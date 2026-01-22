#!/bin/bash
# ===========================================
# Move para Cloud após importação do Sonarr/Radarr
# Executado automaticamente via Connect do *arr
# ===========================================

LOG_FILE="/app/logs/move-to-cloud.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Variáveis passadas pelo Sonarr/Radarr
# Sonarr: sonarr_episodefile_path, sonarr_series_path
# Radarr: radarr_moviefile_path, radarr_movie_path

if [ -n "$sonarr_episodefile_path" ]; then
    # É do Sonarr
    FILE_PATH="$sonarr_episodefile_path"
    SERIES_PATH="$sonarr_series_path"
    TYPE="tv"
    CLOUD_BASE="/cloud/tv"
    LOCAL_BASE="/tv"
    log "📺 Sonarr importou: $FILE_PATH"
elif [ -n "$radarr_moviefile_path" ]; then
    # É do Radarr
    FILE_PATH="$radarr_moviefile_path"
    MOVIE_PATH="$radarr_movie_path"
    TYPE="movies"
    CLOUD_BASE="/cloud/movies"
    LOCAL_BASE="/movies"
    log "🎬 Radarr importou: $FILE_PATH"
else
    log "⚠️ Nenhum arquivo detectado (variáveis vazias)"
    exit 0
fi

# Verificar se arquivo existe
if [ ! -f "$FILE_PATH" ]; then
    log "❌ Arquivo não encontrado: $FILE_PATH"
    exit 1
fi

# Calcular caminho relativo
RELATIVE_PATH="${FILE_PATH#$LOCAL_BASE/}"
CLOUD_PATH="$CLOUD_BASE/$RELATIVE_PATH"
CLOUD_DIR=$(dirname "$CLOUD_PATH")

# Criar diretório no cloud
mkdir -p "$CLOUD_DIR" 2>/dev/null

# Tamanho do arquivo
SIZE=$(du -h "$FILE_PATH" | cut -f1)
log "📤 Movendo para cloud: $RELATIVE_PATH ($SIZE)"

# Mover arquivo para cloud usando rclone (mais confiável)
# Como /cloud é um mount, copiar para lá já envia pro Drive
if cp "$FILE_PATH" "$CLOUD_PATH" 2>/dev/null; then
    log "✅ Copiado para cloud: $CLOUD_PATH"
    
    # Remover arquivo local e criar symlink
    rm -f "$FILE_PATH"
    ln -sf "$CLOUD_PATH" "$FILE_PATH"
    
    log "🔗 Symlink criado: $FILE_PATH -> $CLOUD_PATH"
    log "💾 Espaço liberado: $SIZE"
else
    log "❌ Erro ao copiar para cloud"
    exit 1
fi

log "✅ Concluído: $RELATIVE_PATH"
