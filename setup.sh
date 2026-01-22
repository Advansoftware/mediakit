#!/bin/bash
# ===========================================
# MediaKit - Setup Automatizado Completo
# Execute apenas este script para ter tudo funcionando!
# ===========================================

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Diretório base
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE_DIR"

# Banner
print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║   ███╗   ███╗███████╗██████╗ ██╗ █████╗ ██╗  ██╗██╗████████╗  ║"
    echo "║   ████╗ ████║██╔════╝██╔══██╗██║██╔══██╗██║ ██╔╝██║╚══██╔══╝  ║"
    echo "║   ██╔████╔██║█████╗  ██║  ██║██║███████║█████╔╝ ██║   ██║     ║"
    echo "║   ██║╚██╔╝██║██╔══╝  ██║  ██║██║██╔══██║██╔═██╗ ██║   ██║     ║"
    echo "║   ██║ ╚═╝ ██║███████╗██████╔╝██║██║  ██║██║  ██╗██║   ██║     ║"
    echo "║   ╚═╝     ╚═╝╚══════╝╚═════╝ ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝   ╚═╝     ║"
    echo "║                                                               ║"
    echo "║          🎬 Servidor de Mídia Automatizado 🎬                 ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Logging
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "\n${BOLD}${CYAN}▶ $1${NC}"; }

# Solicitar credenciais
ask_credentials() {
    log_step "Configuração de Credenciais"
    echo ""
    echo -e "${YELLOW}Estas credenciais serão usadas para TODOS os serviços:${NC}"
    echo -e "  • qBittorrent, Rclone WebUI, e configurações internas"
    echo ""
    
    # Username
    while true; do
        read -p "👤 Digite o nome de usuário: " MEDIAKIT_USER
        if [ -n "$MEDIAKIT_USER" ] && [ ${#MEDIAKIT_USER} -ge 3 ]; then
            break
        fi
        echo -e "${RED}   Usuário deve ter pelo menos 3 caracteres${NC}"
    done
    
    # Password
    while true; do
        read -s -p "🔐 Digite a senha: " MEDIAKIT_PASS
        echo ""
        if [ -n "$MEDIAKIT_PASS" ] && [ ${#MEDIAKIT_PASS} -ge 6 ]; then
            read -s -p "🔐 Confirme a senha: " MEDIAKIT_PASS_CONFIRM
            echo ""
            if [ "$MEDIAKIT_PASS" = "$MEDIAKIT_PASS_CONFIRM" ]; then
                break
            else
                echo -e "${RED}   As senhas não coincidem${NC}"
            fi
        else
            echo -e "${RED}   Senha deve ter pelo menos 6 caracteres${NC}"
        fi
    done
    
    echo ""
    log_success "Credenciais configuradas para usuário: $MEDIAKIT_USER"
}

# Verificar Docker
check_docker() {
    log_step "Verificando Docker..."
    
    if ! command -v docker &> /dev/null; then
        log_warn "Docker não está instalado!"
        log "Instalando Docker automaticamente..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker
        systemctl start docker
    fi
    
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose não encontrado!"
        exit 1
    fi
    
    log_success "Docker instalado e funcionando"
}

# Criar estrutura de diretórios
create_directories() {
    log_step "Criando estrutura de diretórios..."
    
    # Configurações dos serviços
    mkdir -p config/{jellyfin,jellyseerr,qbittorrent,rclone,prowlarr,radarr,sonarr}
    mkdir -p config/prowlarr/Definitions/Custom
    
    # Cache
    mkdir -p cache/jellyfin/{images,transcodes}
    
    # Mídia
    mkdir -p media/{movies,tv,music,books}
    
    # Downloads
    mkdir -p downloads/incomplete
    
    # Cloud mount point
    mkdir -p cloud/{movies,tv,downloads-temp}
    
    # Logs
    mkdir -p logs
    
    log_success "Diretórios criados"
}

# Configurar .env
setup_env() {
    log_step "Configurando variáveis de ambiente..."
    
    PUID=$(id -u)
    PGID=$(id -g)
    
    cat > .env << EOF
# ===========================================
# MEDIAKIT - Configuração Automática
# Gerado em: $(date)
# ===========================================

# Timezone
TZ=America/Sao_Paulo

# User/Group ID
PUID=$PUID
PGID=$PGID

# Credenciais (usadas em todos os serviços)
MEDIAKIT_USER=$MEDIAKIT_USER
MEDIAKIT_PASS=$MEDIAKIT_PASS

# URLs públicas (ajuste conforme necessário)
JELLYFIN_URL=http://localhost:8096

# Aliases para compatibilidade
RCLONE_USER=$MEDIAKIT_USER
RCLONE_PASS=$MEDIAKIT_PASS
QB_USER=$MEDIAKIT_USER
QB_PASS=$MEDIAKIT_PASS
EOF

    log_success "Arquivo .env criado com PUID=$PUID PGID=$PGID"
}

# Copiar definição do indexer brasileiro
setup_indexer_definition() {
    log_step "Configurando indexer brasileiro..."
    
    cat > config/prowlarr/Definitions/Custom/torrent-indexer-br.yml << 'YAML'
---
id: torrent-indexer-br
name: Torrent Indexer BR
description: "Indexing Brazilian Torrent websites"
language: pt-BR
type: public
encoding: UTF-8
links:
  - http://torrent-indexer:7006/

caps:
  categories:
    Movies: Movies
    TV: TV
  modes:
    search: [q]
    tv-search: [q, season]
    movie-search: [q]

settings:
  - name: indexer
    type: select
    label: Indexer
    default: bludv
    options:
      search: Torrent-Indexer Cache
      bludv: BLUDV
      comando_torrents: Comando Torrents
      torrent-dos-filmes: Torrent dos Filmes

search:
  paths:
    - path: "{{ if eq .Config.indexer \"search\" }}/search{{ else }}/indexers/{{ .Config.indexer }}{{ end }}"
      response:
        type: json
  inputs:
    filter_results: "true"
    q: "{{ .Keywords }}"
  rows:
    selector: $.results
  fields:
    download:
      selector: magnet_link
    title:
      selector: title
    size:
      selector: size
    seeders:
      selector: seed_count
    leechers:
      selector: leech_count
    category:
      text: "Movies"
YAML

    log_success "Indexer brasileiro configurado"
}

# Configurar permissões
set_permissions() {
    log_step "Configurando permissões..."
    
    PUID=$(id -u)
    PGID=$(id -g)
    
    chown -R $PUID:$PGID config/ 2>/dev/null || true
    chown -R $PUID:$PGID cache/ 2>/dev/null || true
    chown -R $PUID:$PGID media/ 2>/dev/null || true
    chown -R $PUID:$PGID downloads/ 2>/dev/null || true
    chown -R $PUID:$PGID cloud/ 2>/dev/null || true
    chown -R $PUID:$PGID logs/ 2>/dev/null || true
    
    chmod 755 manager/entrypoint.sh 2>/dev/null || true
    chmod 755 manager/scripts/*.sh 2>/dev/null || true
    
    log_success "Permissões configuradas"
}

# Criar rede Docker
create_network() {
    log_step "Configurando rede Docker..."
    
    if ! docker network inspect proxy-network &> /dev/null; then
        docker network create proxy-network
        log_success "Rede proxy-network criada"
    else
        log_success "Rede proxy-network já existe"
    fi
}

# Limpar configuração anterior para reconfigurar
reset_configuration() {
    log_step "Preparando para nova configuração..."
    rm -f config/.configured
    log_success "Pronto para auto-configuração"
}

# Iniciar serviços
start_services() {
    log_step "Iniciando todos os serviços..."
    
    # Parar serviços existentes
    docker compose down 2>/dev/null || true
    
    # Build do manager
    docker compose build mediakit-manager
    
    # Iniciar com profile full (todos os serviços)
    docker compose --profile full up -d
    
    log_success "Serviços iniciados"
}

# Aguardar serviços
wait_for_services() {
    log_step "Aguardando serviços ficarem prontos..."
    
    local services=("8096" "5055" "8080" "9696" "7878" "8989")
    local max_wait=120
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        local all_ready=true
        
        for port in "${services[@]}"; do
            if ! curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port" 2>/dev/null | grep -qE "200|302|401"; then
                all_ready=false
                break
            fi
        done
        
        if $all_ready; then
            echo ""
            log_success "Todos os serviços estão prontos!"
            return 0
        fi
        
        sleep 5
        waited=$((waited + 5))
        echo -ne "\r${YELLOW}[!]${NC} Aguardando... ($waited/${max_wait}s)"
    done
    
    echo ""
    log_warn "Alguns serviços ainda podem estar inicializando"
}

# Configuração do rclone (Google Drive)
setup_rclone() {
    log_step "Configuração do Google Drive (opcional)"
    
    echo ""
    echo -e "${YELLOW}Para sincronizar com Google Drive, você precisa autenticar o rclone.${NC}"
    echo ""
    
    read -p "Deseja configurar o Google Drive agora? (s/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        echo ""
        log "Iniciando configuração do rclone..."
        echo ""
        echo -e "${CYAN}Siga as instruções:${NC}"
        echo "1. Digite 'n' para nova configuração"
        echo "2. Nome: 'gdrive'"
        echo "3. Tipo: 'Google Drive' (18 ou similar)"
        echo "4. Deixe client_id e client_secret em branco"
        echo "5. Escopo: 'full access'"
        echo "6. Siga as instruções de autenticação"
        echo ""
        
        docker run --rm -it \
            -v "$BASE_DIR/config/rclone:/config/rclone" \
            rclone/rclone:latest \
            config --config /config/rclone/rclone.conf
        
        if [ -f "$BASE_DIR/config/rclone/rclone.conf" ] && grep -q "\[gdrive\]" "$BASE_DIR/config/rclone/rclone.conf"; then
            log_success "Google Drive configurado!"
            
            log "Criando pastas no Google Drive..."
            docker run --rm \
                -v "$BASE_DIR/config/rclone:/config/rclone" \
                rclone/rclone:latest \
                mkdir gdrive:MediaKit/movies --config /config/rclone/rclone.conf 2>/dev/null || true
            docker run --rm \
                -v "$BASE_DIR/config/rclone:/config/rclone" \
                rclone/rclone:latest \
                mkdir gdrive:MediaKit/tv --config /config/rclone/rclone.conf 2>/dev/null || true
            
            log_success "Estrutura do Drive criada"
        else
            log_warn "Configuração do Drive não completada"
        fi
    else
        log "Pulando configuração do Google Drive"
    fi
}

# Mostrar resumo final
show_summary() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}              ${GREEN}${BOLD}✅ INSTALAÇÃO CONCLUÍDA!${NC}                        ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}🔐 Credenciais (para todos os serviços):${NC}"
    echo -e "   Usuário: ${GREEN}$MEDIAKIT_USER${NC}"
    echo -e "   Senha:   ${GREEN}(a que você digitou)${NC}"
    echo ""
    echo -e "${BOLD}🌐 URLs dos Serviços:${NC}"
    echo -e "   ${GREEN}Jellyfin${NC}        → http://localhost:8096"
    echo -e "   ${GREEN}Jellyseerr${NC}      → http://localhost:5055"
    echo -e "   ${GREEN}qBittorrent${NC}     → http://localhost:8080"
    echo -e "   ${GREEN}Radarr${NC}          → http://localhost:7878"
    echo -e "   ${GREEN}Sonarr${NC}          → http://localhost:8989"
    echo -e "   ${GREEN}Prowlarr${NC}        → http://localhost:9696"
    echo -e "   ${GREEN}Torrent Indexer${NC} → http://localhost:7006"
    echo ""
    echo -e "${BOLD}📋 Próximos Passos:${NC}"
    echo -e "   1. Acesse ${CYAN}http://localhost:5055${NC} (Jellyseerr)"
    echo -e "   2. Vincule com Jellyfin quando solicitado"
    echo -e "   3. Comece a solicitar filmes e séries em PT-BR!"
    echo ""
    echo -e "${BOLD}📁 Estrutura:${NC}"
    echo -e "   • Downloads     → ./downloads/"
    echo -e "   • Mídia local   → ./media/"
    echo -e "   • Google Drive  → ./cloud/"
    echo -e "   • Configurações → ./config/"
    echo -e "   • Logs          → ./logs/"
    echo ""
    echo -e "${BOLD}🔧 Comandos Úteis:${NC}"
    echo -e "   ${YELLOW}docker compose logs -f${NC}              → Ver logs"
    echo -e "   ${YELLOW}docker compose --profile full up -d${NC} → Reiniciar"
    echo -e "   ${YELLOW}docker compose down${NC}                 → Parar tudo"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    log "O MediaKit Manager está configurando automaticamente os serviços..."
    log "Aguarde alguns minutos para a configuração automática completar."
    echo ""
}

# Main
main() {
    print_banner
    
    log "Iniciando instalação automatizada do MediaKit..."
    echo ""
    
    ask_credentials
    check_docker
    create_directories
    setup_env
    setup_indexer_definition
    set_permissions
    create_network
    reset_configuration
    start_services
    wait_for_services
    setup_rclone
    show_summary
}

# Executar
main "$@"
