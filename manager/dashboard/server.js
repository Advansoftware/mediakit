const express = require('express');
const session = require('express-session');
const { createServer } = require('http');
const { Server } = require('socket.io');
const { Tail } = require('tail');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const app = express();
const server = createServer(app);
const io = new Server(server);

// Configuração
const PORT = process.env.DASHBOARD_PORT || 3000;
const DASHBOARD_USER = process.env.MEDIAKIT_USER || 'admin';
const DASHBOARD_PASS = process.env.MEDIAKIT_PASS || 'adminadmin';
const QB_USER = process.env.QB_USER || 'admin';
const QB_PASS = process.env.QB_PASS || '@Brunrego2022';

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// Sessão
app.use(session({
  secret: 'mediakit-dashboard-secret-' + Date.now(),
  resave: false,
  saveUninitialized: false,
  cookie: { secure: false }
}));

// Middleware de autenticação
const requireAuth = (req, res, next) => {
  if (req.session.authenticated) {
    return next();
  }
  res.redirect('/login');
};

// Rotas
app.get('/login', (req, res) => {
  res.render('login', { error: null });
});

app.post('/login', (req, res) => {
  const { username, password } = req.body;
  if (username === DASHBOARD_USER && password === DASHBOARD_PASS) {
    req.session.authenticated = true;
    res.redirect('/');
  } else {
    res.render('login', { error: 'Credenciais inválidas' });
  }
});

app.get('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/login');
});

app.get('/', requireAuth, (req, res) => {
  res.render('dashboard');
});

// API Routes
app.get('/api/status', requireAuth, async (req, res) => {
  try {
    const status = await getSystemStatus();
    res.json(status);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/logs/:type', requireAuth, (req, res) => {
  const { type } = req.params;
  const logPath = `/app/logs/${type}.log`;
  if (!fs.existsSync(logPath)) {
    return res.json({ lines: [] });
  }
  try {
    const content = fs.readFileSync(logPath, 'utf8');
    const lines = content.split('\n').filter(line => line.trim()).slice(-100);
    res.json({ lines });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Funções auxiliares
function execCommand(command) {
  return new Promise((resolve, reject) => {
    exec(command, { timeout: 10000 }, (error, stdout, stderr) => {
      if (error) {
        resolve(''); // Não rejeitar, apenas retornar vazio
      } else {
        resolve(stdout);
      }
    });
  });
}

async function getSystemStatus() {
  const status = {
    disk: { used: 0, total: 0, free: 0, percentage: 0 },
    downloads: [],
    services: {},
    crons: [],
    cloudSync: { active: false, transfers: [], stats: {} }
  };

  try {
    // Espaço em disco
    const diskInfo = await execCommand('df -BG /downloads 2>/dev/null | tail -1');
    if (diskInfo) {
      const diskParts = diskInfo.trim().split(/\s+/);
      if (diskParts.length >= 5) {
        status.disk.total = parseInt(diskParts[1].replace('G', '')) || 0;
        status.disk.used = parseInt(diskParts[2].replace('G', '')) || 0;
        status.disk.free = parseInt(diskParts[3].replace('G', '')) || 0;
        status.disk.percentage = parseInt(diskParts[4].replace('%', '')) || 0;
      }
    }

    // Status de downloads (qBittorrent)
    try {
      await execCommand(`curl -s -X POST "http://qbittorrent:8080/api/v2/auth/login" -d "username=${QB_USER}&password=${QB_PASS}" -c /tmp/qb.cookie`);
      const qbResponse = await execCommand('curl -s -b /tmp/qb.cookie "http://qbittorrent:8080/api/v2/torrents/info"');
      if (qbResponse && qbResponse.trim().startsWith('[')) {
        const torrents = JSON.parse(qbResponse);
        status.downloads = torrents.map(t => ({
          name: t.name,
          progress: Math.round(t.progress * 100 * 10) / 10,
          speed: Math.round(t.dlspeed / 1024 / 1024 * 10) / 10,
          state: t.state,
          size: Math.round(t.size / 1024 / 1024 / 1024 * 100) / 100,
          downloaded: Math.round(t.completed / 1024 / 1024 / 1024 * 100) / 100,
          seeds: t.num_seeds,
          peers: t.num_leechs
        }));
      }
    } catch (e) {
      console.error('Erro qBittorrent:', e.message);
    }

    // Status do Cloud Sync (rclone)
    try {
      // Verificar se há transferências ativas via rclone rc
      const rcloneStats = await execCommand('curl -s "http://rclone-mount:5572/core/stats" 2>/dev/null');
      if (rcloneStats && rcloneStats.trim().startsWith('{')) {
        const stats = JSON.parse(rcloneStats);
        status.cloudSync.active = (stats.transferring && stats.transferring.length > 0);
        status.cloudSync.stats = {
          speed: Math.round((stats.speed || 0) / 1024 / 1024 * 10) / 10,
          bytes: stats.bytes || 0,
          totalBytes: stats.totalBytes || 0,
          transfers: stats.transfers || 0,
          checks: stats.checks || 0
        };
        if (stats.transferring) {
          status.cloudSync.transfers = stats.transferring.map(t => ({
            name: t.name ? t.name.split('/').pop() : 'Desconhecido',
            size: Math.round((t.size || 0) / 1024 / 1024 / 1024 * 100) / 100,
            progress: t.size ? Math.round((t.bytes || 0) / t.size * 100) : 0,
            speed: Math.round((t.speed || 0) / 1024 / 1024 * 10) / 10,
            eta: t.eta || 0
          }));
        }
      }
    } catch (e) {
      // rclone rc não disponível, tentar via arquivo de status
    }

    // Fallback: verificar arquivo de status do sync
    try {
      const syncStatus = await execCommand('cat /tmp/cloud-sync-status.json 2>/dev/null');
      if (syncStatus && syncStatus.trim().startsWith('{')) {
        const parsed = JSON.parse(syncStatus);
        if (parsed.transfers && parsed.transfers.length > 0) {
          status.cloudSync.active = true;
          status.cloudSync.transfers = parsed.transfers;
        }
      }
    } catch (e) { }

    // Status dos serviços (portas corretas)
    const servicePorts = {
      jellyfin: 8096,
      jellyseerr: 5055,
      qbittorrent: 8080,
      prowlarr: 9696,
      radarr: 7878,
      sonarr: 8989
    };

    for (const [service, port] of Object.entries(servicePorts)) {
      try {
        const response = await execCommand(`curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://${service}:${port}"`);
        const code = response.trim();
        status.services[service] = (code.startsWith('2') || code.startsWith('3') || code === '401') ? 'online' : 'offline';
      } catch (e) {
        status.services[service] = 'offline';
      }
    }

    // Cron jobs
    try {
      const crontab = await execCommand('cat /var/spool/cron/crontabs/root 2>/dev/null');
      status.crons = crontab.split('\n').filter(line => line.trim() && !line.startsWith('#'));
    } catch (e) {
      status.crons = [];
    }

  } catch (error) {
    console.error('Erro ao obter status:', error);
  }

  return status;
}

// ===========================================
// WEBSOCKET - Tempo real
// ===========================================
const logTails = {};
let statusInterval = null;

io.on('connection', (socket) => {
  console.log('Cliente conectado ao dashboard');

  // Enviar status inicial
  getSystemStatus().then(status => {
    socket.emit('status-update', status);
  });

  // Atualizar status a cada 5 segundos para este cliente
  const clientInterval = setInterval(async () => {
    try {
      const status = await getSystemStatus();
      socket.emit('status-update', status);
    } catch (e) {
      console.error('Erro ao enviar status:', e.message);
    }
  }, 5000);

  // Subscribe em logs
  socket.on('subscribe-log', (logType) => {
    const logPath = `/app/logs/${logType}.log`;

    // Enviar logs existentes
    if (fs.existsSync(logPath)) {
      try {
        const content = fs.readFileSync(logPath, 'utf8');
        const lines = content.split('\n').filter(line => line.trim()).slice(-50);
        lines.forEach(line => {
          socket.emit('log-line', { type: logType, line });
        });
      } catch (e) { }

      // Criar tail para novas linhas
      const tailKey = `${socket.id}-${logType}`;
      if (logTails[tailKey]) {
        logTails[tailKey].unwatch();
      }

      try {
        logTails[tailKey] = new Tail(logPath, { fromBeginning: false, follow: true });
        logTails[tailKey].on('line', (line) => {
          socket.emit('log-line', { type: logType, line });
        });
        logTails[tailKey].on('error', (error) => {
          console.error(`Erro no tail de ${logType}:`, error.message);
        });
      } catch (e) {
        console.error(`Erro ao criar tail para ${logType}:`, e.message);
      }
    }
  });

  socket.on('disconnect', () => {
    console.log('Cliente desconectado');
    clearInterval(clientInterval);

    // Limpar tails deste cliente
    Object.keys(logTails).forEach(key => {
      if (key.startsWith(socket.id)) {
        logTails[key].unwatch();
        delete logTails[key];
      }
    });
  });
});

// Iniciar servidor
server.listen(PORT, '0.0.0.0', () => {
  console.log(`MediaKit Dashboard rodando na porta ${PORT}`);
  console.log(`Acesse: http://localhost:${PORT}`);
  console.log(`Usuário: ${DASHBOARD_USER}`);
});
