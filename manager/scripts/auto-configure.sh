#!/bin/bash
# ===========================================
# MediaKit - Auto Configuração Completa
# Configura TUDO automaticamente na primeira execução
# ===========================================

set -e

LOG_FILE="/app/logs/auto-configure.log"
CONFIG_DIR="/app/config"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_success() { log "${GREEN}✅ $1${NC}"; }
log_warn() { log "${YELLOW}⚠️  $1${NC}"; }
log_error() { log "${RED}❌ $1${NC}"; }
log_info() { log "${BLUE}ℹ️  $1${NC}"; }

# Gerar API Key aleatória
generate_api_key() {
    openssl rand -hex 16
}

# Aguardar serviço ficar online
wait_for_service() {
    local name=$1
    local url=$2
    local max_attempts=${3:-30}
    local attempt=0
    
    log_info "Aguardando $name ficar online..."
    
    while [ $attempt -lt $max_attempts ]; do
        local code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "$url" 2>/dev/null)
        if echo "$code" | grep -qE "200|401|302|307"; then
            log_success "$name está online!"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    log_error "$name não respondeu após $max_attempts tentativas"
    return 1
}

# Extrair API Key dos arquivos de configuração
get_api_key() {
    local config_file=$1
    # Usar sed pois grep -P não está disponível no Alpine BusyBox
    if [ -f "$config_file" ]; then
        sed -n 's/.*<ApiKey>\([^<]*\)<\/ApiKey>.*/\1/p' "$config_file" | head -1
    else
        echo ""
    fi
}

# ===========================================
# CONFIGURAÇÃO DO QBITTORRENT
# ===========================================
configure_qbittorrent() {
    log_info "Configurando qBittorrent..."
    
    local QB_URL="http://qbittorrent:8080"
    local QB_USER="${MEDIAKIT_USER:-admin}"
    local QB_PASS="${MEDIAKIT_PASS:-adminadmin}"
    
    wait_for_service "qBittorrent" "$QB_URL"
    
    # Autenticar (primeiro tenta com credenciais padrão, depois com as configuradas)
    # qBittorrent inicia com adminadmin como senha padrão
    if ! curl -s -c /tmp/qb_cookies.txt "$QB_URL/api/v2/auth/login" \
        -d "username=$QB_USER&password=$QB_PASS" | grep -q "Ok"; then
        # Tentar com senha padrão do linuxserver
        curl -s -c /tmp/qb_cookies.txt "$QB_URL/api/v2/auth/login" \
            -d "username=admin&password=adminadmin" > /dev/null
        
        # Alterar para as credenciais configuradas
        curl -s -b /tmp/qb_cookies.txt "$QB_URL/api/v2/app/setPreferences" \
            -d "json={\"web_ui_username\":\"$QB_USER\",\"web_ui_password\":\"$QB_PASS\"}" > /dev/null
        
        # Re-autenticar com novas credenciais
        curl -s -c /tmp/qb_cookies.txt "$QB_URL/api/v2/auth/login" \
            -d "username=$QB_USER&password=$QB_PASS" > /dev/null
    fi
    
    # Configurar preferências
    curl -s -b /tmp/qb_cookies.txt "$QB_URL/api/v2/app/setPreferences" \
        -d 'json={
            "save_path": "/downloads/",
            "temp_path": "/downloads/incomplete/",
            "temp_path_enabled": true,
            "max_active_downloads": 3,
            "max_active_torrents": 5,
            "max_active_uploads": 3,
            "dont_count_slow_torrents": true,
            "add_trackers_enabled": false,
            "auto_delete_mode": 0,
            "autorun_enabled": false,
            "preallocate_all": false,
            "incomplete_files_ext": true
        }' > /dev/null
    
    # Criar categorias para Sonarr e Radarr
    log_info "Criando categorias para Sonarr e Radarr..."
    curl -s -b /tmp/qb_cookies.txt "$QB_URL/api/v2/torrents/createCategory" \
        -d "category=tv-sonarr&savePath=/downloads/" > /dev/null 2>&1
    curl -s -b /tmp/qb_cookies.txt "$QB_URL/api/v2/torrents/createCategory" \
        -d "category=movies-radarr&savePath=/downloads/" > /dev/null 2>&1
    
    log_success "qBittorrent configurado com categorias!"
}

# ===========================================
# CONFIGURAÇÃO DO PROWLARR
# ===========================================
configure_prowlarr() {
    log_info "Configurando Prowlarr..."
    
    local PROWLARR_URL="http://prowlarr:9696"
    local PROWLARR_CONFIG="/app/config/prowlarr/config.xml"
    
    wait_for_service "Prowlarr" "$PROWLARR_URL"
    
    local API_KEY=$(get_api_key "$PROWLARR_CONFIG")
    
    if [ -z "$API_KEY" ]; then
        log_error "Não foi possível obter API Key do Prowlarr"
        return 1
    fi
    
    echo "$API_KEY" > "$CONFIG_DIR/.prowlarr_api"
    
    # Criar App Profile se não existir
    local PROFILE_EXISTS=$(curl -s "$PROWLARR_URL/api/v1/appprofile" \
        -H "X-Api-Key: $API_KEY" | jq 'length')
    
    if [ "$PROFILE_EXISTS" -eq 0 ]; then
        curl -s -X POST "$PROWLARR_URL/api/v1/appprofile" \
            -H "X-Api-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "Standard",
                "enableRss": true,
                "enableAutomaticSearch": true,
                "enableInteractiveSearch": true,
                "minimumSeeders": 1
            }' > /dev/null
    fi
    
    log_success "Prowlarr configurado! API Key: $API_KEY"
}

# ===========================================
# CONFIGURAÇÃO DO RADARR
# ===========================================
configure_radarr() {
    log_info "Configurando Radarr..."
    
    local RADARR_URL="http://radarr:7878"
    local RADARR_CONFIG="/app/config/radarr/config.xml"
    
    wait_for_service "Radarr" "$RADARR_URL"
    
    local API_KEY=$(get_api_key "$RADARR_CONFIG")
    
    if [ -z "$API_KEY" ]; then
        log_error "Não foi possível obter API Key do Radarr"
        return 1
    fi
    
    echo "$API_KEY" > "$CONFIG_DIR/.radarr_api"
    
    # Configurar Root Folder
    local ROOT_EXISTS=$(curl -s "$RADARR_URL/api/v3/rootfolder" \
        -H "X-Api-Key: $API_KEY" | jq 'length')
    
    if [ "$ROOT_EXISTS" -eq 0 ]; then
        curl -s -X POST "$RADARR_URL/api/v3/rootfolder" \
            -H "X-Api-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            -d '{"path": "/movies"}' > /dev/null
        log_info "Root folder /movies adicionado ao Radarr"
    fi
    
    # Configurar Download Client (qBittorrent)
    local DC_EXISTS=$(curl -s "$RADARR_URL/api/v3/downloadclient" \
        -H "X-Api-Key: $API_KEY" | jq 'length')
    
    if [ "$DC_EXISTS" -eq 0 ]; then
        curl -s -X POST "$RADARR_URL/api/v3/downloadclient" \
            -H "X-Api-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "qBittorrent",
                "implementation": "QBittorrent",
                "configContract": "QBittorrentSettings",
                "enable": true,
                "protocol": "torrent",
                "priority": 1,
                "fields": [
                    {"name": "host", "value": "qbittorrent"},
                    {"name": "port", "value": 8080},
                    {"name": "username", "value": "admin"},
                    {"name": "password", "value": "@Brunrego2022"},
                    {"name": "movieCategory", "value": "movies"},
                    {"name": "recentMoviePriority", "value": 0},
                    {"name": "olderMoviePriority", "value": 0},
                    {"name": "initialState", "value": 0},
                    {"name": "sequentialOrder", "value": false},
                    {"name": "firstAndLast", "value": false}
                ]
            }' > /dev/null
        log_info "qBittorrent adicionado como Download Client no Radarr"
    fi
    
    # Criar Custom Formats para PT-BR
    configure_radarr_custom_formats "$RADARR_URL" "$API_KEY"
    
    log_success "Radarr configurado! API Key: $API_KEY"
}

configure_radarr_custom_formats() {
    local URL=$1
    local API_KEY=$2
    
    log_info "Configurando Custom Formats PT-BR no Radarr..."
    
    # Custom Format: Portuguese BR Audio
    local CF_PTBR=$(curl -s "$URL/api/v3/customformat" -H "X-Api-Key: $API_KEY" | jq '[.[] | select(.name == "Portuguese BR Audio")] | length')
    
    if [ "$CF_PTBR" -eq 0 ]; then
        curl -s -X POST "$URL/api/v3/customformat" \
            -H "X-Api-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "Portuguese BR Audio",
                "includeCustomFormatWhenRenaming": true,
                "specifications": [{
                    "name": "Portuguese BR",
                    "implementation": "LanguageSpecification",
                    "negate": false,
                    "required": true,
                    "fields": [{"name": "value", "value": 18}]
                }]
            }' > /dev/null
    fi
    
    # Custom Format: No Portuguese (Reject)
    local CF_NO_PT=$(curl -s "$URL/api/v3/customformat" -H "X-Api-Key: $API_KEY" | jq '[.[] | select(.name == "No Portuguese (Reject)")] | length')
    
    if [ "$CF_NO_PT" -eq 0 ]; then
        curl -s -X POST "$URL/api/v3/customformat" \
            -H "X-Api-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "No Portuguese (Reject)",
                "includeCustomFormatWhenRenaming": false,
                "specifications": [{
                    "name": "Not Portuguese BR",
                    "implementation": "LanguageSpecification",
                    "negate": true,
                    "required": true,
                    "fields": [{"name": "value", "value": 18}]
                }]
            }' > /dev/null
    fi
    
    # Atualizar Quality Profiles para usar Custom Formats
    local PROFILES=$(curl -s "$URL/api/v3/qualityprofile" -H "X-Api-Key: $API_KEY")
    local FORMATS=$(curl -s "$URL/api/v3/customformat" -H "X-Api-Key: $API_KEY")
    
    local CF_PTBR_ID=$(echo "$FORMATS" | jq '.[] | select(.name == "Portuguese BR Audio") | .id')
    local CF_NO_PT_ID=$(echo "$FORMATS" | jq '.[] | select(.name == "No Portuguese (Reject)") | .id')
    
    if [ -n "$CF_PTBR_ID" ] && [ -n "$CF_NO_PT_ID" ]; then
        echo "$PROFILES" | jq -c '.[]' | while read -r profile; do
            local PROFILE_ID=$(echo "$profile" | jq '.id')
            
            # Atualizar profile com Custom Formats e idioma PT-BR
            echo "$profile" | jq --argjson ptbr_id "$CF_PTBR_ID" --argjson nopt_id "$CF_NO_PT_ID" '
                .language = {"id": 30, "name": "Portuguese (Brazil)"} |
                .formatItems = [
                    {"format": $ptbr_id, "name": "Portuguese BR Audio", "score": 1000},
                    {"format": $nopt_id, "name": "No Portuguese (Reject)", "score": -10000}
                ] |
                .minFormatScore = 1
            ' > /tmp/profile_update.json
            
            curl -s -X PUT "$URL/api/v3/qualityprofile/$PROFILE_ID" \
                -H "X-Api-Key: $API_KEY" \
                -H "Content-Type: application/json" \
                -d @/tmp/profile_update.json > /dev/null
        done
        
        log_info "Quality Profiles atualizados para priorizar PT-BR"
    fi
}

# ===========================================
# CONFIGURAÇÃO DO SONARR
# ===========================================
configure_sonarr() {
    log_info "Configurando Sonarr..."
    
    local SONARR_URL="http://sonarr:8989"
    local SONARR_CONFIG="/app/config/sonarr/config.xml"
    
    wait_for_service "Sonarr" "$SONARR_URL"
    
    local API_KEY=$(get_api_key "$SONARR_CONFIG")
    
    if [ -z "$API_KEY" ]; then
        log_error "Não foi possível obter API Key do Sonarr"
        return 1
    fi
    
    echo "$API_KEY" > "$CONFIG_DIR/.sonarr_api"
    
    # Configurar Root Folder
    local ROOT_EXISTS=$(curl -s "$SONARR_URL/api/v3/rootfolder" \
        -H "X-Api-Key: $API_KEY" | jq 'length')
    
    if [ "$ROOT_EXISTS" -eq 0 ]; then
        curl -s -X POST "$SONARR_URL/api/v3/rootfolder" \
            -H "X-Api-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            -d '{"path": "/tv"}' > /dev/null
        log_info "Root folder /tv adicionado ao Sonarr"
    fi
    
    # Configurar Download Client (qBittorrent)
    local DC_EXISTS=$(curl -s "$SONARR_URL/api/v3/downloadclient" \
        -H "X-Api-Key: $API_KEY" | jq 'length')
    
    if [ "$DC_EXISTS" -eq 0 ]; then
        curl -s -X POST "$SONARR_URL/api/v3/downloadclient" \
            -H "X-Api-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "qBittorrent",
                "implementation": "QBittorrent",
                "configContract": "QBittorrentSettings",
                "enable": true,
                "protocol": "torrent",
                "priority": 1,
                "fields": [
                    {"name": "host", "value": "qbittorrent"},
                    {"name": "port", "value": 8080},
                    {"name": "username", "value": "admin"},
                    {"name": "password", "value": "@Brunrego2022"},
                    {"name": "tvCategory", "value": "tv"},
                    {"name": "recentTvPriority", "value": 0},
                    {"name": "olderTvPriority", "value": 0},
                    {"name": "initialState", "value": 0},
                    {"name": "sequentialOrder", "value": false},
                    {"name": "firstAndLast", "value": false}
                ]
            }' > /dev/null
        log_info "qBittorrent adicionado como Download Client no Sonarr"
    fi
    
    # Criar Custom Formats para PT-BR
    configure_sonarr_custom_formats "$SONARR_URL" "$API_KEY"
    
    log_success "Sonarr configurado! API Key: $API_KEY"
}

configure_sonarr_custom_formats() {
    local URL=$1
    local API_KEY=$2
    
    log_info "Configurando Custom Formats PT-BR no Sonarr..."
    
    # Custom Format: Portuguese BR Audio
    local CF_PTBR=$(curl -s "$URL/api/v3/customformat" -H "X-Api-Key: $API_KEY" | jq '[.[] | select(.name == "Portuguese BR Audio")] | length')
    
    if [ "$CF_PTBR" -eq 0 ]; then
        curl -s -X POST "$URL/api/v3/customformat" \
            -H "X-Api-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "Portuguese BR Audio",
                "includeCustomFormatWhenRenaming": true,
                "specifications": [{
                    "name": "Portuguese BR",
                    "implementation": "LanguageSpecification",
                    "negate": false,
                    "required": true,
                    "fields": [{"name": "value", "value": 18}]
                }]
            }' > /dev/null
    fi
    
    # Custom Format: No Portuguese (Reject)
    local CF_NO_PT=$(curl -s "$URL/api/v3/customformat" -H "X-Api-Key: $API_KEY" | jq '[.[] | select(.name == "No Portuguese (Reject)")] | length')
    
    if [ "$CF_NO_PT" -eq 0 ]; then
        curl -s -X POST "$URL/api/v3/customformat" \
            -H "X-Api-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "No Portuguese (Reject)",
                "includeCustomFormatWhenRenaming": false,
                "specifications": [{
                    "name": "Not Portuguese BR",
                    "implementation": "LanguageSpecification",
                    "negate": true,
                    "required": true,
                    "fields": [{"name": "value", "value": 18}]
                }]
            }' > /dev/null
    fi
    
    # Custom Format: Anime PT-BR Subs
    local CF_ANIME=$(curl -s "$URL/api/v3/customformat" -H "X-Api-Key: $API_KEY" | jq '[.[] | select(.name == "Anime PT-BR Subs")] | length')
    
    if [ "$CF_ANIME" -eq 0 ]; then
        curl -s -X POST "$URL/api/v3/customformat" \
            -H "X-Api-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "Anime PT-BR Subs",
                "includeCustomFormatWhenRenaming": true,
                "specifications": [
                    {
                        "name": "Japanese Audio",
                        "implementation": "LanguageSpecification",
                        "negate": false,
                        "required": true,
                        "fields": [{"name": "value", "value": 8}]
                    },
                    {
                        "name": "BR Subtitles in Name",
                        "implementation": "ReleaseTitleSpecification",
                        "negate": false,
                        "required": false,
                        "fields": [{"name": "value", "value": "(leg|sub|pt-?br|portugues|brazilian|dublado)"}]
                    }
                ]
            }' > /dev/null
    fi
    
    # Atualizar Quality Profiles
    local PROFILES=$(curl -s "$URL/api/v3/qualityprofile" -H "X-Api-Key: $API_KEY")
    local FORMATS=$(curl -s "$URL/api/v3/customformat" -H "X-Api-Key: $API_KEY")
    
    local CF_PTBR_ID=$(echo "$FORMATS" | jq '.[] | select(.name == "Portuguese BR Audio") | .id')
    local CF_NO_PT_ID=$(echo "$FORMATS" | jq '.[] | select(.name == "No Portuguese (Reject)") | .id')
    local CF_ANIME_ID=$(echo "$FORMATS" | jq '.[] | select(.name == "Anime PT-BR Subs") | .id')
    
    if [ -n "$CF_PTBR_ID" ] && [ -n "$CF_NO_PT_ID" ]; then
        echo "$PROFILES" | jq -c '.[]' | while read -r profile; do
            local PROFILE_ID=$(echo "$profile" | jq '.id')
            
            echo "$profile" | jq --argjson ptbr_id "$CF_PTBR_ID" --argjson nopt_id "$CF_NO_PT_ID" --argjson anime_id "${CF_ANIME_ID:-0}" '
                .formatItems = [
                    {"format": $ptbr_id, "name": "Portuguese BR Audio", "score": 1000},
                    {"format": $nopt_id, "name": "No Portuguese (Reject)", "score": -10000}
                ] + (if $anime_id > 0 then [{"format": $anime_id, "name": "Anime PT-BR Subs", "score": 1000}] else [] end) |
                .minFormatScore = 1
            ' > /tmp/profile_update.json
            
            curl -s -X PUT "$URL/api/v3/qualityprofile/$PROFILE_ID" \
                -H "X-Api-Key: $API_KEY" \
                -H "Content-Type: application/json" \
                -d @/tmp/profile_update.json > /dev/null
        done
        
        log_info "Quality Profiles do Sonarr atualizados para PT-BR"
    fi
}

# ===========================================
# VINCULAR PROWLARR COM RADARR E SONARR
# ===========================================
configure_prowlarr_apps() {
    log_info "Vinculando Prowlarr com Radarr e Sonarr..."
    
    local PROWLARR_URL="http://prowlarr:9696"
    local PROWLARR_API=$(cat "$CONFIG_DIR/.prowlarr_api" 2>/dev/null)
    local RADARR_API=$(cat "$CONFIG_DIR/.radarr_api" 2>/dev/null)
    local SONARR_API=$(cat "$CONFIG_DIR/.sonarr_api" 2>/dev/null)
    
    if [ -z "$PROWLARR_API" ]; then
        log_error "API Key do Prowlarr não encontrada"
        return 1
    fi
    
    # Verificar se Radarr já está vinculado
    local RADARR_APP=$(curl -s "$PROWLARR_URL/api/v1/applications" \
        -H "X-Api-Key: $PROWLARR_API" | jq '[.[] | select(.name == "Radarr")] | length')
    
    if [ "$RADARR_APP" -eq 0 ] && [ -n "$RADARR_API" ]; then
        curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
            -H "X-Api-Key: $PROWLARR_API" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"Radarr\",
                \"syncLevel\": \"fullSync\",
                \"implementation\": \"Radarr\",
                \"configContract\": \"RadarrSettings\",
                \"fields\": [
                    {\"name\": \"prowlarrUrl\", \"value\": \"http://prowlarr:9696\"},
                    {\"name\": \"baseUrl\", \"value\": \"http://radarr:7878\"},
                    {\"name\": \"apiKey\", \"value\": \"$RADARR_API\"},
                    {\"name\": \"syncCategories\", \"value\": [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060]}
                ]
            }" > /dev/null
        log_info "Radarr vinculado ao Prowlarr"
    fi
    
    # Verificar se Sonarr já está vinculado
    local SONARR_APP=$(curl -s "$PROWLARR_URL/api/v1/applications" \
        -H "X-Api-Key: $PROWLARR_API" | jq '[.[] | select(.name == "Sonarr")] | length')
    
    if [ "$SONARR_APP" -eq 0 ] && [ -n "$SONARR_API" ]; then
        curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
            -H "X-Api-Key: $PROWLARR_API" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"Sonarr\",
                \"syncLevel\": \"fullSync\",
                \"implementation\": \"Sonarr\",
                \"configContract\": \"SonarrSettings\",
                \"fields\": [
                    {\"name\": \"prowlarrUrl\", \"value\": \"http://prowlarr:9696\"},
                    {\"name\": \"baseUrl\", \"value\": \"http://sonarr:8989\"},
                    {\"name\": \"apiKey\", \"value\": \"$SONARR_API\"},
                    {\"name\": \"syncCategories\", \"value\": [5000, 5010, 5020, 5030, 5040, 5045, 5050]}
                ]
            }" > /dev/null
        log_info "Sonarr vinculado ao Prowlarr"
    fi
    
    log_success "Prowlarr vinculado com sucesso!"
}

# ===========================================
# CONFIGURAR INDEXERS BRASILEIROS
# ===========================================
configure_brazilian_indexers() {
    log_info "Configurando indexers brasileiros..."
    
    local PROWLARR_URL="http://prowlarr:9696"
    local PROWLARR_API=$(cat "$CONFIG_DIR/.prowlarr_api" 2>/dev/null)
    
    if [ -z "$PROWLARR_API" ]; then
        log_error "API Key do Prowlarr não encontrada"
        return 1
    fi
    
    # Aguardar torrent-indexer
    wait_for_service "Torrent Indexer" "http://torrent-indexer:7006" 30 || {
        log_warn "Torrent Indexer não está disponível, pulando indexers brasileiros"
        return 0
    }
    
    # Buscar schema do torrent-indexer
    local SCHEMA=$(curl -s "$PROWLARR_URL/api/v1/indexer/schema" \
        -H "X-Api-Key: $PROWLARR_API" | jq '.[] | select(.definitionName == "torrent-indexer-br")')
    
    if [ -z "$SCHEMA" ] || [ "$SCHEMA" == "null" ]; then
        log_warn "Schema do torrent-indexer-br não encontrado no Prowlarr"
        return 0
    fi
    
    # Lista de indexers brasileiros para adicionar
    declare -A INDEXERS=(
        ["BLUDV (BR)"]=0
        ["Torrent dos Filmes (BR)"]=5
    )
    
    for name in "${!INDEXERS[@]}"; do
        local value=${INDEXERS[$name]}
        
        # Verificar se já existe
        local EXISTS=$(curl -s "$PROWLARR_URL/api/v1/indexer" \
            -H "X-Api-Key: $PROWLARR_API" | jq "[.[] | select(.name == \"$name\")] | length")
        
        if [ "$EXISTS" -eq 0 ]; then
            echo "$SCHEMA" | jq --arg name "$name" --argjson value "$value" '
                .name = $name |
                .enable = true |
                .priority = 1 |
                .appProfileId = 1 |
                del(.id) |
                (.fields[] | select(.name == "baseUrl").value) = "http://torrent-indexer:7006/" |
                (.fields[] | select(.name == "indexer").value) = $value
            ' > /tmp/indexer_add.json
            
            local RESULT=$(curl -s -X POST "$PROWLARR_URL/api/v1/indexer" \
                -H "X-Api-Key: $PROWLARR_API" \
                -H "Content-Type: application/json" \
                -d @/tmp/indexer_add.json)
            
            if echo "$RESULT" | jq -e '.id' > /dev/null 2>&1; then
                log_info "Indexer $name adicionado"
            else
                log_warn "Falha ao adicionar $name: $(echo "$RESULT" | jq -r '.[0].errorMessage // "Erro desconhecido"')"
            fi
        fi
    done
    
    # Sincronizar indexers
    curl -s -X POST "$PROWLARR_URL/api/v1/command" \
        -H "X-Api-Key: $PROWLARR_API" \
        -H "Content-Type: application/json" \
        -d '{"name":"ApplicationIndexerSync"}' > /dev/null
    
    log_success "Indexers brasileiros configurados!"
}

# ===========================================
# CONFIGURAR JELLYSEERR
# ===========================================
configure_jellyseerr() {
    log_info "Configurando Jellyseerr..."
    
    local JELLYSEERR_URL="http://jellyseerr:5055"
    
    wait_for_service "Jellyseerr" "$JELLYSEERR_URL"
    
    # Jellyseerr precisa de configuração manual inicial pelo wizard
    # Mas podemos pré-configurar algumas coisas
    
    log_warn "Jellyseerr requer configuração inicial pelo navegador"
    log_info "Acesse: http://localhost:5055 para completar a configuração"
    
    log_success "Jellyseerr pronto para configuração!"
}

# ===========================================
# CONFIGURAR SCRIPTS DE MOVE-TO-CLOUD
# ===========================================
configure_cloud_scripts() {
    log_info "Configurando scripts de move-to-cloud..."
    
    # Criar script para Sonarr
    mkdir -p "$CONFIG_DIR/sonarr/scripts"
    cat > "$CONFIG_DIR/sonarr/scripts/move-to-cloud-on-import.sh" << 'SCRIPT'
#!/bin/bash
LOG_FILE="/config/logs/move-to-cloud.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

if [ -n "$sonarr_episodefile_path" ]; then
    FILE_PATH="$sonarr_episodefile_path"
    CLOUD_BASE="/cloud-tv"
    LOCAL_BASE="/tv"
    log "📺 Sonarr importou: $FILE_PATH"
else
    exit 0
fi

[ ! -f "$FILE_PATH" ] && exit 1

RELATIVE_PATH="${FILE_PATH#$LOCAL_BASE/}"
CLOUD_PATH="$CLOUD_BASE/$RELATIVE_PATH"
CLOUD_DIR=$(dirname "$CLOUD_PATH")
mkdir -p "$CLOUD_DIR" 2>/dev/null

SIZE=$(du -h "$FILE_PATH" 2>/dev/null | cut -f1)
log "📤 Movendo para cloud: $RELATIVE_PATH ($SIZE)"

if cp "$FILE_PATH" "$CLOUD_PATH" 2>/dev/null; then
    rm -f "$FILE_PATH"
    ln -sf "$CLOUD_PATH" "$FILE_PATH"
    log "✅ Movido e symlink criado"
else
    log "❌ Erro ao copiar"
fi
SCRIPT
    chmod +x "$CONFIG_DIR/sonarr/scripts/move-to-cloud-on-import.sh"
    
    # Criar script para Radarr
    mkdir -p "$CONFIG_DIR/radarr/scripts"
    cat > "$CONFIG_DIR/radarr/scripts/move-to-cloud-on-import.sh" << 'SCRIPT'
#!/bin/bash
LOG_FILE="/config/logs/move-to-cloud.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

if [ -n "$radarr_moviefile_path" ]; then
    FILE_PATH="$radarr_moviefile_path"
    CLOUD_BASE="/cloud-movies"
    LOCAL_BASE="/movies"
    log "🎬 Radarr importou: $FILE_PATH"
else
    exit 0
fi

[ ! -f "$FILE_PATH" ] && exit 1

RELATIVE_PATH="${FILE_PATH#$LOCAL_BASE/}"
CLOUD_PATH="$CLOUD_BASE/$RELATIVE_PATH"
CLOUD_DIR=$(dirname "$CLOUD_PATH")
mkdir -p "$CLOUD_DIR" 2>/dev/null

SIZE=$(du -h "$FILE_PATH" 2>/dev/null | cut -f1)
log "📤 Movendo para cloud: $RELATIVE_PATH ($SIZE)"

if cp "$FILE_PATH" "$CLOUD_PATH" 2>/dev/null; then
    rm -f "$FILE_PATH"
    ln -sf "$CLOUD_PATH" "$FILE_PATH"
    log "✅ Movido e symlink criado"
else
    log "❌ Erro ao copiar"
fi
SCRIPT
    chmod +x "$CONFIG_DIR/radarr/scripts/move-to-cloud-on-import.sh"
    
    # Adicionar notificação no Sonarr
    local SONARR_API=$(cat "$CONFIG_DIR/.sonarr_api" 2>/dev/null)
    if [ -n "$SONARR_API" ]; then
        # Verificar se já existe
        local EXISTS=$(curl -s "http://sonarr:8989/api/v3/notification" -H "X-Api-Key: $SONARR_API" | grep -c "Move to Cloud")
        if [ "$EXISTS" -eq 0 ]; then
            curl -s -X POST "http://sonarr:8989/api/v3/notification" \
                -H "X-Api-Key: $SONARR_API" \
                -H "Content-Type: application/json" \
                -d '{"name":"Move to Cloud","implementation":"CustomScript","configContract":"CustomScriptSettings","onDownload":true,"onUpgrade":true,"fields":[{"name":"path","value":"/config/scripts/move-to-cloud-on-import.sh"}]}' > /dev/null 2>&1
            log_success "Notificação Move to Cloud adicionada no Sonarr"
        fi
    fi
    
    # Adicionar notificação no Radarr
    local RADARR_API=$(cat "$CONFIG_DIR/.radarr_api" 2>/dev/null)
    if [ -n "$RADARR_API" ]; then
        local EXISTS=$(curl -s "http://radarr:7878/api/v3/notification" -H "X-Api-Key: $RADARR_API" | grep -c "Move to Cloud")
        if [ "$EXISTS" -eq 0 ]; then
            curl -s -X POST "http://radarr:7878/api/v3/notification" \
                -H "X-Api-Key: $RADARR_API" \
                -H "Content-Type: application/json" \
                -d '{"name":"Move to Cloud","implementation":"CustomScript","configContract":"CustomScriptSettings","onDownload":true,"onUpgrade":true,"fields":[{"name":"path","value":"/config/scripts/move-to-cloud-on-import.sh"}]}' > /dev/null 2>&1
            log_success "Notificação Move to Cloud adicionada no Radarr"
        fi
    fi
    
    log_success "Scripts de move-to-cloud configurados!"
}

# ===========================================
# MAIN
# ===========================================
main() {
    log "=================================================="
    log "🎬 MediaKit - Auto Configuração Iniciando..."
    log "=================================================="
    
    mkdir -p "$CONFIG_DIR"
    
    # Ordem importante de configuração
    configure_qbittorrent
    configure_prowlarr
    configure_radarr
    configure_sonarr
    configure_prowlarr_apps
    configure_brazilian_indexers
    configure_cloud_scripts
    configure_jellyseerr
    
    log "=================================================="
    log_success "🎉 Auto Configuração Concluída!"
    log "=================================================="
    log ""
    log "📋 Resumo das API Keys:"
    log "   Prowlarr: $(cat $CONFIG_DIR/.prowlarr_api 2>/dev/null || echo 'N/A')"
    log "   Radarr:   $(cat $CONFIG_DIR/.radarr_api 2>/dev/null || echo 'N/A')"
    log "   Sonarr:   $(cat $CONFIG_DIR/.sonarr_api 2>/dev/null || echo 'N/A')"
    log ""
    log "🌐 URLs dos serviços:"
    log "   Jellyfin:       http://localhost:8096"
    log "   Jellyseerr:     http://localhost:5055"
    log "   qBittorrent:    http://localhost:8080"
    log "   Radarr:         http://localhost:7878"
    log "   Sonarr:         http://localhost:8989"
    log "   Prowlarr:       http://localhost:9696"
    log "   Torrent Indexer: http://localhost:7006"
    log ""
}

main "$@"
