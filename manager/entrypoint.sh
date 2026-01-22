#!/bin/bash
# ===========================================
# MediaKit Manager - Entrypoint
# ===========================================

# Não usar set -e para evitar saída prematura
# set -e

LOG_DIR="/app/logs"
CONFIG_DIR="/app/config"

# Garantir que diretórios existem
mkdir -p "$LOG_DIR" 2>/dev/null || true
mkdir -p "$CONFIG_DIR" 2>/dev/null || true

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_DIR/manager.log" 2>/dev/null || echo "$msg"
}

log "🚀 MediaKit Manager iniciando..."

# Copiar definição do indexer brasileiro para Prowlarr
if [ -d "/app/config/prowlarr" ]; then
    mkdir -p "/app/config/prowlarr/Definitions/Custom"
    cp /app/indexer-definitions/*.yml "/app/config/prowlarr/Definitions/Custom/" 2>/dev/null || true
    log "📋 Definições de indexer copiadas para Prowlarr"
fi

# Aguardar containers estarem prontos
log "⏳ Aguardando serviços ficarem online..."

wait_for_services() {
    local max_wait=120
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        # Verificar serviços essenciais
        local prowlarr_ok=$(curl -s -o /dev/null -w "%{http_code}" "http://prowlarr:9696" 2>/dev/null || echo "000")
        local radarr_ok=$(curl -s -o /dev/null -w "%{http_code}" "http://radarr:7878" 2>/dev/null || echo "000")
        local sonarr_ok=$(curl -s -o /dev/null -w "%{http_code}" "http://sonarr:8989" 2>/dev/null || echo "000")
        local qb_ok=$(curl -s -o /dev/null -w "%{http_code}" "http://qbittorrent:8080" 2>/dev/null || echo "000")
        
        if [[ "$prowlarr_ok" =~ ^(200|302|401)$ ]] && \
           [[ "$radarr_ok" =~ ^(200|302|401)$ ]] && \
           [[ "$sonarr_ok" =~ ^(200|302|401)$ ]] && \
           [[ "$qb_ok" =~ ^(200|302|401)$ ]]; then
            log "✅ Todos os serviços estão online!"
            return 0
        fi
        
        sleep 5
        waited=$((waited + 5))
        log "⏳ Aguardando... ($waited/${max_wait}s)"
    done
    
    log "⚠️ Timeout aguardando serviços, continuando mesmo assim..."
    return 0
}

wait_for_services

# Verificar se já está configurado
if [ ! -f "$CONFIG_DIR/.configured" ]; then
    log "🔧 Primeira execução detectada - Iniciando auto-configuração..."
    
    # Aguardar mais um pouco para garantir que os serviços inicializaram completamente
    sleep 15
    
    # Executar configuração automática
    if /app/scripts/auto-configure.sh; then
        touch "$CONFIG_DIR/.configured"
        log "✅ Auto-configuração concluída com sucesso!"
    else
        log "⚠️ Auto-configuração teve problemas, tentará novamente na próxima reinicialização"
    fi
else
    log "✅ Sistema já configurado anteriormente"
    
    # Re-sincronizar indexers brasileiros (pode ter novos)
    if [ -f "/app/scripts/auto-configure.sh" ]; then
        log "🔄 Verificando indexers brasileiros..."
        # Extrair apenas a função de indexers do script
        source /app/scripts/auto-configure.sh 2>/dev/null || true
        configure_brazilian_indexers 2>/dev/null || true
    fi
fi

# Configurar crontab
log "⏰ Configurando tarefas agendadas..."
cat > /var/spool/cron/crontabs/root << 'CRONTAB'
# MediaKit Cron Jobs
# ==================

# Verificar downloads completos e mover para cloud a cada 2 minutos
*/2 * * * * /app/scripts/post-download.sh >> /app/logs/post-download.log 2>&1

# Sincronizar com cloud a cada 10 minutos
*/10 * * * * /app/scripts/sync-cloud.sh >> /app/logs/sync-cloud.log 2>&1

# Monitorar saúde dos serviços a cada 5 minutos
*/5 * * * * /app/scripts/health-check.sh >> /app/logs/health-check.log 2>&1

# Limpeza de logs semanalmente (domingo 00:00)
0 0 * * 0 find /app/logs -name "*.log" -mtime +7 -delete

# Rotação de logs diária
0 0 * * * for f in /app/logs/*.log; do [ -f "$f" ] && tail -10000 "$f" > "$f.tmp" && mv "$f.tmp" "$f"; done
CRONTAB

chmod 0600 /var/spool/cron/crontabs/root

log "✅ Crontab configurado"
log "🎯 MediaKit Manager pronto!"
log ""
log "📋 Logs disponíveis em /app/logs/"
log "   - manager.log: Log principal do manager"
log "   - post-download.log: Movimentação de downloads"
log "   - sync-cloud.log: Sincronização com cloud"
log "   - health-check.log: Verificação de saúde"
log ""

# Manter container rodando com cron
log "🔄 Iniciando daemon cron..."
exec /usr/sbin/crond -f -d 8

