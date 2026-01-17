#!/bin/bash
# ===========================================
# MediaKit - Script de pós-download
# Fluxo: Download completo → Mover para GDrive → Remover torrent
# Roda a cada 2 minutos via cron
# ===========================================

LOGFILE="/root/mediakit/logs/post-download.log"
RCLONE_CONF="/root/mediakit/config/rclone/rclone.conf"
QB_URL="http://localhost:8080"
QB_USER="admin"
QB_PASS="@Brunrego2022"
MIN_DISK_GB=20  # Mínimo de espaço livre em GB

mkdir -p /root/mediakit/logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

# Verificar espaço em disco
check_disk_space() {
    local avail_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [ "$avail_gb" -lt "$MIN_DISK_GB" ]; then
        log "⚠️ ALERTA: Apenas ${avail_gb}GB livres! Pausando downloads..."
        # Pausar todos os downloads
        curl -s -c /tmp/qb_auto.txt "$QB_URL/api/v2/auth/login" -d "username=$QB_USER&password=$QB_PASS" > /dev/null
        curl -s -b /tmp/qb_auto.txt "$QB_URL/api/v2/torrents/stop" -d "hashes=all" > /dev/null
        return 1
    fi
    return 0
}

# Autenticar no qBittorrent
qb_auth() {
    curl -s -c /tmp/qb_auto.txt "$QB_URL/api/v2/auth/login" -d "username=$QB_USER&password=$QB_PASS" > /dev/null
}

# Obter torrents completos
get_completed_torrents() {
    curl -s -b /tmp/qb_auto.txt "$QB_URL/api/v2/torrents/info?filter=completed" 2>/dev/null
}

# Mover arquivos para GDrive
move_to_gdrive() {
    local path="$1"
    local dest="$2"
    
    if [ -d "$path" ] && [ "$(ls -A "$path" 2>/dev/null)" ]; then
        log "📤 Movendo $path para $dest..."
        rclone move "$path" "$dest" \
            --config "$RCLONE_CONF" \
            --transfers 4 \
            --drive-chunk-size 64M \
            --delete-empty-src-dirs \
            --log-level INFO 2>&1 | tee -a "$LOGFILE"
        return $?
    fi
    return 1
}

# Remover torrent do qBittorrent
remove_torrent() {
    local hash="$1"
    log "🗑️ Removendo torrent $hash..."
    curl -s -b /tmp/qb_auto.txt "$QB_URL/api/v2/torrents/delete" \
        -d "hashes=$hash&deleteFiles=true" > /dev/null
}

# ================== MAIN ==================

log "========== Iniciando verificação =========="

# Verificar espaço
if ! check_disk_space; then
    log "❌ Espaço insuficiente, executando limpeza de emergência..."
    
    # Forçar upload de tudo que está em /media
    move_to_gdrive "/root/mediakit/media/movies" "gdrive:MediaKit/movies"
    move_to_gdrive "/root/mediakit/media/tv" "gdrive:MediaKit/tv"
    
    log "✅ Limpeza de emergência concluída"
    exit 0
fi

# Autenticar
qb_auth

# Processar torrents completos
COMPLETED=$(get_completed_torrents)

if [ -z "$COMPLETED" ] || [ "$COMPLETED" = "[]" ]; then
    log "📭 Nenhum torrent completo para processar"
else
    log "🔍 Processando torrents completos..."
    
    echo "$COMPLETED" | jq -r '.[] | "\(.hash)|\(.name)|\(.content_path)|\(.category)"' | while IFS='|' read -r hash name path category; do
        log "📦 Processando: $name"
        
        # Determinar destino baseado na categoria ou nome
        if [[ "$category" == "movies" ]] || [[ "$name" =~ \.(mkv|mp4|avi)$ && ! "$name" =~ S[0-9]+E[0-9]+ ]]; then
            DEST="gdrive:MediaKit/movies"
            LOCAL_DEST="/root/mediakit/media/movies"
        else
            # Tentar extrair nome da série
            SERIES_NAME=$(echo "$name" | sed -E 's/\.S[0-9]+.*//;s/\./\ /g;s/\ *$//')
            DEST="gdrive:MediaKit/tv/$SERIES_NAME"
            LOCAL_DEST="/root/mediakit/media/tv/$SERIES_NAME"
        fi
        
        # Verificar se o caminho existe
        if [ -e "$path" ]; then
            log "📤 Enviando para $DEST..."
            
            if rclone move "$path" "$DEST" \
                --config "$RCLONE_CONF" \
                --transfers 4 \
                --drive-chunk-size 64M \
                --delete-empty-src-dirs \
                --log-level INFO 2>&1 | tee -a "$LOGFILE"; then
                
                log "✅ Upload concluído, removendo torrent..."
                remove_torrent "$hash"
                log "✅ Torrent $name processado com sucesso!"
            else
                log "❌ Erro no upload de $name"
            fi
        else
            log "⚠️ Caminho não encontrado: $path"
        fi
    done
fi

# Mover conteúdo de /media que sobrou
log "🧹 Limpando pasta /media..."
move_to_gdrive "/root/mediakit/media/movies" "gdrive:MediaKit/movies"
move_to_gdrive "/root/mediakit/media/tv" "gdrive:MediaKit/tv"

log "========== Verificação concluída =========="
log ""
