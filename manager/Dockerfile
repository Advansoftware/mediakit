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
  fuse3

# Criar diretórios
RUN mkdir -p /app/scripts /app/logs /app/indexer-definitions /var/spool/cron/crontabs

# Copiar arquivos
COPY scripts/ /app/scripts/
COPY indexer-definitions/ /app/indexer-definitions/
COPY entrypoint.sh /app/entrypoint.sh

# Permissões
RUN chmod +x /app/scripts/*.sh /app/entrypoint.sh

WORKDIR /app

# Volumes
VOLUME ["/app/logs", "/app/config", "/downloads", "/media"]

# Entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
