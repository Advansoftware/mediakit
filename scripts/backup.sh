#!/bin/bash

# ==========================================
# MediaKit - Script de Backup
# ==========================================

set -e

echo "💾 MediaKit - Backup de Configurações"
echo "======================================"
echo ""

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Diretório base
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

# Data/hora para nome do arquivo
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="backup-mediakit-$TIMESTAMP.tar.gz"
BACKUP_DIR="$BASE_DIR/backups"

# Criar diretório de backups se não existir
mkdir -p "$BACKUP_DIR"

echo -e "${YELLOW}📦 Criando backup das configurações...${NC}"

# Parar serviços para garantir consistência (opcional)
read -p "Deseja parar os serviços durante o backup? (recomendado) [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}⏸️  Parando serviços...${NC}"
    docker compose down
    RESTART_AFTER=true
fi

# Criar backup
tar -czf "$BACKUP_DIR/$BACKUP_NAME" \
    --exclude='cache' \
    --exclude='downloads' \
    --exclude='media' \
    --exclude='cloud' \
    --exclude='backups' \
    --exclude='.git' \
    -C "$BASE_DIR" \
    config/ \
    .env \
    docker-compose.yml \
    2>/dev/null || true

# Calcular tamanho
BACKUP_SIZE=$(du -h "$BACKUP_DIR/$BACKUP_NAME" | cut -f1)

echo -e "${GREEN}✅ Backup criado: $BACKUP_DIR/$BACKUP_NAME ($BACKUP_SIZE)${NC}"

# Reiniciar serviços se foram parados
if [ "$RESTART_AFTER" = true ]; then
    echo -e "${YELLOW}▶️  Reiniciando serviços...${NC}"
    docker compose up -d
fi

# Listar backups existentes
echo ""
echo "Backups disponíveis:"
ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "Nenhum backup anterior encontrado."

# Limpar backups antigos (manter apenas os últimos 5)
echo ""
echo -e "${YELLOW}🧹 Limpando backups antigos (mantendo os 5 mais recentes)...${NC}"
cd "$BACKUP_DIR"
ls -t *.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm --
echo -e "${GREEN}✅ Limpeza concluída!${NC}"
