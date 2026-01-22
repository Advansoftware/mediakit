#!/bin/bash
# ===========================================
# MediaKit - Pós Download (Manager Version)
# Monitora downloads completos e move para cloud
# ===========================================

LOG_FILE="/app/logs/post-download.log"
CONFIG_DIR="/app/config"
DOWNLOADS_DIR="/downloads"
RCLONE_CONFIG="/app/config/rclone/rclone.conf"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Verificar se rclone está configurado
if [ ! -f "$RCLONE_CONFIG" ]; then
    log "⚠️ rclone não configurado, pulando sincronização"
    exit 0
fi

# Verificar se gdrive está configurado
if ! grep -q "\[gdrive\]" "$RCLONE_CONFIG" 2>/dev/null; then
    log "⚠️ Google Drive não configurado no rclone"
    exit 0
fi

QB_URL="http://qbittorrent:8080"
QB_USER="admin"
QB_PASS="@Brunrego2022"

# Autenticar qBittorrent
qb_auth() {
    curl -s -c /tmp/qb_cookies.txt "$QB_URL/api/v2/auth/login" \
        -d "username=$QB_USER&password=$QB_PASS" > /dev/null
}

get_completed_torrents() {
    curl -s -b /tmp/qb_cookies.txt "$QB_URL/api/v2/torrents/info?filter=completed" 2>/dev/null
}

remove_torrent() {
    local hash="$1"
    curl -s -b /tmp/qb_cookies.txt "$QB_URL/api/v2/torrents/delete" \
        -d "hashes=$hash&deleteFiles=true" > /dev/null
}

detect_media_type() {
    local name="$1"
    if [[ "$name" =~ S[0-9]+E[0-9]+ ]] || [[ "$name" =~ [Ss]eason ]] || [[ "$name" =~ Simpsons|SpongeBob ]]; then
        echo "tv"
    else
        echo "movies"
    fi
}

extract_series_name() {
    local name="$1"
    name=$(echo "$name" | sed -E 's/^.*www\.[^-]+-\s*//; s/\.S[0-9]+.*//; s/\./\ /g; s/\ *$//')
    echo "$name" | sed 's/^[ ]*//'
}

log "========== Iniciando verificação =========="

# Verificar espaço em disco
DISK_FREE=$(df -BG /downloads | awk 'NR==2 {print $4}' | tr -d 'G')
log "💾 Espaço livre: ${DISK_FREE}GB"

# Autenticar
qb_auth

# Processar torrents completos
COMPLETED=$(get_completed_torrents)

if [ -n "$COMPLETED" ] && [ "$COMPLETED" != "[]" ]; then
    log "🔍 Encontrados torrents completos"
    
    echo "$COMPLETED" | jq -r '.[] | "\(.hash)|\(.name)|\(.save_path)"' | while IFS='|' read -r hash name save_path; do
        log "📦 Processando: $name"
        
        # Encontrar arquivo
        HOST_PATH=""
        if [ -e "$DOWNLOADS_DIR/$name" ]; then
            HOST_PATH="$DOWNLOADS_DIR/$name"
        else
            SEARCH_NAME=$(echo "$name" | sed -E 's/\[ez[^ ]*\]$//; s/^.*www\.[^-]+-\s*//')
            FOUND_PATH=$(find "$DOWNLOADS_DIR" -maxdepth 1 -name "*$SEARCH_NAME*" 2>/dev/null | head -1)
            [ -n "$FOUND_PATH" ] && HOST_PATH="$FOUND_PATH"
        fi
        
        if [ -n "$HOST_PATH" ] && [ -e "$HOST_PATH" ]; then
            MEDIA_TYPE=$(detect_media_type "$name")
            
            if [ "$MEDIA_TYPE" = "tv" ]; then
                SERIES_NAME=$(extract_series_name "$name")
                DEST="gdrive:MediaKit/tv/$SERIES_NAME"
            else
                DEST="gdrive:MediaKit/movies"
            fi
            
            log "📤 Enviando para $DEST..."
            
            if rclone move "$HOST_PATH" "$DEST" \
                --config "$RCLONE_CONFIG" \
                --transfers 4 \
                --drive-chunk-size 64M \
                --delete-empty-src-dirs \
                --log-level NOTICE 2>&1; then
                
                log "✅ Upload concluído!"
                remove_torrent "$hash"
                log "🗑️ Torrent removido: $name"
            else
                log "❌ Erro no upload de $name"
            fi
        else
            log "⚠️ Arquivo não encontrado, removendo torrent órfão"
            remove_torrent "$hash"
        fi
    done
else
    log "📭 Nenhum torrent completo"
fi

log "========== Verificação concluída =========="
