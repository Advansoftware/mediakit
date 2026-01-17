#!/bin/bash
# ===========================================
# MediaKit - Move automaticamente arquivos completos para GDrive
# Roda a cada 5 minutos via cron
# ===========================================

LOGFILE="/root/mediakit/logs/auto-move.log"
mkdir -p /root/mediakit/logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

# Mover filmes completos
if [ -d "/root/mediakit/media/movies" ] && [ "$(ls -A /root/mediakit/media/movies 2>/dev/null)" ]; then
    log "📽️ Movendo filmes para Google Drive..."
    docker exec rclone rclone move /data/media/movies gdrive:MediaKit/movies \
        --transfers 4 \
        --drive-chunk-size 64M \
        --min-age 2m \
        --delete-empty-src-dirs \
        --log-level INFO 2>&1 | tee -a "$LOGFILE"
fi

# Mover séries completas
if [ -d "/root/mediakit/media/tv" ] && [ "$(ls -A /root/mediakit/media/tv 2>/dev/null)" ]; then
    log "📺 Movendo séries para Google Drive..."
    docker exec rclone rclone move /data/media/tv gdrive:MediaKit/tv \
        --transfers 4 \
        --drive-chunk-size 64M \
        --min-age 2m \
        --delete-empty-src-dirs \
        --log-level INFO 2>&1 | tee -a "$LOGFILE"
fi

# Mover música
if [ -d "/root/mediakit/media/music" ] && [ "$(ls -A /root/mediakit/media/music 2>/dev/null)" ]; then
    log "🎵 Movendo música para Google Drive..."
    docker exec rclone rclone move /data/media/music gdrive:MediaKit/music \
        --transfers 4 \
        --drive-chunk-size 64M \
        --min-age 2m \
        --delete-empty-src-dirs \
        --log-level INFO 2>&1 | tee -a "$LOGFILE"
fi

# Mover livros
if [ -d "/root/mediakit/media/books" ] && [ "$(ls -A /root/mediakit/media/books 2>/dev/null)" ]; then
    log "📚 Movendo livros para Google Drive..."
    docker exec rclone rclone move /data/media/books gdrive:MediaKit/books \
        --transfers 4 \
        --drive-chunk-size 64M \
        --min-age 2m \
        --delete-empty-src-dirs \
        --log-level INFO 2>&1 | tee -a "$LOGFILE"
fi

log "✅ Verificação concluída"
