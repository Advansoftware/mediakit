#!/bin/bash
# ===========================================
# MediaKit - Sincronização com Cloud
# ===========================================

LOG_FILE="/app/logs/sync-cloud.log"
RCLONE_CONFIG="/app/config/rclone/rclone.conf"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Verificar se rclone está configurado
if [ ! -f "$RCLONE_CONFIG" ]; then
    exit 0
fi

# Verificar se gdrive está configurado
if ! grep -q "\[gdrive\]" "$RCLONE_CONFIG" 2>/dev/null; then
    exit 0
fi

log "========== Sincronização com Cloud =========="

# Verificar espaço em disco
DISK_USAGE=$(df /downloads | tail -1 | awk '{print $5}' | tr -d '%')
log "📊 Uso do disco: ${DISK_USAGE}%"

# Se disco > 80%, forçar movimentação
if [ "$DISK_USAGE" -gt 80 ]; then
    log "⚠️ Disco acima de 80%! Forçando movimentação..."
    
    for folder in movies tv; do
        SRC="/media/$folder"
        if [ -d "$SRC" ] && [ "$(find "$SRC" -type f 2>/dev/null | head -1)" ]; then
            log "📤 Movendo $folder para cloud..."
            rclone move "$SRC" "gdrive:MediaKit/$folder" \
                --config "$RCLONE_CONFIG" \
                --transfers 4 \
                --drive-chunk-size 64M \
                --min-age 2m \
                --delete-empty-src-dirs \
                --log-level INFO 2>&1 | tail -10
        fi
    done
fi

log "========== Sincronização concluída =========="
