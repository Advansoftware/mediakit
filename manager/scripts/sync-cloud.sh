#!/bin/bash
# ===========================================
# MediaKit - Sincronização com Cloud
# ===========================================
# Move arquivos para cloud E cria symlinks
# para que Sonarr/Radarr não baixem novamente
# ===========================================

LOG_FILE="/app/logs/sync-cloud.log"
STATUS_FILE="/tmp/cloud-sync-status.json"
RCLONE_CONFIG="/app/config/rclone/rclone.conf"
CLOUD_TV="/cloud-tv"
CLOUD_MOVIES="/cloud-movies"
MEDIA_TV="/media/tv"
MEDIA_MOVIES="/media/movies"
MIN_SPACE_GB=5

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Atualizar status JSON para dashboard
update_status() {
    local file="$1"
    local progress="$2"
    local speed="$3"
    local action="$4"
    
    if [ "$action" = "start" ]; then
        # Adicionar ao array de transfers
        local current=$(cat "$STATUS_FILE" 2>/dev/null || echo '{"transfers":[]}')
        echo "$current" | jq --arg name "$(basename "$file")" --arg progress "$progress" --arg speed "$speed" \
            '.transfers += [{"name": $name, "progress": ($progress | tonumber), "speed": ($speed | tonumber), "startTime": now}]' > "$STATUS_FILE" 2>/dev/null
    elif [ "$action" = "progress" ]; then
        # Atualizar progresso
        local current=$(cat "$STATUS_FILE" 2>/dev/null || echo '{"transfers":[]}')
        echo "$current" | jq --arg name "$(basename "$file")" --arg progress "$progress" --arg speed "$speed" \
            '(.transfers[] | select(.name == $name)) |= . + {"progress": ($progress | tonumber), "speed": ($speed | tonumber)}' > "$STATUS_FILE" 2>/dev/null
    elif [ "$action" = "done" ]; then
        # Remover do array
        local current=$(cat "$STATUS_FILE" 2>/dev/null || echo '{"transfers":[]}')
        echo "$current" | jq --arg name "$(basename "$file")" \
            '.transfers = [.transfers[] | select(.name != $name)]' > "$STATUS_FILE" 2>/dev/null
    fi
}

# Inicializar status
echo '{"transfers":[], "lastRun": "'$(date -Iseconds)'"}' > "$STATUS_FILE"

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
get_free_space_gb() {
    df -BG /downloads 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G'
}

FREE_GB=$(get_free_space_gb)
log "💾 Espaço livre: ${FREE_GB}GB (mínimo: ${MIN_SPACE_GB}GB)"

# Função para mover arquivo e criar symlink
move_and_symlink() {
    local src_file="$1"
    local cloud_base="$2"
    local media_base="$3"
    
    # Caminho relativo do arquivo
    local relative_path="${src_file#$media_base/}"
    local cloud_file="$cloud_base/$relative_path"
    local cloud_dir=$(dirname "$cloud_file")
    local filename=$(basename "$src_file")
    
    # Verificar se já é symlink
    if [ -L "$src_file" ]; then
        return 0
    fi
    
    # Verificar se arquivo existe
    if [ ! -f "$src_file" ]; then
        return 0
    fi
    
    local size_mb=$(du -m "$src_file" 2>/dev/null | cut -f1)
    log "📤 Movendo: $relative_path ($size_mb MB)"
    
    # Adicionar ao status
    update_status "$src_file" 0 0 "start"
    
    # Verificar se cloud mount está disponível
    if mountpoint -q "$cloud_base" 2>/dev/null; then
        # Criar diretório no cloud
        mkdir -p "$cloud_dir" 2>/dev/null
        
        # Copiar para cloud com progresso
        if pv -n "$src_file" 2>&1 > "$cloud_file" | while read progress; do
            update_status "$src_file" "$progress" 0 "progress"
        done; then
            # Remover original
            rm -f "$src_file"
            # Criar symlink
            ln -sf "$cloud_file" "$src_file"
            log "✅ Movido e symlink criado: $relative_path"
            update_status "$src_file" 100 0 "done"
            return 0
        else
            log "❌ Erro ao copiar: $relative_path"
            update_status "$src_file" 0 0 "done"
            return 1
        fi
    else
        # Usar rclone direto (sem mount)
        local rclone_dest="gdrive:MediaKit${cloud_base#/cloud}"
        
        # Rclone com progresso
        if rclone copy "$src_file" "$rclone_dest/$(dirname "$relative_path")/" \
            --config "$RCLONE_CONFIG" \
            --progress \
            --stats 1s \
            --stats-one-line 2>&1 | while read line; do
                # Extrair progresso do output do rclone
                pct=$(echo "$line" | grep -oP '\d+(?=%)' | tail -1)
                speed=$(echo "$line" | grep -oP '[\d.]+\s*[MKG]i?B/s' | tail -1 | grep -oP '[\d.]+')
                [ -n "$pct" ] && update_status "$src_file" "$pct" "${speed:-0}" "progress"
            done; then
            rm -f "$src_file"
            log "✅ Movido via rclone: $relative_path (sem symlink - mount não disponível)"
            update_status "$src_file" 100 0 "done"
            return 0
        else
            log "❌ Erro ao copiar via rclone: $relative_path"
            update_status "$src_file" 0 0 "done"
            return 1
        fi
    fi
}

# Processar arquivos de TV
process_tv() {
    log "📺 Processando séries..."
    
    if [ ! -d "$MEDIA_TV" ]; then
        log "   Pasta $MEDIA_TV não existe"
        return
    fi
    
    find "$MEDIA_TV" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.m4v" \) 2>/dev/null | while read -r file; do
        move_and_symlink "$file" "$CLOUD_TV" "$MEDIA_TV"
    done
}

# Processar arquivos de Filmes
process_movies() {
    log "🎬 Processando filmes..."
    
    if [ ! -d "$MEDIA_MOVIES" ]; then
        log "   Pasta $MEDIA_MOVIES não existe"
        return
    fi
    
    find "$MEDIA_MOVIES" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.m4v" \) 2>/dev/null | while read -r file; do
        move_and_symlink "$file" "$CLOUD_MOVIES" "$MEDIA_MOVIES"
    done
}

# Verificar espaço e decidir ação
if [ "$FREE_GB" -lt "$MIN_SPACE_GB" ]; then
    log "🚨 ESPAÇO CRÍTICO! Forçando movimentação imediata..."
    process_tv
    process_movies
    
    NEW_FREE=$(get_free_space_gb)
    log "💾 Espaço após limpeza: ${NEW_FREE}GB"
else
    # Mesmo com espaço ok, mover arquivos mais antigos que 5 minutos
    log "📦 Movendo arquivos importados..."
    process_tv
    process_movies
fi

log "========== Sincronização concluída =========="
