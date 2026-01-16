#!/bin/bash

# ==========================================
# MediaKit - Script de Sincronização com Cloud
# ==========================================

set -e

echo "☁️  MediaKit - Sincronização com Cloud"
echo "======================================="
echo ""

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configurações
REMOTE_NAME="${RCLONE_REMOTE:-gdrive}"
SYNC_MODE="${1:-sync}"  # sync, copy, bisync
SOURCE_PATH="/data/media"
DEST_PATH="$REMOTE_NAME:media"

# Diretório base
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Verificar se rclone está configurado
check_config() {
    echo -e "${YELLOW}🔍 Verificando configuração do rclone...${NC}"
    
    if ! docker exec rclone rclone listremotes | grep -q "$REMOTE_NAME:"; then
        echo -e "${RED}❌ Remote '$REMOTE_NAME' não encontrado!${NC}"
        echo ""
        echo "Configure o rclone primeiro:"
        echo "  docker exec -it rclone rclone config"
        echo ""
        echo "Ou defina outro remote:"
        echo "  RCLONE_REMOTE=meuremote $0"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Remote '$REMOTE_NAME' configurado!${NC}"
}

# Mostrar uso
show_usage() {
    echo "Uso: $0 [modo]"
    echo ""
    echo "Modos disponíveis:"
    echo "  sync    - Sincroniza local -> cloud (padrão)"
    echo "  copy    - Copia local -> cloud (não deleta arquivos na cloud)"
    echo "  bisync  - Sincronização bidirecional"
    echo "  mount   - Monta o remote como pasta local"
    echo "  unmount - Desmonta o remote"
    echo "  status  - Mostra status da sincronização"
    echo ""
    echo "Exemplos:"
    echo "  $0 sync"
    echo "  $0 copy"
    echo "  RCLONE_REMOTE=onedrive $0 sync"
}

# Sync local -> cloud
do_sync() {
    echo -e "${YELLOW}🔄 Sincronizando $SOURCE_PATH -> $DEST_PATH...${NC}"
    
    docker exec rclone rclone sync \
        "$SOURCE_PATH" \
        "$DEST_PATH" \
        --progress \
        --stats 10s \
        --log-file=/config/rclone/sync.log \
        --log-level INFO
    
    echo -e "${GREEN}✅ Sincronização concluída!${NC}"
}

# Copy local -> cloud
do_copy() {
    echo -e "${YELLOW}📤 Copiando $SOURCE_PATH -> $DEST_PATH...${NC}"
    
    docker exec rclone rclone copy \
        "$SOURCE_PATH" \
        "$DEST_PATH" \
        --progress \
        --stats 10s \
        --log-file=/config/rclone/copy.log \
        --log-level INFO
    
    echo -e "${GREEN}✅ Cópia concluída!${NC}"
}

# Bisync (bidirecional)
do_bisync() {
    echo -e "${YELLOW}🔁 Sincronização bidirecional $SOURCE_PATH <-> $DEST_PATH...${NC}"
    
    # Primeira execução precisa de --resync
    if [ ! -f "$BASE_DIR/config/rclone/.bisync_initialized" ]; then
        echo -e "${YELLOW}⚠️  Primeira execução do bisync, inicializando...${NC}"
        docker exec rclone rclone bisync \
            "$SOURCE_PATH" \
            "$DEST_PATH" \
            --resync \
            --progress
        touch "$BASE_DIR/config/rclone/.bisync_initialized"
    else
        docker exec rclone rclone bisync \
            "$SOURCE_PATH" \
            "$DEST_PATH" \
            --progress \
            --log-file=/config/rclone/bisync.log \
            --log-level INFO
    fi
    
    echo -e "${GREEN}✅ Sincronização bidirecional concluída!${NC}"
}

# Mount remote
do_mount() {
    echo -e "${YELLOW}📂 Montando $REMOTE_NAME em /cloud...${NC}"
    
    docker exec -d rclone rclone mount \
        "$REMOTE_NAME:" \
        /cloud \
        --allow-other \
        --vfs-cache-mode writes \
        --vfs-cache-max-size 10G \
        --log-file=/config/rclone/mount.log \
        --log-level INFO
    
    echo -e "${GREEN}✅ Remote montado em /cloud!${NC}"
    echo "Acesse os arquivos em: $BASE_DIR/cloud/"
}

# Unmount remote
do_unmount() {
    echo -e "${YELLOW}📂 Desmontando /cloud...${NC}"
    
    docker exec rclone fusermount -u /cloud 2>/dev/null || true
    
    echo -e "${GREEN}✅ Remote desmontado!${NC}"
}

# Status
do_status() {
    echo -e "${YELLOW}📊 Status do rclone:${NC}"
    echo ""
    
    echo "Remotes configurados:"
    docker exec rclone rclone listremotes
    echo ""
    
    echo "Espaço no remote '$REMOTE_NAME':"
    docker exec rclone rclone about "$REMOTE_NAME:" 2>/dev/null || echo "Não foi possível obter informações."
    echo ""
    
    echo "Últimas linhas do log de sync:"
    tail -20 "$BASE_DIR/config/rclone/sync.log" 2>/dev/null || echo "Nenhum log de sync encontrado."
}

# Main
main() {
    case "$SYNC_MODE" in
        sync)
            check_config
            do_sync
            ;;
        copy)
            check_config
            do_copy
            ;;
        bisync)
            check_config
            do_bisync
            ;;
        mount)
            check_config
            do_mount
            ;;
        unmount)
            do_unmount
            ;;
        status)
            do_status
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            echo -e "${RED}❌ Modo desconhecido: $SYNC_MODE${NC}"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
