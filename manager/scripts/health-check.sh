#!/bin/bash
# ===========================================
# MediaKit - Health Check dos Serviços
# ===========================================

LOG_FILE="/app/logs/health-check.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_service() {
    local name=$1
    local url=$2
    local status=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    
    if [[ "$status" =~ ^(200|302|401)$ ]]; then
        echo "✅ $name: OK"
    else
        echo "❌ $name: FALHA (HTTP $status)"
    fi
}

log "=== Health Check ==="

check_service "Jellyfin" "http://jellyfin:8096/health"
check_service "Jellyseerr" "http://jellyseerr:5055/api/v1/status"
check_service "qBittorrent" "http://qbittorrent:8080"
check_service "Prowlarr" "http://prowlarr:9696"
check_service "Radarr" "http://radarr:7878"
check_service "Sonarr" "http://sonarr:8989"
check_service "Torrent Indexer" "http://torrent-indexer:7006"
check_service "rclone" "http://rclone:5572"

log "=== Health Check Concluído ==="
