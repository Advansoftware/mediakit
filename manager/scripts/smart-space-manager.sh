#!/bin/bash
# ===========================================
# MediaKit - Smart Space Manager
# ===========================================
# - Monitora espaço em disco
# - Pausa downloads se < 5GB livres
# - Prioriza arquivos quase completos (>80%)
# - Resume quando tiver espaço
# ===========================================

LOG_FILE="/app/logs/smart-space.log"
MIN_SPACE_GB=5
DOWNLOADS_DIR="/downloads"

# qBittorrent config
QB_HOST="http://qbittorrent:8080"
QB_USER="${QB_USER:-admin}"
QB_PASS="${QB_PASS:-@Brunrego2022}"
COOKIE_FILE="/tmp/qb_smart.cookie"
PAUSED_FLAG="/tmp/mediakit_paused_for_space"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg"
}

# Login no qBittorrent
qb_login() {
    curl -s -X POST "$QB_HOST/api/v2/auth/login" \
        -d "username=$QB_USER&password=$QB_PASS" \
        -c "$COOKIE_FILE" > /dev/null 2>&1
}

# Chamada API qBittorrent
qb_api() {
    local endpoint="$1"
    shift
    curl -s -b "$COOKIE_FILE" "$QB_HOST/api/v2/$endpoint" "$@" 2>/dev/null
}

# Obter espaço livre em GB
get_free_space_gb() {
    local free_kb=$(df "$DOWNLOADS_DIR" 2>/dev/null | tail -1 | awk '{print $4}')
    echo $((free_kb / 1024 / 1024))
}

# Pausar todos os torrents
pause_all_torrents() {
    log "⏸️ Pausando todos os torrents por falta de espaço..."
    qb_api "torrents/pause" -X POST -d "hashes=all"
    touch "$PAUSED_FLAG"
}

# Resumir todos os torrents
resume_all_torrents() {
    log "▶️ Resumindo todos os torrents..."
    qb_api "torrents/resume" -X POST -d "hashes=all"
    rm -f "$PAUSED_FLAG"
}

# Priorizar arquivos quase completos
prioritize_almost_complete() {
    log "🎯 Priorizando arquivos quase completos..."
    
    # Obter lista de torrents
    local torrents=$(qb_api "torrents/info")
    
    # Verificar se resposta é válida e é um JSON array
    if [ -z "$torrents" ] || [ "$torrents" = "Fails." ] || [ "$torrents" = "Forbidden" ]; then
        log "⚠️ Falha na conexão com qBittorrent"
        qb_login
        return 0
    fi
    
    if ! echo "$torrents" | jq -e 'type == "array"' > /dev/null 2>&1; then
        log "⚠️ Resposta inválida do qBittorrent"
        return 0
    fi
    
    local count=$(echo "$torrents" | jq 'length')
    if [ "$count" = "0" ] || [ -z "$count" ]; then
        log "⚠️ Sem torrents ativos"
        return 0
    fi
    
    log "🔍 Encontrados $count torrents"
    
    # Para cada torrent
    echo "$torrents" | jq -r '.[].hash // empty' 2>/dev/null | while read -r hash; do
        [ -z "$hash" ] && continue
        
        # Obter arquivos do torrent
        local files=$(qb_api "torrents/files?hash=$hash")
        
        if ! echo "$files" | jq -e '.' > /dev/null 2>&1; then
            continue
        fi
        
        local total=$(echo "$files" | jq 'length')
        local adjusted=0
        
        # Processar cada arquivo
        for idx in $(seq 0 $((total - 1))); do
            local priority=$(echo "$files" | jq -r ".[$idx].priority")
            local progress=$(echo "$files" | jq -r ".[$idx].progress")
            
            # Pular arquivos desabilitados
            [ "$priority" = "0" ] && continue
            
            # Calcular porcentagem
            local pct=$(echo "$progress" | awk '{printf "%.0f", $1 * 100}')
            
            # Definir nova prioridade baseada no progresso
            local new_priority=1
            if [ "$pct" -ge 95 ]; then
                new_priority=7  # Máxima - quase terminando!
            elif [ "$pct" -ge 80 ]; then
                new_priority=6  # Alta
            elif [ "$pct" -ge 50 ]; then
                new_priority=4  # Normal-alta
            fi
            
            # Atualizar se diferente
            if [ "$new_priority" != "$priority" ]; then
                qb_api "torrents/filePrio" -X POST \
                    -d "hash=$hash&id=$idx&priority=$new_priority" > /dev/null 2>&1
                adjusted=$((adjusted + 1))
            fi
        done
        
        [ "$adjusted" -gt 0 ] && log "   📁 Ajustadas $adjusted prioridades no torrent"
    done
    
    log "✅ Prioridades ajustadas"
}

# Função principal
main() {
    log "=================================================="
    log "🧠 Smart Space Manager"
    log "=================================================="
    
    # Login no qBittorrent
    qb_login
    
    # Verificar espaço disponível
    local free_gb=$(get_free_space_gb)
    log "💾 Espaço livre: ${free_gb}GB (mínimo: ${MIN_SPACE_GB}GB)"
    
    # Se espaço crítico
    if [ "$free_gb" -lt "$MIN_SPACE_GB" ]; then
        log "🚨 ESPAÇO CRÍTICO!"
        
        # Pausar downloads se ainda não pausou
        if [ ! -f "$PAUSED_FLAG" ]; then
            pause_all_torrents
        fi
        
        # Forçar sync-cloud para liberar espaço
        log "📤 Forçando sincronização com cloud..."
        /app/scripts/sync-cloud.sh
        
        # Verificar espaço novamente
        free_gb=$(get_free_space_gb)
        log "💾 Espaço após limpeza: ${free_gb}GB"
        
        if [ "$free_gb" -ge "$MIN_SPACE_GB" ]; then
            log "✅ Espaço recuperado!"
            resume_all_torrents
            prioritize_almost_complete
        else
            log "⚠️ Espaço ainda crítico. Downloads permanecem pausados."
            log "   Aguardando sync-cloud mover mais arquivos..."
        fi
    else
        # Espaço ok
        
        # Se estava pausado por espaço, resumir
        if [ -f "$PAUSED_FLAG" ]; then
            log "✅ Espaço recuperado!"
            resume_all_torrents
        fi
        
        # Priorizar arquivos quase completos
        prioritize_almost_complete
    fi
    
    log "=================================================="
}

main "$@"
