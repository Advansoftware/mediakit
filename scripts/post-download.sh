#!/bin/bash
# ===========================================
# MediaKit - Script de pós-download CORRIGIDO
# Fluxo: Pegar arquivos em downloads → Mover para GDrive → Remover torrent
# Roda a cada 2 minutos via cron
# ===========================================

LOGFILE="/root/mediakit/logs/post-download.log"
RCLONE_CONF="/root/mediakit/config/rclone/rclone.conf"
QB_URL="http://localhost:8080"
QB_USER="admin"
QB_PASS="@Brunrego2022"
MIN_DISK_GB=20
DOWNLOADS_DIR="/root/mediakit/downloads"

mkdir -p /root/mediakit/logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

check_disk_space() {
    local avail_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    echo $avail_gb
}

qb_auth() {
    curl -s -c /tmp/qb_auto.txt "$QB_URL/api/v2/auth/login" -d "username=$QB_USER&password=$QB_PASS" > /dev/null
}

get_completed_torrents() {
    curl -s -b /tmp/qb_auto.txt "$QB_URL/api/v2/torrents/info?filter=completed" 2>/dev/null
}

remove_torrent() {
    local hash="$1"
    curl -s -b /tmp/qb_auto.txt "$QB_URL/api/v2/torrents/delete" \
        -d "hashes=$hash&deleteFiles=true" > /dev/null
}

pause_downloads() {
    curl -s -c /tmp/qb_auto.txt "$QB_URL/api/v2/auth/login" -d "username=$QB_USER&password=$QB_PASS" > /dev/null
    curl -s -b /tmp/qb_auto.txt "$QB_URL/api/v2/torrents/stop" -d "hashes=all" > /dev/null
}

resume_downloads() {
    curl -s -b /tmp/qb_auto.txt "$QB_URL/api/v2/torrents/start" -d "hashes=all" > /dev/null
}

# Detectar se é filme ou série pelo nome
detect_media_type() {
    local name="$1"
    # Se tem S01E01 ou similar, é série
    if [[ "$name" =~ S[0-9]+E[0-9]+ ]] || [[ "$name" =~ [Ss]eason ]] || [[ "$name" =~ Simpsons|SpongeBob ]]; then
        echo "tv"
    else
        echo "movies"
    fi
}

# Extrair nome da série limpo
extract_series_name() {
    local name="$1"
    # Remove prefixos como www.UIndex.org e limpa o nome
    name=$(echo "$name" | sed -E 's/^.*www\.[^-]+-\s*//; s/\.S[0-9]+.*//; s/\./\ /g; s/\ *$//')
    echo "$name" | sed 's/^[ ]*//'
}

# ================== MAIN ==================

log "========== Iniciando verificação =========="

DISK_FREE=$(check_disk_space)
log "💾 Espaço livre: ${DISK_FREE}GB"

# Se espaço baixo, pausar downloads
if [ "$DISK_FREE" -lt "$MIN_DISK_GB" ]; then
    log "⚠️ ALERTA: Apenas ${DISK_FREE}GB livres! Pausando downloads..."
    pause_downloads
fi

# Autenticar no qBittorrent
qb_auth

# Processar torrents completos
COMPLETED=$(get_completed_torrents)

if [ -n "$COMPLETED" ] && [ "$COMPLETED" != "[]" ]; then
    log "🔍 Encontrados torrents completos, processando..."
    
    # Processar cada torrent
    echo "$COMPLETED" | jq -r '.[] | "\(.hash)|\(.name)|\(.save_path)"' | while IFS='|' read -r hash name save_path; do
        log "📦 Processando: $name"
        log "🔍 Save Path: $save_path"
        
        # Tentar múltiplas formas de localizar o arquivo
        HOST_PATH=""
        
        # 1. Tentar o nome exato
        if [ -e "$DOWNLOADS_DIR/$name" ]; then
            HOST_PATH="$DOWNLOADS_DIR/$name"
        # 2. Tentar sem sufixo [eztvx.to], [eztv.re], etc
        elif [ -e "$DOWNLOADS_DIR/$(echo "$name" | sed -E 's/\[ez[^ ]*\]$//')" ]; then
            HOST_PATH="$DOWNLOADS_DIR/$(echo "$name" | sed -E 's/\[ez[^ ]*\]$//')"
        # 3. Buscar por padrão similar
        else
            SEARCH_NAME=$(echo "$name" | sed -E 's/\[ez[^ ]*\]$//; s/^.*www\.[^-]+-\s*//; s/\.mkv$//; s/\.mp4$//')
            FOUND_PATH=$(find "$DOWNLOADS_DIR" -maxdepth 1 \( -name "*$SEARCH_NAME*" -o -iname "$(echo "$SEARCH_NAME" | tr '.' ' ')*" \) 2>/dev/null | head -1)
            if [ -n "$FOUND_PATH" ] && [ -e "$FOUND_PATH" ]; then
                HOST_PATH="$FOUND_PATH"
            fi
        fi
        
        if [ -n "$HOST_PATH" ] && [ -e "$HOST_PATH" ]; then
            log "✅ Arquivo encontrado: $HOST_PATH"
            
            # Detectar tipo de mídia
            MEDIA_TYPE=$(detect_media_type "$name")
            
            if [ "$MEDIA_TYPE" = "tv" ]; then
                SERIES_NAME=$(extract_series_name "$name")
                DEST="gdrive:MediaKit/tv/$SERIES_NAME"
            else
                DEST="gdrive:MediaKit/movies"
            fi
            
            log "📤 Enviando para $DEST..."
            
            if rclone move "$HOST_PATH" "$DEST" \
                --config "$RCLONE_CONF" \
                --transfers 4 \
                --drive-chunk-size 64M \
                --delete-empty-src-dirs \
                --log-level NOTICE 2>&1 | tee -a "$LOGFILE"; then
                
                log "✅ Upload concluído!"
                sleep 2
                remove_torrent "$hash"
                log "🗑️ Torrent removido: $name"
            else
                log "❌ Erro no upload de $name"
            fi
        else
            log "⚠️ Arquivo não encontrado: $name"
            log "⚠️ Removendo torrent órfão..."
            remove_torrent "$hash"
            log "🗑️ Torrent órfão removido: $name"
        fi
    done
else
    log "📭 Nenhum torrent completo para processar"
fi

# ================== MOVER ARQUIVOS ÓRFÃOS ==================
# Arquivos em downloads que não são torrents ativos

log "🔍 Verificando arquivos órfãos em downloads..."

# Lista de nomes de torrents ativos
ACTIVE_TORRENTS=$(curl -s -b /tmp/qb_auto.txt "$QB_URL/api/v2/torrents/info" 2>/dev/null | jq -r '.[].name' 2>/dev/null || echo "")

# Processar cada pasta em downloads (exceto incomplete)
for dir in "$DOWNLOADS_DIR"/*/; do
    [ -d "$dir" ] || continue
    
    dirname=$(basename "$dir")
    
    # Pular pasta incomplete
    [ "$dirname" = "incomplete" ] && continue
    
    # Verificar se não é torrent ativo
    IS_ACTIVE=$(echo "$ACTIVE_TORRENTS" | grep -F "$dirname" || true)
    
    if [ -z "$IS_ACTIVE" ]; then
        log "📦 Arquivo órfão encontrado: $dirname"
        
        # Detectar tipo de mídia
        MEDIA_TYPE=$(detect_media_type "$dirname")
        
        if [ "$MEDIA_TYPE" = "tv" ]; then
            SERIES_NAME=$(extract_series_name "$dirname")
            DEST="gdrive:MediaKit/tv/$SERIES_NAME"
        else
            DEST="gdrive:MediaKit/movies"
        fi
        
        log "📤 Movendo órfão para $DEST..."
        
        if rclone move "$dir" "$DEST" \
            --config "$RCLONE_CONF" \
            --transfers 4 \
            --drive-chunk-size 64M \
            --delete-empty-src-dirs \
            --log-level NOTICE 2>&1 | tee -a "$LOGFILE"; then
            log "✅ Órfão movido: $dirname"
        else
            log "❌ Erro ao mover órfão: $dirname"
        fi
    fi
done

# Verificar espaço novamente após processamento
DISK_FREE=$(check_disk_space)
if [ "$DISK_FREE" -ge "$MIN_DISK_GB" ]; then
    log "✅ Espaço OK (${DISK_FREE}GB), retomando downloads..."
    resume_downloads
fi

log "========== Verificação concluída =========="
log ""
