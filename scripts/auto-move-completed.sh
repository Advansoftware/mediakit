#!/bin/bash
# ===========================================
# MediaKit - Move automaticamente arquivos para GDrive
# Roda a cada 5 minutos via cron
# Monitora espaço em disco e pausa torrents se necessário
# ===========================================

LOGFILE="/root/mediakit/logs/auto-move.log"
RCLONE_CONFIG="/root/mediakit/config/rclone/rclone.conf"
THRESHOLD=80  # Pausar torrents se disco > 80%

mkdir -p /root/mediakit/logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

# Verificar espaço em disco
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
log "📊 Uso do disco: ${DISK_USAGE}%"

# Se disco > 80%, pausar torrents
if [ "$DISK_USAGE" -gt "$THRESHOLD" ]; then
    log "⚠️ Disco acima de ${THRESHOLD}%! Pausando torrents..."
    curl -s -c /tmp/qb.txt "http://localhost:8080/api/v2/auth/login" -d "username=admin&password=@Brunrego2022" 2>/dev/null
    curl -s -b /tmp/qb.txt "http://localhost:8080/api/v2/torrents/pause" -d "hashes=all" 2>/dev/null
fi

# Mover arquivos de /media para GDrive
for folder in movies tv music books; do
    SRC="/root/mediakit/media/$folder"
    if [ -d "$SRC" ] && [ "$(find "$SRC" -type f 2>/dev/null | head -1)" ]; then
        log "📤 Movendo $folder de /media para GDrive..."
        rclone move "$SRC" "gdrive:MediaKit/$folder" \
            --config "$RCLONE_CONFIG" \
            --transfers 2 \
            --drive-chunk-size 32M \
            --min-age 2m \
            --delete-empty-src-dirs \
            -v 2>&1 | tail -5 | tee -a "$LOGFILE"
    fi
done

# Mover downloads completos para GDrive
DOWNLOADS="/root/mediakit/downloads"
for dir in "$DOWNLOADS"/*/; do
    [ "$dir" = "$DOWNLOADS/complete/" ] && continue
    [ "$dir" = "$DOWNLOADS/incomplete/" ] && continue
    
    if [ -d "$dir" ] && [ "$(find "$dir" -type f 2>/dev/null | head -1)" ]; then
        DIRNAME=$(basename "$dir")
        log "📤 Movendo download '$DIRNAME' para GDrive..."
        
        # Detectar se é série ou filme baseado no nome
        if echo "$DIRNAME" | grep -qiE "S[0-9]{2}|Season|Temporada"; then
            DEST="gdrive:MediaKit/downloads/tv"
        else
            DEST="gdrive:MediaKit/downloads/movies"
        fi
        
        rclone move "$dir" "$DEST/$DIRNAME" \
            --config "$RCLONE_CONFIG" \
            --transfers 2 \
            --drive-chunk-size 32M \
            --min-age 5m \
            --delete-empty-src-dirs \
            -v 2>&1 | tail -5 | tee -a "$LOGFILE"
    fi
done

# Verificar espaço após limpeza
DISK_USAGE_AFTER=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
log "📊 Uso do disco após limpeza: ${DISK_USAGE_AFTER}%"

# Se disco < 70%, retomar torrents
if [ "$DISK_USAGE_AFTER" -lt 70 ]; then
    log "✅ Disco abaixo de 70%. Retomando torrents..."
    curl -s -c /tmp/qb.txt "http://localhost:8080/api/v2/auth/login" -d "username=admin&password=@Brunrego2022" 2>/dev/null
    curl -s -b /tmp/qb.txt "http://localhost:8080/api/v2/torrents/resume" -d "hashes=all" 2>/dev/null
fi

log "✅ Verificação concluída"
