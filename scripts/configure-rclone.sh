#!/bin/bash

# ==========================================
# MediaKit - Configuração do rclone
# ==========================================

set -e

echo "☁️  MediaKit - Configuração do rclone"
echo "====================================="
echo ""

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Este script ajuda a configurar o rclone para uso com Google Drive.${NC}"
echo ""

# Verificar se o container rclone está rodando
if ! docker ps | grep -q rclone; then
    echo -e "${RED}❌ Container rclone não está rodando!${NC}"
    echo "Execute: docker compose up -d rclone"
    exit 1
fi

echo "Escolha uma opção:"
echo "  1) Configuração interativa (recomendado para desktop)"
echo "  2) Configuração headless (para servidor sem interface gráfica)"
echo "  3) Importar configuração existente"
echo "  4) Testar conexão com remote existente"
echo ""

read -p "Opção [1-4]: " -n 1 -r
echo ""

case $REPLY in
    1)
        echo -e "${YELLOW}🔧 Iniciando configuração interativa...${NC}"
        echo "Siga as instruções do rclone."
        echo ""
        docker exec -it rclone rclone config
        ;;
    2)
        echo -e "${YELLOW}🔧 Configuração headless para Google Drive${NC}"
        echo ""
        echo "Para configurar em um servidor sem interface gráfica:"
        echo ""
        echo "1. Em seu computador local (com navegador), instale o rclone:"
        echo "   curl https://rclone.org/install.sh | sudo bash"
        echo ""
        echo "2. Execute no seu computador local:"
        echo "   rclone authorize \"drive\""
        echo ""
        echo "3. Faça login no Google e copie o token gerado"
        echo ""
        echo "4. No servidor, execute:"
        echo "   docker exec -it rclone rclone config"
        echo ""
        echo "5. Durante a configuração, quando perguntar sobre 'remote machine',"
        echo "   responda 'n' e cole o token quando solicitado"
        ;;
    3)
        echo -e "${YELLOW}📥 Importar configuração existente${NC}"
        echo ""
        
        BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        CONFIG_PATH="$BASE_DIR/config/rclone/rclone.conf"
        
        read -p "Caminho do arquivo rclone.conf existente: " SOURCE_CONF
        
        if [ -f "$SOURCE_CONF" ]; then
            cp "$SOURCE_CONF" "$CONFIG_PATH"
            echo -e "${GREEN}✅ Configuração importada para $CONFIG_PATH${NC}"
            
            echo ""
            echo "Remotes disponíveis:"
            docker exec rclone rclone listremotes
        else
            echo -e "${RED}❌ Arquivo não encontrado: $SOURCE_CONF${NC}"
            exit 1
        fi
        ;;
    4)
        echo -e "${YELLOW}🔍 Testando conexão...${NC}"
        echo ""
        
        echo "Remotes configurados:"
        docker exec rclone rclone listremotes
        echo ""
        
        read -p "Nome do remote para testar (ex: gdrive): " REMOTE_NAME
        
        echo ""
        echo "Testando $REMOTE_NAME..."
        docker exec rclone rclone about "$REMOTE_NAME:" && \
            echo -e "${GREEN}✅ Conexão OK!${NC}" || \
            echo -e "${RED}❌ Falha na conexão${NC}"
        ;;
    *)
        echo -e "${RED}Opção inválida${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}🎉 Configuração concluída!${NC}"
echo ""
echo "Para sincronizar com a cloud:"
echo "  ./scripts/sync-cloud.sh sync"
echo ""
echo "Para montar como pasta:"
echo "  ./scripts/sync-cloud.sh mount"
