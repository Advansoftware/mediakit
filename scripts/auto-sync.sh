#!/bin/bash
# ===========================================
# MediaKit - Sincronização Automática com Google Drive
# ===========================================

LOGFILE="/root/mediakit/logs/sync.log"
mkdir -p /root/mediakit/logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

log "========== Iniciando sincronização =========="

# Sincronizar filmes (local → Google Drive)
log "📽️  Sincronizando filmes..."
docker exec rclone rclone sync /data/media/movies gdrive:MediaKit/movies \
    --progress \
    --transfers 4 \
    --checkers 8 \
    --drive-chunk-size 64M \
    --log-level INFO \
    2>&1 | tee -a "$LOGFILE"

# Sincronizar séries (local → Google Drive)
log "📺 Sincronizando séries..."
docker exec rclone rclone sync /data/media/tv gdrive:MediaKit/tv \
    --progress \
    --transfers 4 \
    --checkers 8 \
    --drive-chunk-size 64M \
    --log-level INFO \
    2>&1 | tee -a "$LOGFILE"

# Sincronizar música (local → Google Drive)
log "🎵 Sincronizando música..."
docker exec rclone rclone sync /data/media/music gdrive:MediaKit/music \
    --progress \
    --transfers 4 \
    --checkers 8 \
    --drive-chunk-size 64M \
    --log-level INFO \
    2>&1 | tee -a "$LOGFILE"

# Sincronizar livros (local → Google Drive)
log "📚 Sincronizando livros..."
docker exec rclone rclone sync /data/media/books gdrive:MediaKit/books \
    --progress \
    --transfers 4 \
    --checkers 8 \
    --drive-chunk-size 64M \
    --log-level INFO \
    2>&1 | tee -a "$LOGFILE"

log "========== Sincronização concluída =========="
log ""
