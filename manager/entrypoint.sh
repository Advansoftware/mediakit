#!/bin/bash
# ===========================================
# MediaKit Manager - Entrypoint
# ===========================================

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

# ===========================================
# 1. INICIAR DASHBOARD PRIMEIRO (para ver tudo acontecendo)
# ===========================================
log "🌐 Iniciando Dashboard Web PRIMEIRO..."
cd /app/dashboard && node server.js >> "$LOG_DIR/dashboard.log" 2>&1 &
DASHBOARD_PID=$!

# Aguardar dashboard iniciar
sleep 3

if kill -0 $DASHBOARD_PID 2>/dev/null; then
    log "✅ Dashboard iniciado com PID: $DASHBOARD_PID"
    log "🌐 Acesse: http://localhost:3000"
    log "   Usuário: ${MEDIAKIT_USER:-admin}"
    log "   Senha: ${MEDIAKIT_PASS:-adminadmin}"
else
    log "⚠️ Dashboard falhou ao iniciar"
    cat "$LOG_DIR/dashboard.log" 2>/dev/null | tail -20 || true
fi

log ""

# ===========================================
# 2. COPIAR DEFINIÇÕES DE INDEXER
# ===========================================
if [ -d "/app/config/prowlarr" ]; then
    mkdir -p "/app/config/prowlarr/Definitions/Custom"
    cp /app/indexer-definitions/*.yml "/app/config/prowlarr/Definitions/Custom/" 2>/dev/null || true
    log "📋 Definições de indexer copiadas para Prowlarr"
fi

# ===========================================
# 3. AGUARDAR SERVIÇOS FICAREM ONLINE
# ===========================================
log "⏳ Aguardando serviços ficarem online..."

wait_for_services() {
    local max_wait=120
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
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

# ===========================================
# 4. AUTO-CONFIGURAÇÃO
# ===========================================
if [ ! -f "$CONFIG_DIR/.configured" ]; then
    log "🔧 Primeira execução detectada - Iniciando auto-configuração..."
    sleep 15
    
    if /app/scripts/auto-configure.sh; then
        touch "$CONFIG_DIR/.configured"
        log "✅ Auto-configuração concluída com sucesso!"
    else
        log "⚠️ Auto-configuração teve problemas, tentará novamente na próxima reinicialização"
    fi
else
    log "✅ Sistema já configurado anteriormente"
    
    if [ -f "/app/scripts/auto-configure.sh" ]; then
        log "🔄 Verificando indexers brasileiros..."
        source /app/scripts/auto-configure.sh 2>/dev/null || true
        configure_brazilian_indexers 2>/dev/null || true
    fi
fi

# ===========================================
# 5. CONFIGURAR CRONTAB
# ===========================================
log "⏰ Configurando tarefas agendadas..."
cat > /var/spool/cron/crontabs/root << 'CRONTAB'
# MediaKit Cron Jobs
# ==================

# 🧠 Smart Space Manager - A CADA 1 MINUTO
*/1 * * * * /app/scripts/smart-space-manager.sh >> /app/logs/smart-space.log 2>&1

# Verificar downloads completos a cada 2 minutos
*/2 * * * * /app/scripts/post-download.sh >> /app/logs/post-download.log 2>&1

# Sincronizar com cloud a cada 10 minutos
*/10 * * * * /app/scripts/sync-cloud.sh >> /app/logs/sync-cloud.log 2>&1

# Monitorar saúde a cada 5 minutos
*/5 * * * * /app/scripts/health-check.sh >> /app/logs/health-check.log 2>&1

# Limpeza de logs semanalmente
0 0 * * 0 find /app/logs -name "*.log" -mtime +7 -delete

# Rotação de logs diária
0 0 * * * for f in /app/logs/*.log; do [ -f "$f" ] && tail -10000 "$f" > "$f.tmp" && mv "$f.tmp" "$f"; done
CRONTAB

chmod 0600 /var/spool/cron/crontabs/root
log "✅ Crontab configurado"

# ===========================================
# 6. MANTER CONTAINER RODANDO
# ===========================================
log "🎯 MediaKit Manager pronto!"
log ""
log "📋 Logs disponíveis em /app/logs/"
log "   - manager.log: Log principal"
log "   - dashboard.log: Servidor web"
log "   - post-download.log: Downloads"
log "   - sync-cloud.log: Cloud sync"
log "   - smart-space.log: Espaço"
log ""

# Iniciar cron em foreground
log "🔄 Iniciando daemon cron..."
exec /usr/sbin/crond -f -d 8

