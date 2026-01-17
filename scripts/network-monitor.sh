#!/bin/bash
# ===========================================
# MediaKit - Monitor de Rede Proxy
# Garante que todos os containers MediaKit estejam na proxy-network
# Roda a cada 5 minutos via cron
# ===========================================

LOGFILE="/root/mediakit/logs/network-monitor.log"
PROXY_NETWORK="proxy-network"
CONTAINERS="jellyfin jellyseerr qbittorrent sonarr radarr prowlarr"

mkdir -p /root/mediakit/logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

# Verificar se a rede existe
if ! docker network inspect "$PROXY_NETWORK" >/dev/null 2>&1; then
    log "❌ Rede $PROXY_NETWORK não existe!"
    exit 1
fi

# Verificar cada container
for container in $CONTAINERS; do
    # Verificar se o container está rodando
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        log "⚠️ Container $container não está rodando"
        continue
    fi
    
    # Verificar se está na rede proxy-network
    if docker network inspect "$PROXY_NETWORK" --format '{{range .Containers}}{{.Name}} {{end}}' | grep -q "$container"; then
        : # Container já está na rede, não fazer nada
    else
        log "🔗 Conectando $container à $PROXY_NETWORK..."
        if docker network connect "$PROXY_NETWORK" "$container" 2>/dev/null; then
            log "✅ $container conectado com sucesso!"
        else
            log "❌ Erro ao conectar $container"
        fi
    fi
done
