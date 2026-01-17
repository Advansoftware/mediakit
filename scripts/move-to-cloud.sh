#!/bin/bash
# ===========================================
# MediaKit - Mover arquivos para Google Drive
# Move arquivos para o GDrive e apaga local
# ===========================================

LOGFILE="/root/mediakit/logs/move-to-cloud.log"
mkdir -p /root/mediakit/logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

log "========== Iniciando movimentação para nuvem =========="

# Mover filmes (local → Google Drive) - MOVE apaga o original
log "📽️  Movendo filmes para nuvem..."
docker exec rclone rclone move /data/media/movies gdrive:MediaKit/movies \
    --progress \
    --transfers 4 \
    --checkers 8 \
    --drive-chunk-size 64M \
    --min-age 5m \
    --log-level INFO \
    --delete-empty-src-dirs \
    2>&1 | tee -a "$LOGFILE"

# Mover séries (local → Google Drive)
log "📺 Movendo séries para nuvem..."
docker exec rclone rclone move /data/media/tv gdrive:MediaKit/tv \
    --progress \
    --transfers 4 \
    --checkers 8 \
    --drive-chunk-size 64M \
    --min-age 5m \
    --log-level INFO \
    --delete-empty-src-dirs \
    2>&1 | tee -a "$LOGFILE"

# Mover música (local → Google Drive)
log "🎵 Movendo música para nuvem..."
docker exec rclone rclone move /data/media/music gdrive:MediaKit/music \
    --progress \
    --transfers 4 \
    --checkers 8 \
    --drive-chunk-size 64M \
    --min-age 5m \
    --log-level INFO \
    --delete-empty-src-dirs \
    2>&1 | tee -a "$LOGFILE"

# Mover livros (local → Google Drive)
log "📚 Movendo livros para nuvem..."
docker exec rclone rclone move /data/media/books gdrive:MediaKit/books \
    --progress \
    --transfers 4 \
    --checkers 8 \
    --drive-chunk-size 64M \
    --min-age 5m \
    --log-level INFO \
    --delete-empty-src-dirs \
    2>&1 | tee -a "$LOGFILE"

log "========== Movimentação concluída =========="

# Mostrar espaço liberado
log "💾 Espaço em disco:"
df -h / | tee -a "$LOGFILE"
log ""
