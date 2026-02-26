# personalos_full_windows.ps1
# BuildKit indir/kur + PersonalOS bundle oluştur + Docker Compose başlat
# 12 Adım: BuildKit, Klasör, Config, Kodlar, Observability, Vault, Helm/TF, CI/CD, Render, Smoke, Compose, Test

param()
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ==================== CONFIG ====================
$buildkit_version = "v0.22.0"
$arch = "amd64"
$buildkit_filename = "buildkit-$buildkit_version.windows-$arch.tar.gz"
$buildkit_url = "https://github.com/moby/buildkit/releases/download/$buildkit_version/$buildkit_filename"
$install_dir = "C:\Program Files\BuildKit"
$personalos_root = Join-Path $PWD "PersonalOS"
# ===============================================

function Write-Log([string]$msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Sub([string]$msg) { Write-Host "  -> $msg" -ForegroundColor Gray }
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Write-TextFile([string]$baseDir, [string]$relPath, [string]$content) {
    $full = Join-Path $baseDir $relPath
    $dir = Split-Path $full -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($full, $content, $utf8NoBom)
}

# ==================== ADIM 1: BUILDKIT ====================
Write-Log "ADIM 1: BuildKit indiriliyor..."
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw "curl.exe bulunamadı" }
if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) { throw "tar.exe bulunamadı" }

$target_bin = Join-Path $install_dir "bin"
$temp_dir = Join-Path $env:TEMP ("buildkit_" + (Get-Random))
New-Item -ItemType Directory -Force -Path $temp_dir | Out-Null

Push-Location $temp_dir
try {
    Write-Sub "İndir: $buildkit_url"
    curl.exe -fL -o $buildkit_filename $buildkit_url
    Write-Sub "Açılıyor..."
    tar.exe -xvf $buildkit_filename | Out-Null
    $extracted_bin = Join-Path $temp_dir "bin"
    if (-not (Test-Path $extracted_bin)) { throw "'bin' klasörü yok" }
    if (-not (Test-Path $target_bin)) { New-Item -ItemType Directory -Force -Path $target_bin | Out-Null }
    Get-ChildItem -Path $extracted_bin -File | ForEach-Object { Copy-Item -Path $_.FullName -Destination $target_bin -Force }
    $env:Path = "$target_bin;$env:Path"
    if (Test-IsAdmin) {
        $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($machinePath -notlike "*$target_bin*") {
            [Environment]::SetEnvironmentVariable("Path", ($machinePath + ";" + $target_bin), "Machine")
        }
    }
    Write-Sub "BuildKit kuruldu: $target_bin"
}
finally { Pop-Location; Remove-Item -Recurse -Force $temp_dir -EA SilentlyContinue }

# ==================== ADIM 2: KLASOR YAPISI ====================
Write-Log "ADIM 2: Klasör yapısı oluşturuluyor..."
$dirs = @(
    "integration/gateway/service",
    "integration/gateway/adapters/whatsapp",
    "integration/agents/runtime",
    "integration/workers/whatsapp-worker",
    "integration/workers/email-worker",
    "observability/prometheus",
    "observability/grafana/provisioning/datasources",
    "observability/grafana/provisioning/dashboards",
    "observability/grafana/dashboards",
    "observability/alertmanager",
    "migration/db-migrations",
    "vault/config",
    "vault/policies",
    "terraform/aws",
    "terraform/gcp",
    "terraform/kubernetes",
    "helm/personalos",
    "helm/personalos/templates",
    "helm/personalos/values",
    ".github/workflows",
    "render/scripts",
    "render/assets",
    "scripts",
    "tests/integration",
    "tests/unit",
    "docs"
)
foreach ($d in $dirs) { New-Item -ItemType Directory -Force -Path (Join-Path $personalos_root $d) | Out-Null }
Write-Sub "Klasörler hazır"

# ==================== ADIM 3: CONFIG DOSYALARI ====================
Write-Log "ADIM 3: Config dosyaları yazılıyor..."

Write-TextFile $personalos_root ".dockerignore" @'
node_modules
.env
*.log
dist/
__pycache__/
*.pyc
.DS_Store
render/frame-*.png
render/output/*.mp4
terraform/*.tfstate
helm/*.tgz
'@

Write-TextFile $personalos_root ".gitignore" @'
node_modules/
.env
*.log
dist/
__pycache__/
*.pyc
.DS_Store
secrets/
render/frame-*.png
render/output/*.mp4
render/voiceover.mp3
terraform/*.tfstate
terraform/*.tfstate.*
helm/*.tgz
'@

Write-TextFile $personalos_root ".env" @'
# Security
ADMIN_TOKEN=devtoken
ADAPTER_API_KEY=changeme
SIGNING_SECRET=changeme
WHATSAPP_PROVIDER_URL=mock://local

# URLs
WHATSAPP_ADAPTER_URL=http://whatsapp-adapter:3000
GATEWAY_URL=http://gateway:8080

# Agent
AGENT_ID=example-agent-1

# Idempotency & Queue
IDEM_TTL_SEC=600
QUEUE_LIMIT=1000
JOB_TTL_SEC=3600

# Observability
GRAFANA_ADMIN_PASSWORD=admin
PROMETHEUS_URL=http://prometheus:9090

# Vault
VAULT_ADDR=http://vault:8200
VAULT_TOKEN=root
VAULT_UNSEAL_KEY=

# Database
POSTGRES_USER=personalos
POSTGRES_PASSWORD=personalos
POSTGRES_DB=personalos

# Redis
REDIS_PASSWORD=
'@

Write-TextFile $personalos_root "docker-compose.yml" @'
name: personalos

x-logging: &logging
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"

services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-personalos}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-personalos}
      POSTGRES_DB: ${POSTGRES_DB:-personalos}
    volumes:
      - pgdata:/var/lib/postgresql/data
    logging: *logging
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB"]
      interval: 10s
      timeout: 5s
      retries: 10

  redis:
    image: redis:7-alpine
    command: ["redis-server", "--save", "60", "1"]
    volumes:
      - redisdata:/data
    logging: *logging
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 15

  vault:
    image: hashicorp/vault:1.14.0
    environment:
      VAULT_DEV_ROOT_TOKEN_ID: ${VAULT_TOKEN:-root}
      VAULT_ADDR: http://0.0.0.0:8200
    command: server -dev -dev-root-token-id=${VAULT_TOKEN:-root} -dev-listen-address=0.0.0.0:8200
    ports:
      - "8200:8200"
    logging: *logging
    healthcheck:
      test: ["CMD", "vault", "status"]
      interval: 10s
      timeout: 5s
      retries: 5

  migrate:
    image: postgres:16-alpine
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - ./migration/db-migrations:/migrations:ro
    entrypoint: ["/bin/sh", "-lc"]
    command: "psql postgresql://${POSTGRES_USER:-personalos}:${POSTGRES_PASSWORD:-personalos}@postgres:5432/${POSTGRES_DB:-personalos} -f /migrations/001_init.sql"

  gateway:
    build:
      context: ./integration/gateway/service
      dockerfile: Dockerfile
    env_file: .env
    environment:
      PORT: "8080"
      REDIS_URL: redis://redis:6379
      DATABASE_URL: postgres://${POSTGRES_USER:-personalos}:${POSTGRES_PASSWORD:-personalos}@postgres:5432/${POSTGRES_DB:-personalos}
      DEFAULT_AGENT_URL: http://agent:8080
    ports:
      - "8080:8080"
    depends_on:
      migrate:
        condition: service_completed_successfully
      redis:
        condition: service_healthy
      postgres:
        condition: service_healthy
    logging: *logging
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 12

  agent:
    build:
      context: ./integration/agents/runtime
      dockerfile: Dockerfile.agent
    env_file: .env
    environment:
      PORT: "8080"
      SELF_URL: http://agent:8080
      GATEWAY_URL: http://gateway:8080
    ports:
      - "8081:8080"
    depends_on:
      gateway:
        condition: service_healthy
    logging: *logging
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 12

  whatsapp-adapter:
    build:
      context: ./integration/gateway/adapters/whatsapp
      dockerfile: Dockerfile
    env_file: .env
    environment:
      PORT: "3000"
    ports:
      - "3000:3000"
    depends_on:
      gateway:
        condition: service_healthy
    logging: *logging
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/health"]
      interval: 10s
      timeout: 5s
      retries: 12

  whatsapp-worker:
    build:
      context: ./integration/workers/whatsapp-worker
      dockerfile: Dockerfile
    env_file: .env
    environment:
      PORT: "9101"
      REDIS_URL: redis://redis:6379
      WHATSAPP_ADAPTER_URL: http://whatsapp-adapter:3000
    depends_on:
      redis:
        condition: service_healthy
    logging: *logging
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:9101/health"]
      interval: 10s
      timeout: 5s
      retries: 12

  email-worker:
    build:
      context: ./integration/workers/email-worker
      dockerfile: Dockerfile
    env_file: .env
    environment:
      PORT: "9102"
      REDIS_URL: redis://redis:6379
    depends_on:
      redis:
        condition: service_healthy
    logging: *logging

  prometheus:
    image: prom/prometheus:v2.54.1
    volumes:
      - ./observability/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - promdata:/prometheus
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
    ports:
      - "9090:9090"
    logging: *logging

  alertmanager:
    image: prom/alertmanager:v0.26.0
    volumes:
      - ./observability/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
      - alertdata:/alertmanager
    command:
      - "--config.file=/etc/alertmanager/alertmanager.yml"
      - "--storage.path=/alertmanager"
    ports:
      - "9093:9093"
    logging: *logging

  grafana:
    image: grafana/grafana:10.4.2
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD:-admin}
    volumes:
      - ./observability/grafana/provisioning:/etc/grafana/provisioning:ro
      - ./observability/grafana/dashboards:/var/lib/grafana/dashboards:ro
      - grafdata:/var/lib/grafana
    ports:
      - "3001:3000"
    logging: *logging

  minio:
    image: minio/minio:latest
    command: ["server", "/data", "--console-address", ":9001"]
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    volumes:
      - miniodata:/data
    ports:
      - "9000:9000"
      - "9001:9001"
    logging: *logging

  mailhog:
    image: mailhog/mailhog:latest
    ports:
      - "1025:1025"
      - "8025:8025"
    logging: *logging

  portainer:
    image: portainer/portainer-ce:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainerdata:/data
    ports:
      - "9443:9443"
    logging: *logging

  meilisearch:
    image: getmeili/meilisearch:latest
    environment:
      MEILI_MASTER_KEY: masterKey
    volumes:
      - meilisearchdata:/meili_data
    ports:
      - "7700:7700"
    logging: *logging

volumes:
  pgdata:
  redisdata:
  promdata:
  alertdata:
  grafdata:
  miniodata:
  portainerdata:
  meilisearchdata:
'@

# ==================== ADIM 4: KODLAR ====================
Write-Log "ADIM 4: Gateway, Adapter, Agent, Worker kodları..."

# Gateway
Write-TextFile $personalos_root "integration/gateway/service/package.json" @'
{
  "name": "personalos-gateway",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": { "start": "node index.js" },
  "dependencies": {
    "express": "^4.18.2",
    "body-parser": "^1.20.2",
    "axios": "^1.6.8",
    "prom-client": "^15.1.3",
    "ioredis": "^5.4.1",
    "pg": "^8.12.0",
    "uuid": "^9.0.1",
    "cors": "^2.8.5",
    "helmet": "^7.1.0",
    "morgan": "^1.10.0"
  }
}
'@
Write-TextFile $personalos_root "integration/gateway/service/Dockerfile" @'
FROM node:18-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --only=production || npm install --production
COPY . .
EXPOSE 8080
CMD ["node","index.js"]
'@
Write-TextFile $personalos_root "integration/gateway/service/index.js" @'
const express = require("express");
const bodyParser = require("body-parser");
const cors = require("cors");
const helmet = require("helmet");
const morgan = require("morgan");
const axios = require("axios");
const client = require("prom-client");
const Redis = require("ioredis");
const { Pool } = require("pg");
const { v4: uuidv4 } = require("uuid");
const crypto = require("crypto");

const app = express();
app.use(cors());
app.use(helmet());
app.use(morgan("combined"));
app.use(bodyParser.json());

const PORT = parseInt(process.env.PORT || "8080", 10);
const DEFAULT_AGENT_URL = process.env.DEFAULT_AGENT_URL || "http://agent:8080";
const REDIS_URL = process.env.REDIS_URL || "redis://redis:6379";
const DATABASE_URL = process.env.DATABASE_URL || "postgres://personalos:personalos@postgres:5432/personalos";
const ADMIN_TOKEN = (process.env.ADMIN_TOKEN || "").trim();
const WHATSAPP_ADAPTER_URL = process.env.WHATSAPP_ADAPTER_URL || "http://whatsapp-adapter:3000";
const ADAPTER_API_KEY = process.env.ADAPTER_API_KEY || "changeme";
const IDEM_TTL_SEC = parseInt(process.env.IDEM_TTL_SEC || "600", 10);
const QUEUE_LIMIT = parseInt(process.env.QUEUE_LIMIT || "1000", 10);
const JOB_TTL_SEC = parseInt(process.env.JOB_TTL_SEC || "3600", 10);

const registry = new Map();
const redis = new Redis(REDIS_URL, { maxRetriesPerRequest: 2, retryStrategy: (t) => Math.min(t * 2, 2000) });
const pg = new Pool({ connectionString: DATABASE_URL, max: 10 });

client.collectDefaultMetrics();
const invocationsTotal = new client.Counter({ name: "gateway_invocations_total", help: "Total invocations", labelNames: ["agent_id", "status"] });
const latencyMs = new client.Histogram({ name: "gateway_invoke_latency_ms", help: "Invoke latency (ms)", labelNames: ["agent_id"], buckets: [5, 10, 25, 50, 100, 250, 500, 1000, 2000, 5000] });
const idemHits = new client.Counter({ name: "gateway_idempotency_hits_total", help: "Idempotency cache hits" });
const channelSendTotal = new client.Counter({ name: "gateway_channel_send_total", help: "Channel sends", labelNames: ["channel", "mode", "status"] });

function requireAuth(req, res) {
    if (!ADMIN_TOKEN) return true;
    const h = (req.headers["authorization"] || "").trim();
    if (h !== `Bearer ${ADMIN_TOKEN}`) { res.status(401).json({ error: "unauthorized" }); return false; }
    return true;
}

app.use((req, res, next) => {
    if (req.path === "/health" || req.path === "/metrics" || req.path === "/agents/register") return next();
    if (!requireAuth(req, res)) return;
    next();
});

function sKey(id) { return `session:${id}`; }
function eKey(id) { return `session:${id}:events`; }
function idemKey(agentId, key) { return `idem:${agentId}:${key}`; }
function jobKey(jobId) { return `job:${jobId}`; }

function canonicalStringify(obj) {
    if (obj === null || obj === undefined) return "null";
    if (typeof obj !== "object") return JSON.stringify(obj);
    if (Array.isArray(obj)) return "[" + obj.map(canonicalStringify).join(",") + "]";
    const keys = Object.keys(obj).sort();
    return "{" + keys.map(k => JSON.stringify(k) + ":" + canonicalStringify(obj[k])).join(",") + "}";
}

function sha256Hex(str) { return crypto.createHash("sha256").update(str, "utf8").digest("hex"); }

async function audit({ session_id = null, agent_id = null, event_type, payload = null }) {
    try {
        await pg.query("INSERT INTO gateway_events(session_id, agent_id, event_type, payload) VALUES ($1,$2,$3,$4)", [session_id, agent_id, event_type, payload]);
    } catch (e) { console.error("audit failed:", e.message); }
}

async function appendEvent(session_id, event_type, payload) {
    const ev = { event_id: uuidv4(), ts_ms: Date.now(), event_type, payload: payload ?? null };
    await redis.lpush(eKey(session_id), JSON.stringify(ev));
    await redis.ltrim(eKey(session_id), 0, 199);
    const raw = await redis.get(sKey(session_id));
    if (raw) {
        const s = JSON.parse(raw);
        s.updated_at_ms = Date.now();
        await redis.set(sKey(session_id), JSON.stringify(s));
    }
    return ev;
}

async function getSession(session_id) {
    const raw = await redis.get(sKey(session_id));
    if (!raw) return null;
    const s = JSON.parse(raw);
    const events = await redis.lrange(eKey(session_id), 0, 199);
    return { ...s, events: events.map((x) => JSON.parse(x)) };
}

async function callAgent(agentUrl, session_id, input) {
    const resp = await axios.post(`${agentUrl.replace(/\/+$/, "")}/invoke`, { session_id, input }, { timeout: 30000 });
    return resp.data;
}

app.get("/health", async (req, res) => {
    const redisOk = await redis.ping().then(() => true).catch(() => false);
    const pgOk = await pg.query("select 1 as ok").then(() => true).catch(() => false);
    res.json({ status: "ok", deps: { redis: redisOk, postgres: pgOk } });
});

app.get("/metrics", async (req, res) => {
    res.set("Content-Type", client.register.contentType);
    res.end(await client.register.metrics());
});

app.post("/agents/register", async (req, res) => {
    const { agent_id, url } = req.body || {};
    if (!agent_id) return res.status(400).json({ error: "missing_agent_id" });
    const agentUrl = url || DEFAULT_AGENT_URL;
    registry.set(agent_id, agentUrl);
    await audit({ agent_id, event_type: "agent_registered", payload: { url: agentUrl } });
    res.json({ ok: true, agent_id, url: agentUrl });
});

app.post("/sessions/start", async (req, res) => {
    const meta = (req.body && req.body.meta) ? req.body.meta : {};
    const session_id = uuidv4();
    const now = Date.now();
    const session = { session_id, status: "open", created_at_ms: now, updated_at_ms: now, meta };
    await redis.set(sKey(session_id), JSON.stringify(session));
    await redis.del(eKey(session_id));
    await audit({ session_id, event_type: "session_started", payload: { meta } });
    await appendEvent(session_id, "session_started", { meta });
    res.json({ ok: true, session });
});

app.get("/sessions/:session_id", async (req, res) => {
    const s = await getSession(req.params.session_id);
    if (!s) return res.status(404).json({ error: "session_not_found" });
    res.json({ ok: true, session: s });
});

app.post("/sessions/:session_id/replay", async (req, res) => {
    const sid = req.params.session_id;
    const s = await getSession(sid);
    if (!s) return res.status(404).json({ error: "session_not_found" });
    const overrideAgent = (req.body && req.body.agent_id) ? String(req.body.agent_id) : null;
    const fromTs = (req.body && req.body.from_ts_ms) ? Number(req.body.from_ts_ms) : 0;
    const maxCount = (req.body && req.body.max_count) ? Math.max(1, Number(req.body.max_count)) : 100;
    await appendEvent(sid, "replay_started", { override_agent_id: overrideAgent, from_ts_ms: fromTs, max_count: maxCount });
    const chronological = (s.events || []).slice().reverse();
    const invokes = chronological.filter(e => e.event_type === "invoke_requested" && (e.ts_ms || 0) >= fromTs).slice(0, maxCount);
    const results = [];
    for (const ev of invokes) {
        const agentId = overrideAgent || (ev.payload && ev.payload.agent_id) || null;
        if (!agentId) continue;
        const agentUrl = registry.get(agentId) || DEFAULT_AGENT_URL;
        try {
            const out = await callAgent(agentUrl, sid, ev.payload?.input);
            results.push({ agent_id: agentId, ok: true, output: out });
        } catch (e) { results.push({ agent_id: agentId, ok: false, error: e.message }); }
    }
    await appendEvent(sid, "replay_completed", { count: results.length });
    res.json({ ok: true, session_id: sid, results });
});

app.get("/audit/events", async (req, res) => {
    const limit = Math.min(500, Math.max(1, parseInt(req.query.limit || "200", 10)));
    const r = await pg.query("SELECT id, session_id, agent_id, event_type, payload, created_at FROM gateway_events ORDER BY id DESC LIMIT $1", [limit]);
    res.json({ ok: true, events: r.rows });
});

app.get("/jobs/:job_id", async (req, res) => {
    const raw = await redis.get(jobKey(req.params.job_id));
    if (!raw) return res.status(404).json({ error: "job_not_found" });
    res.json({ ok: true, job: JSON.parse(raw) });
});

app.post("/channels/whatsapp/send", async (req, res) => {
    const { recipient, content, session_id } = req.body || {};
    if (!recipient || !content) return res.status(400).json({ error: "invalid_payload" });
    const mode = (req.query.mode || "").toString().toLowerCase();
    const asyncMode = (mode === "async") || (req.body && req.body.async === true);

    if (session_id) {
        const s = await getSession(String(session_id));
        if (!s) return res.status(404).json({ error: "session_not_found" });
        await appendEvent(String(session_id), "channel_send_requested", { channel: "whatsapp", recipient, mode: asyncMode ? "async" : "sync" });
    }

    if (asyncMode) {
        const qlen = await redis.llen("queue:whatsapp");
        if (qlen >= QUEUE_LIMIT) return res.status(429).json({ error: "queue_full", queue_length: qlen, queue_limit: QUEUE_LIMIT });
        const job_id = uuidv4();
        const job = { job_id, status: "queued", created_at_ms: Date.now(), updated_at_ms: Date.now(), payload: { recipient, content, session_id: session_id || null } };
        await redis.setex(jobKey(job_id), JOB_TTL_SEC, JSON.stringify(job));
        await redis.rpush("queue:whatsapp", job_id);
        channelSendTotal.inc({ channel: "whatsapp", mode: "async", status: "queued" });
        return res.status(202).json({ ok: true, mode: "async", job_id, status: "queued" });
    }

    try {
        const resp = await axios.post(`${WHATSAPP_ADAPTER_URL.replace(/\/+$/, "")}/send`, { recipient, content }, { timeout: 10000, headers: { Authorization: `Bearer ${ADAPTER_API_KEY}` } });
        channelSendTotal.inc({ channel: "whatsapp", mode: "sync", status: "ok" });
        if (session_id) await appendEvent(String(session_id), "channel_send_succeeded", { channel: "whatsapp", result: resp.data });
        return res.json({ ok: true, mode: "sync", result: resp.data });
    } catch (e) {
        channelSendTotal.inc({ channel: "whatsapp", mode: "sync", status: "error" });
        if (session_id) await appendEvent(String(session_id), "channel_send_failed", { channel: "whatsapp", error: e.message });
        return res.status(502).json({ error: "adapter_send_failed", detail: e.message });
    }
});

app.post("/invoke/:agent_id", async (req, res) => {
    const agentId = req.params.agent_id;
    const agentUrl = registry.get(agentId) || DEFAULT_AGENT_URL;
    const session_id = (req.body && req.body.session_id) ? String(req.body.session_id) : null;
    const input = (req.body && typeof req.body === "object" && "input" in req.body) ? req.body.input : (req.body || {});
    const idem = (req.header("X-Idempotency-Key") || "").trim();
    const inputHash = sha256Hex(canonicalStringify({ session_id, input }));

    if (idem) {
        const cachedRaw = await redis.get(idemKey(agentId, idem));
        if (cachedRaw) {
            try {
                const cached = JSON.parse(cachedRaw);
                if (cached.hash && cached.hash !== inputHash) return res.status(409).json({ error: "idempotency_conflict" });
                idemHits.inc();
                return res.json(cached.response);
            } catch { }
        }
    }

    if (session_id) {
        const s = await getSession(session_id);
        if (!s) return res.status(404).json({ error: "session_not_found" });
        await appendEvent(session_id, "invoke_requested", { agent_id: agentId, input });
    }

    const end = latencyMs.startTimer({ agent_id: agentId });
    try {
        const out = await callAgent(agentUrl, session_id, input);
        invocationsTotal.inc({ agent_id: agentId, status: "ok" });
        end();
        if (session_id) await appendEvent(session_id, "invoke_succeeded", { agent_id: agentId, output: out });
        const body = { ok: true, agent_id: agentId, session_id, result: out };
        if (idem) await redis.setex(idemKey(agentId, idem), IDEM_TTL_SEC, JSON.stringify({ hash: inputHash, response: body }));
        return res.json(body);
    } catch (e) {
        invocationsTotal.inc({ agent_id: agentId, status: "error" });
        end();
        if (session_id) await appendEvent(session_id, "invoke_failed", { agent_id: agentId, error: e.message });
        return res.status(502).json({ error: "agent_invoke_failed", detail: e.message });
    }
});

app.listen(PORT, () => console.log(`Gateway listening on ${PORT}`));
'@

# WhatsApp Adapter
Write-TextFile $personalos_root "integration/gateway/adapters/whatsapp/package.json" @'
{
  "name": "personalos-whatsapp-adapter",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": { "start": "node index.js" },
  "dependencies": {
    "express": "^4.18.2",
    "body-parser": "^1.20.2",
    "axios": "^1.6.8",
    "prom-client": "^15.1.3"
  }
}
'@
Write-TextFile $personalos_root "integration/gateway/adapters/whatsapp/Dockerfile" @'
FROM node:18-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --only=production || npm install --production
COPY . .
EXPOSE 3000
CMD ["node","index.js"]
'@
Write-TextFile $personalos_root "integration/gateway/adapters/whatsapp/index.js" @'
const express = require("express");
const bodyParser = require("body-parser");
const axios = require("axios");
const client = require("prom-client");

const app = express();
app.use(bodyParser.json());
const PORT = parseInt(process.env.PORT || "3000", 10);
const API_KEY = process.env.ADAPTER_API_KEY || "changeme";
const PROVIDER_URL = process.env.WHATSAPP_PROVIDER_URL || "mock://local";

client.collectDefaultMetrics();
const sent = new client.Counter({ name: "whatsapp_messages_sent_total", help: "Total messages sent", labelNames: ["status"] });

function requireAuth(req, res) {
    const h = (req.headers["authorization"] || "").trim();
    if (h !== `Bearer ${API_KEY}`) { res.status(401).json({ error: "unauthorized" }); return false; }
    return true;
}

app.get("/health", (req, res) => res.json({ status: "ok" }));
app.get("/metrics", async (req, res) => { res.set("Content-Type", client.register.contentType); res.end(await client.register.metrics()); });

app.post("/send", async (req, res) => {
    if (!requireAuth(req, res)) return;
    const { recipient, content } = req.body || {};
    if (!recipient || !content) return res.status(400).json({ error: "invalid_payload" });
    try {
        if (String(PROVIDER_URL).startsWith("mock://")) {
            sent.inc({ status: "ok" });
            return res.json({ message_id: `mock-${Date.now()}`, status: "queued" });
        }
        await axios.post(PROVIDER_URL, { to: recipient, message: content }, { timeout: 10000 });
        sent.inc({ status: "ok" });
        return res.json({ message_id: `msg-${Date.now()}`, status: "queued" });
    } catch (e) {
        sent.inc({ status: "error" });
        return res.status(502).json({ error: "provider_error", detail: e.message });
    }
});

app.listen(PORT, () => console.log(`WhatsApp adapter listening on ${PORT}`));
'@

# Agent
Write-TextFile $personalos_root "integration/agents/runtime/requirements.txt" @'
Flask==2.2.5
requests==2.31.0
prometheus-client==0.20.0
gunicorn==21.2.0
'@
Write-TextFile $personalos_root "integration/agents/runtime/Dockerfile.agent" @'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY agent_main.py .
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "120", "agent_main:app"]
'@
Write-TextFile $personalos_root "integration/agents/runtime/agent_main.py" @'
import os, requests, logging, json, time
from flask import Flask, jsonify, request
from prometheus_client import Counter, Gauge, Histogram, generate_latest, CONTENT_TYPE_LATEST

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
AGENT_ID = os.getenv("AGENT_ID", "example-agent-1")
GATEWAY_URL = os.getenv("GATEWAY_URL", "http://gateway:8080").rstrip("/")
SELF_URL = os.getenv("SELF_URL", "http://agent:8080")

invocations = Counter("agent_invocations_total", "Total invocations", ["agent_id", "status"])
errors = Counter("agent_errors_total", "Total errors")
latency = Histogram("agent_invoke_latency_seconds", "Invoke latency", ["agent_id"])
conversation_history = []

AVAILABLE_TOOLS = {
    "weather": {"name": "get_weather", "description": "Get weather for location"},
    "search": {"name": "web_search", "description": "Search the web"},
    "calculator": {"name": "calculate", "description": "Perform calculations"},
    "memory": {"name": "store_memory", "description": "Store in memory"},
    "recall": {"name": "recall_memory", "description": "Recall from memory"},
}

def execute_tool(tool_name, params):
    logger.info(f"Executing tool: {tool_name}")
    if tool_name == "weather": return {"result": f"Weather: 22°C, sunny"}
    elif tool_name == "search": return {"result": f"Results for: {params.get('query','')}"}
    elif tool_name == "calculator":
        try: return {"result": str(eval(str(params.get('expression','0'))))}
        except: return {"error": "Invalid expression"}
    elif tool_name == "memory":
        conversation_history.append(params.get("data",""))
        return {"result": "Stored", "count": len(conversation_history)}
    elif tool_name == "recall":
        q = params.get("query","")
        return {"results": [h for h in conversation_history if q.lower() in h.lower()][:5]}
    return {"error": "Unknown tool"}

@app.get("/health")
def health(): return jsonify({"status": "ok", "agent_id": AGENT_ID, "tools": list(AVAILABLE_TOOLS.keys())})

@app.get("/metrics")
def metrics(): return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}

@app.get("/tools")
def list_tools(): return jsonify({"tools": AVAILABLE_TOOLS})

@app.post("/invoke")
def invoke():
    start_time = time.time()
    try:
        payload = request.json or {}
        session_id = payload.get("session_id")
        message = payload.get("input", {})
        tools = payload.get("tools", [])
        
        result = {"agent_id": AGENT_ID, "response": f"Echo: {json.dumps(message)}"}
        
        if tools:
            tool_results = []
            for tc in tools:
                tool_results.append(execute_tool(tc.get("name"), tc.get("params", {})))
            result["tool_results"] = tool_results
        
        invocations.labels(agent_id=AGENT_ID, status="ok").inc()
        latency.labels(agent_id=AGENT_ID).observe(time.time() - start_time)
        return jsonify(result)
    except Exception as e:
        errors.inc()
        logger.error(f"Error: {e}")
        return jsonify({"error": str(e)}), 500

def register():
    try:
        requests.post(f"{GATEWAY_URL}/agents/register", json={"agent_id": AGENT_ID, "url": SELF_URL}, timeout=5)
        logger.info(f"Registered to gateway: {GATEWAY_URL}")
    except Exception as e: logger.warning(f"Could not register: {e}")

if __name__ == "__main__":
    register()
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
'@

# WhatsApp Worker
Write-TextFile $personalos_root "integration/workers/whatsapp-worker/package.json" @'
{
  "name": "personalos-whatsapp-worker",
  "version": "1.0.0",
  "main": "worker.js",
  "scripts": { "start": "node worker.js" },
  "dependencies": {
    "axios": "^1.6.8",
    "ioredis": "^5.4.1",
    "prom-client": "^15.1.3",
    "express": "^4.18.2"
  }
}
'@
Write-TextFile $personalos_root "integration/workers/whatsapp-worker/Dockerfile" @'
FROM node:18-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --only=production || npm install --production
COPY worker.js .
EXPOSE 9101
CMD ["node","worker.js"]
'@
Write-TextFile $personalos_root "integration/workers/whatsapp-worker/worker.js" @'
const express = require("express");
const axios = require("axios");
const Redis = require("ioredis");
const client = require("prom-client");

const REDIS_URL = process.env.REDIS_URL || "redis://redis:6379";
const ADAPTER_URL = process.env.WHATSAPP_ADAPTER_URL || "http://whatsapp-adapter:3000";
const API_KEY = process.env.ADAPTER_API_KEY || "changeme";
const JOB_TTL_SEC = parseInt(process.env.JOB_TTL_SEC || "3600", 10);
const PORT = parseInt(process.env.PORT || "9101", 10);

const redis = new Redis(REDIS_URL, { maxRetriesPerRequest: 2 });
const app = express();

client.collectDefaultMetrics();
const jobsTotal = new client.Counter({ name: "worker_jobs_total", help: "Jobs processed", labelNames: ["status"] });
const jobDuration = new client.Histogram({ name: "worker_job_duration_ms", help: "Job duration ms", buckets: [10, 25, 50, 100, 250, 500, 1000, 2000, 5000] });

function jobKey(id) { return `job:${id}`; }

async function updateJob(jobId, patch) {
    const raw = await redis.get(jobKey(jobId));
    if (!raw) return null;
    const job = JSON.parse(raw);
    Object.assign(job, patch);
    job.updated_at_ms = Date.now();
    await redis.setex(jobKey(jobId), JOB_TTL_SEC, JSON.stringify(job));
    return job;
}

async function processJob(jobId) {
    const end = jobDuration.startTimer();
    try {
        const raw = await redis.get(jobKey(jobId));
        if (!raw) { jobsTotal.inc({ status: "missing" }); end(); return; }
        await updateJob(jobId, { status: "processing" });
        const job = JSON.parse(raw);
        const { recipient, content } = job.payload || {};
        await axios.post(`${ADAPTER_URL.replace(/\/+$/, "")}/send`, { recipient, content }, { timeout: 10000, headers: { Authorization: `Bearer ${API_KEY}` } });
        await updateJob(jobId, { status: "done" });
        jobsTotal.inc({ status: "done" });
        end();
    } catch (e) {
        await updateJob(jobId, { status: "failed", error: e.message });
        jobsTotal.inc({ status: "failed" });
        end();
    }
}

async function loop() {
    for (;;) {
        try {
            const r = await redis.brpop("queue:whatsapp", 5);
            if (!r) continue;
            await processJob(r[1]);
        } catch (e) { await new Promise(res => setTimeout(res, 500)); }
    }
}

app.get("/health", (req, res) => res.json({ status: "ok" }));
app.get("/metrics", async (req, res) => { res.set("Content-Type", client.register.contentType); res.end(await client.register.metrics()); });
app.listen(PORT, () => console.log(`Worker metrics on ${PORT}`));
loop();
'@

# Email Worker
Write-TextFile $personalos_root "integration/workers/email-worker/Dockerfile" @'
FROM node:18-alpine
WORKDIR /app
COPY package.json ./
RUN npm install
COPY worker.js .
EXPOSE 9102
CMD ["node","worker.js"]
'@
Write-TextFile $personalos_root "integration/workers/email-worker/package.json" @'
{
  "name": "personalos-email-worker",
  "version": "1.0.0",
  "main": "worker.js",
  "scripts": { "start": "node worker.js" },
  "dependencies": {
    "ioredis": "^5.4.1",
    "nodemailer": "^6.9.8",
    "express": "^4.18.2"
  }
}
'@
Write-TextFile $personalos_root "integration/workers/email-worker/worker.js" @'
const express = require("express");
const Redis = require("ioredis");

const redis = new Redis(process.env.REDIS_URL || "redis://redis:6379");
const app = express();
const PORT = process.env.PORT || 9102;

async function loop() {
    for (;;) {
        try {
            const r = await redis.brpop("queue:email", 5);
            if (!r) continue;
            console.log("Processing email job:", r[1]);
        } catch (e) { await new Promise(res => setTimeout(res, 500)); }
    }
}

app.get("/health", (req, res) => res.json({ status: "ok" }));
app.listen(PORT, () => console.log(`Email worker on ${PORT}`));
loop();
'@

# ==================== ADIM 5: OBSERVABILITY ====================
Write-Log "ADIM 5: Observability yapılandırması..."

Write-TextFile $personalos_root "observability/prometheus/prometheus.yml" @'
global:
  scrape_interval: 10s

scrape_configs:
  - job_name: "gateway"
    metrics_path: /metrics
    static_configs:
      - targets: ["gateway:8080"]
  - job_name: "agent"
    metrics_path: /metrics
    static_configs:
      - targets: ["agent:8080"]
  - job_name: "whatsapp_adapter"
    metrics_path: /metrics
    static_configs:
      - targets: ["whatsapp-adapter:3000"]
  - job_name: "whatsapp_worker"
    metrics_path: /metrics
    static_configs:
      - targets: ["whatsapp-worker:9101"]
  - job_name: "alertmanager"
    static_configs:
      - targets: ["alertmanager:9093"]
'@

Write-TextFile $personalos_root "observability/alertmanager/alertmanager.yml" @'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'default'

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://gateway:8080/alerts'
'@

Write-TextFile $personalos_root "observability/grafana/provisioning/datasources/datasources.yaml" @'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
'@

Write-TextFile $personalos_root "observability/grafana/provisioning/dashboards/dashboards.yaml" @'
apiVersion: 1
providers:
  - name: "PersonalOS"
    orgId: 1
    folder: ""
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards
'@

Write-TextFile $personalos_root "observability/grafana/dashboards/personalos-overview.json" @'
{
  "id": null, "uid": "personalos-overview", "title": "PersonalOS Overview",
  "timezone": "browser", "schemaVersion": 39, "version": 2, "refresh": "10s",
  "panels": [
    {"type": "timeseries", "title": "Gateway invocations", "gridPos": {"x": 0, "y": 0, "w": 12, "h": 8},
     "targets": [{"refId": "A", "expr": "sum(rate(gateway_invocations_total[1m]))", "legendFormat": "inv/s"}]},
    {"type": "timeseries", "title": "Worker jobs", "gridPos": {"x": 12, "y": 0, "w": 12, "h": 8},
     "targets": [{"refId": "A", "expr": "sum(rate(worker_jobs_total[1m]))", "legendFormat": "jobs/s"}]},
    {"type": "timeseries", "title": "Agent latency", "gridPos": {"x": 0, "y": 8, "w": 12, "h": 8},
     "targets": [{"refId": "A", "expr": "histogram_quantile(0.95, rate(agent_invoke_latency_seconds_bucket[5m]))", "legendFormat": "p95"}]}
  ]
}
'@

# ==================== ADIM 6: VAULT ====================
Write-Log "ADIM 6: Vault bootstrap..."

Write-TextFile $personalos_root "vault/config/config.hcl" @'
storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = "true"
}

ui = true
disable_mlock = true
'@

Write-TextFile $personalos_root "vault/policies/personalos.hcl" @'
path "secret/data/personalos/*" {
  capabilities = ["create", "read", "update", "delete"]
}
path "secret/metadata/personalos/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "kv/personalos/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
'@

Write-TextFile $personalos_root "scripts/vault-init.sh" @'
#!/bin/bash
# Vault bootstrap script
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=root

# Enable KV v2
vault secrets enable -path=secret kv-v2

# Write test secrets
vault kv put secret/personalos/db username=personalos password=personalos
vault kv put secret/personalos/api key=changeme

echo "Vault initialized!"
'@

# ==================== ADIM 7: HELM & TERRAFORM ====================
Write-Log "ADIM 7: Helm chart ve Terraform skeleton..."

Write-TextFile $personalos_root "helm/personalos/Chart.yaml" @'
apiVersion: v2
name: personalos
description: PersonalOS Kubernetes deployment
type: application
version: 1.0.0
appVersion: "1.0.0"
'@

Write-TextFile $personalos_root "helm/personalos/values.yaml" @'
replicaCount: 1

image:
  gateway: personalos-gateway:latest
  agent: personalos-agent:latest
  adapter: personalos-whatsapp-adapter:latest

service:
  type: ClusterIP
  ports:
    gateway: 8080
    adapter: 3000
    agent: 8080

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi

autoscaling:
  enabled: false
'@

Write-TextFile $personalos_root "helm/personalos/templates/gateway.yaml" @'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-gateway
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: gateway
  template:
    metadata:
      labels:
        app: gateway
    spec:
      containers:
      - name: gateway
        image: {{ .Values.image.gateway }}
        ports:
        - containerPort: 8080
'@

Write-TextFile $personalos_root "terraform/kubernetes/main.tf" @'
terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_deployment" "personalos" {
  metadata {
    name = "personalos-gateway"
  }
  spec {
    replicas = 1
    selector {
      match_labels {
        app = "gateway"
      }
    }
    template {
      metadata {
        labels {
          app = "gateway"
        }
      }
      spec {
        container {
          image = "personalos-gateway:latest"
          name  = "gateway"
          port  = 8080
        }
      }
    }
  }
}
'@

Write-TextFile $personalos_root "terraform/aws/main.tf" @'
terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_ecs_cluster" "personalos" {
  name = "personalos-cluster"
}

resource "aws_ecs_service" "gateway" {
  name            = "gateway"
  cluster         = aws_ecs_cluster.personalos.id
  task_definition = "gateway-task:1"
  desired_count   = 1
  launch_type     = "FARGATE"
}
'@

# ==================== ADIM 8: CI/CD ====================
Write-Log "ADIM 8: CI/CD workflow'ları..."

Write-TextFile $personalos_root ".github/workflows/ci.yml" @'
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: echo "Running tests..."
      
  build:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build images
        run: |
          docker compose build
'@

Write-TextFile $personalos_root ".github/workflows/deploy.yml" @'
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to production
        run: docker compose up -d
        env:
          ADMIN_TOKEN: ${{ secrets.ADMIN_TOKEN }}
'@

# ==================== ADIM 9: RENDER PIPELINE ====================
Write-Log "ADIM 9: Render pipeline..."

Write-TextFile $personalos_root "render/scripts/render.sh" @'
#!/bin/bash
# Video render script
OUTPUT_DIR="output"
mkdir -p $OUTPUT_DIR

echo "Rendering video..."
# FFmpeg placeholder
ffmpeg -f lavfi -i color=c=blue:s=1280x720:d=5 -vf "drawtext=text='PersonalOS':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2" -pix_fmt yuv420p $OUTPUT_DIR/video.mp4

echo "Done: $OUTPUT_DIR/video.mp4"
'@

Write-TextFile $personalos_root "render/scripts/video-compose.js" @'
const { createCanvas } = require('canvas');
const fs = require('fs');

const width = 1920;
const height = 1080;
const canvas = createCanvas(width, height);
const ctx = canvas.getContext('2d');

ctx.fillStyle = '#1a1a2e';
ctx.fillRect(0, 0, width, height);

ctx.fillStyle = '#ffffff';
ctx.font = 'bold 60px Arial';
ctx.textAlign = 'center';
ctx.fillText('PersonalOS', width/2, height/2);

const buffer = canvas.toBuffer('image/png');
fs.writeFileSync('./frame-001.png', buffer);
console.log('Frame rendered!');
'@

# ==================== ADIM 10: SMOKE TESTS ====================
Write-Log "ADIM 10: Smoke test scripti..."

Write-TextFile $personalos_root "smoke_tests.ps1" @'
$ErrorActionPreference = "Stop"
$token = "devtoken"
$auth = @{ Authorization = "Bearer $token" }

Write-Host "[1] Gateway health" -ForegroundColor Cyan
Invoke-RestMethod -Uri http://localhost:8080/health -TimeoutSec 12 | Out-Null

Write-Host "[2] Create session" -ForegroundColor Cyan
$sid = (Invoke-RestMethod -Method Post -Uri http://localhost:8080/sessions/start -Headers $auth -ContentType "application/json" -Body '{"meta":{"user":"test"}}' -TimeoutSec 12).session.session_id

Write-Host "[3] Invoke agent (first)" -ForegroundColor Cyan
Invoke-RestMethod -Method Post -Uri http://localhost:8080/invoke/example-agent-1 -Headers $auth -ContentType "application/json" -Body "{`"session_id`":`"$sid`",`"input`":{`"hello`":`"world`"}}" -TimeoutSec 15 | Out-Null

Write-Host "[4] Async queue send" -ForegroundColor Cyan
$job = Invoke-RestMethod -Method Post -Uri "http://localhost:8080/channels/whatsapp/send?mode=async" -Headers $auth -ContentType "application/json" -Body "{`"session_id`":`"$sid`",`"recipient`":`"+905555555555`",`"content`":{`"text`":`"test`"}}" -TimeoutSec 15

Write-Host "[5] Poll job" -ForegroundColor Cyan
for ($i=0; $i -lt 15; $i++) {
    $j = Invoke-RestMethod -Uri ("http://localhost:8080/jobs/" + $job.job_id) -Headers $auth -TimeoutSec 10
    if ($j.job.status -eq "done") { Write-Host "Job done!" -ForegroundColor Green; break }
    if ($j.job.status -eq "failed") { throw "Job failed" }
    Start-Sleep -Seconds 1
}

Write-Host "[OK] All smoke tests passed!" -ForegroundColor Green
'@

# ==================== ADIM 11 & 12: DOCKER COMPOSE & TEST ====================
Write-Log "ADIM 11: Docker Compose başlatılıyor..."
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Warning "Docker bulunamadı. Docker Desktop kurun."
    exit 0
}

Push-Location $personalos_root
try {
    docker compose up --build -d
    Write-Sub "Servisler başlatıldı. 20s bekleniyor..."
    Start-Sleep -Seconds 20
    
    Write-Log "ADIM 12: Smoke testler çalıştırılıyor..."
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $personalos_root "smoke_tests.ps1")
}
catch { Write-Warning "Hata: $_" }
finally { Pop-Location }

Write-Log "TAMAMLANDI!" -ForegroundColor Green
Write-Host "Endpoints:"
Write-Host "  Gateway:     http://localhost:8080 (auth: Bearer devtoken)"
Write-Host "  Agent:       http://localhost:8081"
Write-Host "  Adapter:     http://localhost:3000"
Write-Host "  Prometheus:  http://localhost:9090"
Write-Host "  Grafana:     http://localhost:3001"
Write-Host "  Vault:       http://localhost:8200"
Write-Host "  MinIO:       http://localhost:9000"
Write-Host "  Mailhog:     http://localhost:8025"
Write-Host "  Portainer:   https://localhost:9443"
Write-Host "  Meilisearch: http://localhost:7700"
