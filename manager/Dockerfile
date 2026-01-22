FROM alpine:3.19

# Instalar dependências
RUN apk add --no-cache \
  bash \
  curl \
  jq \
  sqlite \
  openssl \
  ca-certificates \
  tzdata \
  rclone \
  fuse3 \
  nodejs \
  npm

# Criar diretórios
RUN mkdir -p /app/scripts /app/logs /app/indexer-definitions /app/dashboard /var/spool/cron/crontabs

# Copiar arquivos
COPY scripts/ /app/scripts/
COPY indexer-definitions/ /app/indexer-definitions/
COPY entrypoint.sh /app/entrypoint.sh
COPY dashboard/ /app/dashboard/

# Instalar dependências do dashboard
WORKDIR /app/dashboard
RUN npm install

# Voltar para /app
WORKDIR /app

# Permissões
RUN chmod +x /app/scripts/*.sh /app/entrypoint.sh

# Expor porta do dashboard
EXPOSE 3000

# Volumes
VOLUME ["/app/logs", "/app/config", "/downloads", "/media"]

# Entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
