#!/bin/bash

# ==========================================
# MediaKit - Script de Setup Inicial
# ==========================================

set -e

echo "🎬 MediaKit - Configuração Inicial"
echo "=================================="
echo ""

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Diretório base
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

# Função para criar diretórios
create_dirs() {
    echo -e "${YELLOW}📁 Criando estrutura de diretórios...${NC}"
    
    # Configurações
    mkdir -p config/jellyfin
    mkdir -p config/jellyseerr
    mkdir -p config/qbittorrent
    mkdir -p config/rclone
    mkdir -p config/prowlarr
    mkdir -p config/radarr
    mkdir -p config/sonarr
    
    # Cache
    mkdir -p cache/jellyfin
    
    # Mídia
    mkdir -p media/movies
    mkdir -p media/tv
    mkdir -p media/music
    mkdir -p media/books
    
    # Downloads
    mkdir -p downloads/complete
    mkdir -p downloads/incomplete
    
    # Cloud mount
    mkdir -p cloud
    
    echo -e "${GREEN}✅ Diretórios criados com sucesso!${NC}"
}

# Função para configurar .env
setup_env() {
    if [ ! -f ".env" ]; then
        echo -e "${YELLOW}📝 Configurando arquivo .env...${NC}"
        cp .env.example .env
        
        # Detectar PUID e PGID
        PUID=$(id -u)
        PGID=$(id -g)
        
        # Substituir valores no .env
        sed -i "s/PUID=1000/PUID=$PUID/" .env
        sed -i "s/PGID=1000/PGID=$PGID/" .env
        
        echo -e "${GREEN}✅ Arquivo .env criado com PUID=$PUID e PGID=$PGID${NC}"
    else
        echo -e "${YELLOW}⚠️  Arquivo .env já existe, mantendo configuração atual.${NC}"
    fi
}

# Função para verificar Docker
check_docker() {
    echo -e "${YELLOW}🐳 Verificando Docker...${NC}"
    
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker não está instalado!${NC}"
        echo "Por favor, instale o Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    if ! docker compose version &> /dev/null; then
        echo -e "${RED}❌ Docker Compose não está instalado!${NC}"
        echo "Por favor, instale o Docker Compose: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Docker e Docker Compose instalados!${NC}"
}

# Função para definir permissões
set_permissions() {
    echo -e "${YELLOW}🔒 Configurando permissões...${NC}"
    
    PUID=$(id -u)
    PGID=$(id -g)
    
    chown -R $PUID:$PGID config/ 2>/dev/null || true
    chown -R $PUID:$PGID cache/ 2>/dev/null || true
    chown -R $PUID:$PGID media/ 2>/dev/null || true
    chown -R $PUID:$PGID downloads/ 2>/dev/null || true
    chown -R $PUID:$PGID cloud/ 2>/dev/null || true
    
    chmod 755 scripts/*.sh 2>/dev/null || true
    
    echo -e "${GREEN}✅ Permissões configuradas!${NC}"
}

# Execução principal
main() {
    check_docker
    create_dirs
    setup_env
    set_permissions
    
    echo ""
    echo -e "${GREEN}🎉 Setup concluído com sucesso!${NC}"
    echo ""
    echo "Próximos passos:"
    echo "  1. Revise o arquivo .env e ajuste conforme necessário"
    echo "  2. Execute: docker compose up -d"
    echo "  3. Acesse os serviços:"
    echo "     - Jellyfin:    http://localhost:8096"
    echo "     - Jellyseerr:  http://localhost:5055"
    echo "     - qBittorrent: http://localhost:8080"
    echo "     - rclone:      http://localhost:5572"
    echo ""
    echo "Para iniciar com todos os serviços opcionais:"
    echo "  docker compose --profile full up -d"
}

main "$@"
