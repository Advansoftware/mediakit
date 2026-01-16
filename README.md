# 🎬 MediaKit

Stack completo de servidor de mídia em Docker com **Jellyfin**, **Jellyseerr**, **qBittorrent** e **rclone** para sincronização com Google Drive.

[![Docker](https://img.shields.io/badge/Docker-Ready-blue?logo=docker)](https://www.docker.com/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 📋 Índice

- [Visão Geral](#-visão-geral)
- [Serviços Incluídos](#-serviços-incluídos)
- [Requisitos](#-requisitos)
- [Instalação Rápida](#-instalação-rápida)
- [Configuração Detalhada](#-configuração-detalhada)
  - [Jellyfin](#jellyfin-servidor-de-mídia)
  - [Jellyseerr](#jellyseerr-gerenciador-de-requisições)
  - [qBittorrent](#qbittorrent-cliente-de-torrent)
  - [rclone](#rclone-sincronização-com-cloud)
- [Serviços Opcionais](#-serviços-opcionais)
- [Estrutura de Pastas](#-estrutura-de-pastas)
- [Comunicação Entre Serviços](#-comunicação-entre-serviços)
- [Comandos Úteis](#-comandos-úteis)
- [Backup e Restauração](#-backup-e-restauração)
- [Solução de Problemas](#-solução-de-problemas)
- [Contribuindo](#-contribuindo)

## 🎯 Visão Geral

MediaKit é uma solução completa e portátil para gerenciar seu próprio servidor de mídia. Com apenas alguns comandos, você terá:

- 📺 **Streaming de mídia** - Assista seus filmes e séries de qualquer dispositivo
- 🔍 **Requisições de mídia** - Solicite novos conteúdos facilmente
- ⬇️ **Downloads automatizados** - Cliente de torrent integrado
- ☁️ **Backup na nuvem** - Sincronize com Google Drive, OneDrive, etc.

### Por que usar o MediaKit?

- ✅ **Portátil** - Clone em qualquer servidor e execute
- ✅ **Isolado** - Tudo roda em containers Docker
- ✅ **Configurável** - Variáveis de ambiente simples
- ✅ **Integrado** - Todos os serviços se comunicam automaticamente
- ✅ **Extensível** - Adicione Radarr, Sonarr, Prowlarr facilmente

## 📦 Serviços Incluídos

### Serviços Principais

| Serviço | Descrição | Porta | Documentação |
|---------|-----------|-------|--------------|
| **Jellyfin** | Servidor de mídia (filmes, séries, música) | 8096 | [docs](https://jellyfin.org/docs/) |
| **Jellyseerr** | Gerenciador de requisições de mídia | 5055 | [docs](https://docs.jellyseerr.dev/) |
| **qBittorrent** | Cliente de torrent com WebUI | 8080 | [docs](https://github.com/qbittorrent/qBittorrent/wiki) |
| **rclone** | Sincronização com cloud (Google Drive, etc.) | 5572 | [docs](https://rclone.org/docs/) |

### Serviços Opcionais (Profile: full)

| Serviço | Descrição | Porta |
|---------|-----------|-------|
| **Prowlarr** | Indexador de torrents | 9696 |
| **Radarr** | Gerenciador automático de filmes | 7878 |
| **Sonarr** | Gerenciador automático de séries | 8989 |

## 💻 Requisitos

- **Sistema Operacional**: Linux (recomendado), macOS ou Windows com WSL2
- **Docker**: versão 20.10+
- **Docker Compose**: versão 2.0+
- **RAM**: Mínimo 2GB (4GB+ recomendado para transcodificação)
- **Armazenamento**: Depende do tamanho da sua biblioteca

### Verificar instalação do Docker

```bash
docker --version
docker compose version
```

### Instalar Docker (se necessário)

```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Reinicie a sessão para aplicar as permissões
```

## 🚀 Instalação Rápida

### 1. Clone o repositório

```bash
git clone git@github.com:Advansoftware/mediakit.git
cd mediakit
```

Ou via HTTPS:
```bash
git clone https://github.com/Advansoftware/mediakit.git
cd mediakit
```

### 2. Execute o script de setup

```bash
chmod +x scripts/*.sh
./scripts/setup.sh
```

Este script irá:
- ✅ Verificar se Docker está instalado
- ✅ Criar todas as pastas necessárias
- ✅ Configurar o arquivo `.env` com seu PUID/PGID
- ✅ Definir permissões corretas

### 3. (Opcional) Ajuste as configurações

```bash
nano .env
```

### 4. Inicie os serviços

```bash
# Apenas serviços principais
docker compose up -d

# Com serviços opcionais (Prowlarr, Radarr, Sonarr)
docker compose --profile full up -d
```

### 5. Acesse os serviços

- **Jellyfin**: http://localhost:8096
- **Jellyseerr**: http://localhost:5055
- **qBittorrent**: http://localhost:8080
- **rclone WebUI**: http://localhost:5572

## ⚙️ Configuração Detalhada

### Variáveis de Ambiente (.env)

| Variável | Descrição | Padrão |
|----------|-----------|--------|
| `TZ` | Fuso horário | `America/Sao_Paulo` |
| `PUID` | ID do usuário Linux | `1000` |
| `PGID` | ID do grupo Linux | `1000` |
| `JELLYFIN_URL` | URL pública do Jellyfin | `http://localhost:8096` |
| `RCLONE_USER` | Usuário da WebUI do rclone | `admin` |
| `RCLONE_PASS` | Senha da WebUI do rclone | `admin123` |

**Descobrir seu PUID e PGID:**
```bash
id -u  # PUID
id -g  # PGID
```

---

### Jellyfin (Servidor de Mídia)

**Acesso**: http://localhost:8096

#### Configuração Inicial

1. Acesse http://localhost:8096
2. Escolha o idioma preferido
3. Crie uma conta de administrador
4. Adicione bibliotecas de mídia:

| Tipo | Caminho no Container |
|------|---------------------|
| Filmes | `/media/movies` |
| Séries | `/media/tv` |
| Música | `/media/music` |
| Livros | `/media/books` |

5. Configure metadados (TheMovieDB, etc.)
6. Finalize a configuração

#### Dicas de Configuração

- **Transcodificação por hardware**: Configure em Dashboard > Playback > Transcoding
- **Usuários remotos**: Crie contas separadas com permissões específicas
- **Plugins**: Instale plugins úteis como OpenSubtitles, Fanart, etc.

---

### Jellyseerr (Gerenciador de Requisições)

**Acesso**: http://localhost:5055

#### Configuração Inicial

1. Acesse http://localhost:5055
2. Escolha "Use your Jellyfin account"
3. Configure a conexão com Jellyfin:
   - **URL do Jellyfin**: `http://jellyfin:8096` (URL interna Docker)
   - **Email/Usuário**: Seu usuário admin do Jellyfin
   - **Senha**: Sua senha do Jellyfin
4. Sincronize bibliotecas e usuários
5. Configure clientes de download (Radarr/Sonarr) se estiver usando

#### Integrações

Para download automático, configure:
- **Radarr** (filmes): http://radarr:7878
- **Sonarr** (séries): http://sonarr:8989

---

### qBittorrent (Cliente de Torrent)

**Acesso**: http://localhost:8080

#### Primeira Execução

Na primeira execução, o qBittorrent gera uma senha aleatória. Para obtê-la:

```bash
docker logs qbittorrent 2>&1 | grep "temporary password"
```

**Credenciais padrão:**
- Usuário: `admin`
- Senha: (veja nos logs acima)

#### Configuração Recomendada

1. **Alterar senha**: Tools > Options > Web UI > Authentication
2. **Diretórios de download**:
   - Download padrão: `/downloads`
   - Mover após conclusão: `/media/movies` ou `/media/tv`
3. **Limites de velocidade**: Configure conforme sua conexão
4. **Conexões**: Ajuste em Connection para otimizar

#### Configurações de Diretório

```
Opções > Downloads:
- Salvar arquivos em: /downloads
- Manter incompletos em: /downloads/incomplete
```

---

### rclone (Sincronização com Cloud)

**WebUI**: http://localhost:5572

O rclone permite sincronizar sua biblioteca com serviços de cloud como Google Drive, OneDrive, Dropbox, etc.

#### Configuração do Google Drive

**Método 1: Script assistido**
```bash
./scripts/configure-rclone.sh
```

**Método 2: Configuração manual**
```bash
docker exec -it rclone rclone config
```

Siga os passos:
1. `n` - Novo remote
2. Nome: `gdrive`
3. Storage: `drive` (Google Drive)
4. Client ID/Secret: Deixe em branco (usa padrão)
5. Scope: `drive` (acesso completo)
6. Root folder ID: Deixe em branco
7. Service Account: Deixe em branco
8. Auto config: `n` (para servidor headless)
9. Configure no navegador local (veja instruções abaixo)

#### Configuração Headless (Servidor sem GUI)

Para servidores sem interface gráfica:

1. **No seu computador local** (com navegador):
```bash
# Instale o rclone localmente
curl https://rclone.org/install.sh | sudo bash

# Execute a autorização
rclone authorize "drive"
```

2. Faça login no Google quando o navegador abrir
3. Copie o token JSON gerado
4. **No servidor**, durante `rclone config`, cole o token quando solicitado

#### Comandos de Sincronização

```bash
# Sincronizar mídia local → Google Drive
./scripts/sync-cloud.sh sync

# Apenas copiar (não deleta arquivos no destino)
./scripts/sync-cloud.sh copy

# Sincronização bidirecional
./scripts/sync-cloud.sh bisync

# Montar Google Drive como pasta local
./scripts/sync-cloud.sh mount

# Verificar status
./scripts/sync-cloud.sh status
```

#### Sincronização Automática (Cron)

Adicione ao crontab do host:
```bash
crontab -e
```

```cron
# Sync a cada 6 horas
0 */6 * * * cd /path/to/mediakit && ./scripts/sync-cloud.sh sync >> /var/log/mediakit-sync.log 2>&1
```

---

## 🔧 Serviços Opcionais

Para ativar Prowlarr, Radarr e Sonarr:

```bash
docker compose --profile full up -d
```

### Prowlarr (Indexador)

**Acesso**: http://localhost:9696

Centraliza a configuração de indexadores (sites de torrent) para Radarr e Sonarr.

1. Adicione indexadores em Indexers > Add Indexer
2. Configure aplicações em Settings > Apps
3. Adicione Radarr e Sonarr como aplicações

### Radarr (Filmes)

**Acesso**: http://localhost:7878

1. Adicione pasta de mídia: `/movies`
2. Configure cliente de download: qBittorrent em `http://qbittorrent:8080`
3. Adicione indexadores via Prowlarr ou manualmente
4. Adicione filmes para monitorar

### Sonarr (Séries)

**Acesso**: http://localhost:8989

1. Adicione pasta de mídia: `/tv`
2. Configure cliente de download: qBittorrent em `http://qbittorrent:8080`
3. Adicione indexadores via Prowlarr ou manualmente
4. Adicione séries para monitorar

---

## 📁 Estrutura de Pastas

```
mediakit/
├── docker-compose.yml      # Definição de todos os serviços
├── .env                    # Variáveis de ambiente (NÃO versionar)
├── .env.example            # Template das variáveis
├── .gitignore              # Arquivos ignorados pelo Git
├── README.md               # Esta documentação
│
├── config/                 # Configurações dos serviços (persistentes)
│   ├── jellyfin/           # Banco de dados e configs do Jellyfin
│   ├── jellyseerr/         # Configurações do Jellyseerr
│   ├── qbittorrent/        # Configurações do qBittorrent
│   ├── rclone/             # rclone.conf (remotes configurados)
│   ├── prowlarr/           # Configurações do Prowlarr
│   ├── radarr/             # Configurações do Radarr
│   └── sonarr/             # Configurações do Sonarr
│
├── cache/                  # Cache (pode ser deletado)
│   └── jellyfin/           # Cache de transcodificação
│
├── downloads/              # Downloads do qBittorrent
│   ├── complete/           # Downloads concluídos
│   └── incomplete/         # Downloads em andamento
│
├── media/                  # Biblioteca de mídia
│   ├── movies/             # Filmes
│   ├── tv/                 # Séries de TV
│   ├── music/              # Música
│   └── books/              # E-books/Audiobooks
│
├── cloud/                  # Ponto de montagem do rclone
│
└── scripts/                # Scripts auxiliares
    ├── setup.sh            # Configuração inicial
    ├── backup.sh           # Backup das configurações
    ├── sync-cloud.sh       # Sincronização com cloud
    └── configure-rclone.sh # Assistente do rclone
```

---

## 🔗 Comunicação Entre Serviços

Todos os serviços estão na rede Docker `mediakit-network` e podem se comunicar pelos nomes dos containers:

| Origem | Destino | URL Interna |
|--------|---------|-------------|
| Jellyseerr | Jellyfin | `http://jellyfin:8096` |
| Jellyseerr | Radarr | `http://radarr:7878` |
| Jellyseerr | Sonarr | `http://sonarr:8989` |
| Radarr | qBittorrent | `http://qbittorrent:8080` |
| Radarr | Prowlarr | `http://prowlarr:9696` |
| Sonarr | qBittorrent | `http://qbittorrent:8080` |
| Sonarr | Prowlarr | `http://prowlarr:9696` |

### Diagrama de Integração

```
                    ┌──────────────┐
                    │  Jellyseerr  │ ← Requisições de usuários
                    │    :5055     │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
       ┌──────────┐  ┌──────────┐  ┌──────────┐
       │  Radarr  │  │  Sonarr  │  │ Jellyfin │
       │  :7878   │  │  :8989   │  │  :8096   │
       └────┬─────┘  └────┬─────┘  └──────────┘
            │             │              ▲
            ▼             ▼              │
       ┌──────────────────────┐          │
       │     qBittorrent      │──────────┘
       │        :8080         │    (mídia pronta)
       └──────────┬───────────┘
                  │
                  ▼
       ┌──────────────────────┐
       │       rclone         │ ← Sync com cloud
       │        :5572         │
       └──────────────────────┘
```

---

## 🛠️ Comandos Úteis

### Docker Compose

```bash
# Iniciar serviços
docker compose up -d

# Iniciar com serviços opcionais
docker compose --profile full up -d

# Parar serviços
docker compose down

# Reiniciar um serviço específico
docker compose restart jellyfin

# Ver status dos containers
docker compose ps

# Ver logs em tempo real
docker compose logs -f

# Ver logs de um serviço específico
docker compose logs -f jellyfin

# Atualizar imagens
docker compose pull

# Recriar containers após atualização
docker compose up -d --force-recreate

# Remover tudo (CUIDADO: remove volumes)
docker compose down -v
```

### Entrar em Containers

```bash
# Jellyfin
docker exec -it jellyfin /bin/bash

# qBittorrent
docker exec -it qbittorrent /bin/bash

# rclone
docker exec -it rclone /bin/sh
```

### Verificar Recursos

```bash
# Uso de recursos dos containers
docker stats

# Espaço em disco
df -h

# Tamanho das pastas
du -sh media/* downloads/*
```

---

## 💾 Backup e Restauração

### Criar Backup

```bash
./scripts/backup.sh
```

O backup inclui:
- Todas as configurações (`config/`)
- Arquivo `.env`
- `docker-compose.yml`

**NÃO inclui** (muito grandes):
- Mídia (`media/`)
- Downloads (`downloads/`)
- Cache (`cache/`)

### Restaurar Backup

```bash
# Extrair backup
tar -xzf backups/backup-mediakit-XXXXXX.tar.gz -C ./

# Reiniciar serviços
docker compose down
docker compose up -d
```

### Backup para Cloud

```bash
# Fazer backup e enviar para Google Drive
./scripts/backup.sh
docker exec rclone rclone copy /config/rclone/../backups gdrive:mediakit-backups
```

---

## ❓ Solução de Problemas

### Jellyfin não inicia

```bash
# Verificar logs
docker logs jellyfin

# Verificar permissões
ls -la config/jellyfin/
```

### qBittorrent - Erro de autenticação

```bash
# Ver senha temporária
docker logs qbittorrent 2>&1 | grep "temporary password"

# Ou resetar a senha deletando a config
rm -rf config/qbittorrent/*
docker compose restart qbittorrent
```

### rclone - Erro de autenticação Google

```bash
# Reconfigurar o remote
docker exec -it rclone rclone config delete gdrive
docker exec -it rclone rclone config
```

### Permissões de arquivos

```bash
# Corrigir permissões
PUID=$(id -u)
PGID=$(id -g)
sudo chown -R $PUID:$PGID config/ media/ downloads/
```

### Container não encontra outro container

Verifique se estão na mesma rede:
```bash
docker network inspect mediakit-network
```

### Porta em uso

```bash
# Verificar qual processo usa a porta
sudo lsof -i :8096

# Ou usar outra porta no .env/docker-compose.yml
```

---

## 🔄 Atualização

```bash
# Baixar últimas imagens
docker compose pull

# Recriar containers
docker compose up -d

# (Opcional) Limpar imagens antigas
docker image prune -f
```

---

## 🤝 Contribuindo

Contribuições são bem-vindas! Para contribuir:

1. Fork o repositório
2. Crie uma branch (`git checkout -b feature/minha-feature`)
3. Commit suas mudanças (`git commit -am 'Adiciona nova feature'`)
4. Push para a branch (`git push origin feature/minha-feature`)
5. Abra um Pull Request

---

## 📄 Licença

Este projeto está sob a licença MIT. Veja o arquivo [LICENSE](LICENSE) para detalhes.

---

## 🙏 Agradecimentos

- [Jellyfin](https://jellyfin.org/) - Servidor de mídia open source
- [Jellyseerr](https://github.com/Fallenbagel/jellyseerr) - Gerenciador de requisições
- [qBittorrent](https://www.qbittorrent.org/) - Cliente de torrent
- [rclone](https://rclone.org/) - Sincronização com cloud
- [LinuxServer.io](https://www.linuxserver.io/) - Imagens Docker otimizadas

---

<p align="center">
  Feito com ❤️ por <a href="https://github.com/Advansoftware">Advansoftware</a>
</p>
