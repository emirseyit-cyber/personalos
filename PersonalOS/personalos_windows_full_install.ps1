# personalos_windows_full_install.ps1
# DEVAM: BuildKit indir/kur + PersonalOS platform PoC (Gateway+Agent+Adapter+Worker+Obs)
# Ekler: RBAC token, Idempotency(payload-hash), Session Replay(filters), Async Queue + Worker(backpressure), Metrics

param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------- CONFIG ----------
$buildkit_version  = "v0.22.0"
$arch              = "amd64"
$buildkit_filename = "buildkit-$buildkit_version.windows-$arch.tar.gz"
$buildkit_url      = "https://github.com/moby/buildkit/releases/download/$buildkit_version/$buildkit_filename"

$install_dir     = "C:\Program Files\BuildKit"
$personalos_root = Join-Path $PWD "PersonalOS"
# ---------------------------

function Write-Log([string]$msg) { Write-Host "[*] $msg" }

function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-TextFile([string]$baseDir, [string]$relPath, [string]$content) {
  $full = Join-Path $baseDir $relPath
  $dir  = Split-Path $full -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($full, $content, $utf8NoBom)
}

# ---------- Preflight ----------
Write-Log "Kontrol: curl.exe ve tar.exe mevcut mu?"
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw "curl.exe bulunamadı." }
if (-not (Get-Command tar.exe  -ErrorAction SilentlyContinue)) { throw "tar.exe bulunamadı." }

# ---------- BuildKit indir/kur ----------
$target_bin = Join-Path $install_dir "bin"

Write-Log "BuildKit indir/kur: $buildkit_version ($arch)"
$temp_dir = Join-Path $env:TEMP ("buildkit_install_" + (Get-Random))
New-Item -ItemType Directory -Force -Path $temp_dir | Out-Null

Push-Location $temp_dir
try {
  Write-Log "İndiriliyor: $buildkit_url"
  curl.exe -fL -o $buildkit_filename $buildkit_url

  if (Test-Path ".\bin") {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Rename-Item ".\bin" ".\bin.backup.$stamp"
  }

  Write-Log "Arşiv açılıyor..."
  tar.exe -xvf $buildkit_filename | Out-Null

  $extracted_bin = Join-Path $temp_dir "bin"
  if (-not (Test-Path $extracted_bin)) { throw "Beklenen 'bin' klasörü bulunamadı." }

  if (-not (Test-Path $target_bin)) {
    Write-Log "Kurulum dizini oluşturuluyor: $target_bin"
    New-Item -ItemType Directory -Force -Path $target_bin | Out-Null
  }

  Write-Log "BuildKit ikilileri kopyalanıyor..."
  Get-ChildItem -Path $extracted_bin -File | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $target_bin -Force
  }

  $env:Path = "$target_bin;$env:Path"

  if (Test-IsAdmin) {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -notlike "*$target_bin*") {
      [Environment]::SetEnvironmentVariable("Path", ($machinePath + ";" + $target_bin), "Machine")
      Write-Log "PATH (Machine) güncellendi."
    }
  }

  $ver = & (Join-Path $target_bin "buildctl.exe") --version 2>&1
  Write-Log "buildctl OK: $ver"

  if (Test-IsAdmin) {
    $svcName = "buildkitd"
    $exe     = Join-Path $target_bin "buildkitd.exe"
    $args    = "--addr npipe:////./pipe/buildkitd"

    $existing = (sc.exe query $svcName 2>$null) | Out-String
    if ($existing -notmatch "SERVICE_NAME") {
      Write-Log "Windows Service oluşturuluyor: $svcName"
      sc.exe create $svcName binPath= "`"$exe`" $args" start= auto | Out-Null
    }
    Write-Log "Windows Service başlatılıyor: $svcName"
    sc.exe start $svcName | Out-Null
  }
}
finally {
  Pop-Location
  Remove-Item -Recurse -Force $temp_dir -ErrorAction SilentlyContinue
}

# ---------- PersonalOS bundle ----------
Write-Log "PersonalOS oluşturuluyor: $personalos_root"
New-Item -ItemType Directory -Force -Path $personalos_root | Out-Null

@(
  "integration/gateway/service",
  "integration/gateway/adapters/whatsapp",
  "integration/agents/runtime",
  "integration/workers/whatsapp-worker",
  "observability/prometheus",
  "observability/grafana/provisioning/datasources",
  "observability/grafana/provisioning/dashboards",
  "observability/grafana/dashboards",
  "migration/db-migrations"
) | ForEach-Object {
  New-Item -ItemType Directory -Force -Path (Join-Path $personalos_root $_) | Out-Null
}

Write-TextFile $personalos_root ".dockerignore" @'
node_modules
.env
*.log
dist/
__pycache__/
*.pyc
.DS_Store
render/frame-*.png
'@

Write-TextFile $personalos_root ".gitignore" @'
node_modules/
.env
*.log
dist/
__pycache__/
*.pyc
.DS_Store
secrets/*
render/frame-*.png
render/opode_*.mp4
render/voiceover.mp3
'@

Write-TextFile $personalos_root ".env" @'
# Security (RBAC stub)
ADMIN_TOKEN=devtoken

# Adapter auth
ADAPTER_API_KEY=changeme
SIGNING_SECRET=changeme

# Provider: internet bağımsız mock default
WHATSAPP_PROVIDER_URL=mock://local

# Gateway routing
WHATSAPP_ADAPTER_URL=http://whatsapp-adapter:3000

# Agent
AGENT_ID=example-agent-1
GATEWAY_URL=http://gateway:8080

# Idempotency
IDEM_TTL_SEC=600

# Queue/backpressure
QUEUE_LIMIT=1000
JOB_TTL_SEC=3600

# Grafana
GRAFANA_ADMIN_PASSWORD=admin
'@

# ---------- Migration ----------
Write-TextFile $personalos_root "migration/db-migrations/001_init.sql" @'
create table if not exists gateway_events (
  id bigserial primary key,
  session_id uuid,
  agent_id text,
  event_type text not null,
  payload jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_gateway_events_session on gateway_events(session_id);
create index if not exists idx_gateway_events_agent on gateway_events(agent_id);
create index if not exists idx_gateway_events_type on gateway_events(event_type);
create index if not exists idx_gateway_events_created on gateway_events(created_at);
'@

# ---------- Prometheus ----------
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
'@

# ---------- Grafana provisioning ----------
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
  "id": null,
  "uid": "personalos-overview",
  "title": "PersonalOS Overview",
  "timezone": "browser",
  "schemaVersion": 39,
  "version": 2,
  "refresh": "10s",
  "panels": [
    {
      "type": "timeseries",
      "title": "Gateway invocations (rate)",
      "gridPos": { "x": 0, "y": 0, "w": 12, "h": 8 },
      "targets": [{ "refId": "A", "expr": "sum(rate(gateway_invocations_total[1m]))", "legendFormat": "inv/s" }]
    },
    {
      "type": "timeseries",
      "title": "Idempotency hits (rate)",
      "gridPos": { "x": 12, "y": 0, "w": 12, "h": 8 },
      "targets": [{ "refId": "A", "expr": "sum(rate(gateway_idempotency_hits_total[1m]))", "legendFormat": "hits/s" }]
    },
    {
      "type": "timeseries",
      "title": "Worker jobs (rate)",
      "gridPos": { "x": 0, "y": 8, "w": 12, "h": 8 },
      "targets": [{ "refId": "A", "expr": "sum(rate(worker_jobs_total[1m]))", "legendFormat": "jobs/s" }]
    }
  ]
}
'@

# =========================
# Gateway (Node)
# =========================
Write-TextFile $personalos_root "integration/gateway/service/package.json" @'
{
  "name": "personalos-gateway",
  "version": "0.7.0",
  "main": "index.js",
  "scripts": { "start": "node index.js" },
  "dependencies": {
    "express": "^4.18.2",
    "body-parser": "^1.20.2",
    "axios": "^1.6.8",
    "prom-client": "^15.1.3",
    "ioredis": "^5.4.1",
    "pg": "^8.12.0",
    "uuid": "^9.0.1"
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
const axios = require("axios");
const client = require("prom-client");
const Redis = require("ioredis");
const { Pool } = require("pg");
const { v4: uuidv4 } = require("uuid");
const crypto = require("crypto");

const app = express();
app.use(bodyParser.json());

const PORT = parseInt(process.env.PORT || "8080", 10);
const DEFAULT_AGENT_URL = process.env.DEFAULT_AGENT_URL || "http://agent:8080";
const REDIS_URL = process.env.REDIS_URL || "redis://redis:6379";
const DATABASE_URL = process.env.DATABASE_URL || "postgres://personalos:personalos@postgres:5432/personalos";

const ADMIN_TOKEN = (process.env.ADMIN_TOKEN || "").trim();

const WHATSAPP_ADAPTER_URL = process.env.WHATSAPP_ADAPTER_URL || "http://whatsapp-adapter:3000";
const ADAPTER_API_KEY = process.env.ADAPTER_API_KEY || "changeme";

const IDEM_TTL_SEC = parseInt(process.env.IDEM_TTL_SEC || "600", 10);
const QUEUE_LIMIT  = parseInt(process.env.QUEUE_LIMIT || "1000", 10);
const JOB_TTL_SEC  = parseInt(process.env.JOB_TTL_SEC || "3600", 10);

const registry = new Map();
const redis = new Redis(REDIS_URL, { maxRetriesPerRequest: 2 });
const pg = new Pool({ connectionString: DATABASE_URL, max: 5 });

client.collectDefaultMetrics();
const invocationsTotal = new client.Counter({ name: "gateway_invocations_total", help: "Total invocations", labelNames: ["agent_id","status"] });
const latencyMs = new client.Histogram({ name: "gateway_invoke_latency_ms", help: "Invoke latency (ms)", labelNames: ["agent_id"], buckets: [5,10,25,50,100,250,500,1000,2000,5000] });
const idemHits = new client.Counter({ name: "gateway_idempotency_hits_total", help: "Idempotency cache hits" });
const replayTotal = new client.Counter({ name: "gateway_replay_total", help: "Replay operations", labelNames: ["status"] });
const channelSendTotal = new client.Counter({ name: "gateway_channel_send_total", help: "Channel sends", labelNames: ["channel","mode","status"] });

const queueLenGauge = new client.Gauge({
  name: "gateway_whatsapp_queue_length",
  help: "WhatsApp queue length",
  collect: async function() {
    try {
      const n = await redis.llen("queue:whatsapp");
      this.set(n);
    } catch {
      this.set(NaN);
    }
  }
});

function requireAuth(req, res) {
  if (!ADMIN_TOKEN) return true;
  const h = (req.headers["authorization"] || "").trim();
  if (h !== `Bearer ${ADMIN_TOKEN}`) {
    res.status(401).json({ error: "unauthorized" });
    return false;
  }
  return true;
}

app.use((req, res, next) => {
  if (req.path === "/health" || req.path === "/metrics" || req.path === "/agents/register") return next();
  if (!requireAuth(req, res)) return;
  next();
});

function sKey(id){ return `session:${id}`; }
function eKey(id){ return `session:${id}:events`; }
function idemKey(agentId, key){ return `idem:${agentId}:${key}`; }
function jobKey(jobId){ return `job:${jobId}`; }

function canonicalStringify(obj) {
  if (obj === null || obj === undefined) return "null";
  if (typeof obj !== "object") return JSON.stringify(obj);
  if (Array.isArray(obj)) return "[" + obj.map(canonicalStringify).join(",") + "]";
  const keys = Object.keys(obj).sort();
  return "{" + keys.map(k => JSON.stringify(k) + ":" + canonicalStringify(obj[k])).join(",") + "}";
}

function sha256Hex(str) {
  return crypto.createHash("sha256").update(str, "utf8").digest("hex");
}

async function audit({ session_id=null, agent_id=null, event_type, payload=null }) {
  try {
    await pg.query(
      "insert into gateway_events(session_id, agent_id, event_type, payload) values ($1,$2,$3,$4)",
      [session_id, agent_id, event_type, payload]
    );
  } catch (e) {
    console.error("audit failed:", e.message || e);
  }
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
  const resp = await axios.post(`${agentUrl.replace(/\/+$/,"")}/invoke`, { session_id, input }, { timeout: 10000 });
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

  try {
    replayTotal.inc({ status: "started" });
    await appendEvent(sid, "replay_started", { override_agent_id: overrideAgent, from_ts_ms: fromTs, max_count: maxCount });
    await audit({ session_id: sid, event_type: "replay_started", payload: { override_agent_id: overrideAgent, from_ts_ms: fromTs, max_count: maxCount } });

    const chronological = (s.events || []).slice().reverse();
    const invokes = chronological
      .filter(e => e.event_type === "invoke_requested" && (e.ts_ms || 0) >= fromTs)
      .slice(0, maxCount);

    const results = [];
    for (const ev of invokes) {
      const agentId = overrideAgent || (ev.payload && ev.payload.agent_id) || null;
      if (!agentId) continue;

      const agentUrl = registry.get(agentId) || DEFAULT_AGENT_URL;
      const input = ev.payload ? ev.payload.input : null;

      await appendEvent(sid, "replay_invoke_requested", { agent_id: agentId, input });
      await audit({ session_id: sid, agent_id: agentId, event_type: "replay_invoke_requested", payload: { input } });

      try {
        const out = await callAgent(agentUrl, sid, input);
        results.push({ agent_id: agentId, ok: true, output: out });
        await appendEvent(sid, "replay_invoke_succeeded", { agent_id: agentId, output: out });
        await audit({ session_id: sid, agent_id: agentId, event_type: "replay_invoke_succeeded", payload: { output: out } });
      } catch (e) {
        results.push({ agent_id: agentId, ok: false, error: e.message || String(e) });
        await appendEvent(sid, "replay_invoke_failed", { agent_id: agentId, error: e.message || String(e) });
        await audit({ session_id: sid, agent_id: agentId, event_type: "replay_invoke_failed", payload: { error: e.message || String(e) } });
      }
    }

    await appendEvent(sid, "replay_completed", { count: results.length });
    await audit({ session_id: sid, event_type: "replay_completed", payload: { count: results.length } });
    replayTotal.inc({ status: "completed" });

    res.json({ ok: true, session_id: sid, results });
  } catch (e) {
    replayTotal.inc({ status: "error" });
    res.status(500).json({ ok: false, error: "replay_failed", detail: e.message || String(e) });
  }
});

app.get("/audit/events", async (req, res) => {
  const limit = Math.min(500, Math.max(1, parseInt(req.query.limit || "200", 10)));
  const r = await pg.query("select id, session_id, agent_id, event_type, payload, created_at from gateway_events order by id desc limit $1", [limit]);
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
    await audit({ session_id: String(session_id), event_type: "channel_send_requested", payload: { channel: "whatsapp", recipient, mode: asyncMode ? "async" : "sync" } });
  }

  if (asyncMode) {
    const qlen = await redis.llen("queue:whatsapp");
    if (qlen >= QUEUE_LIMIT) {
      channelSendTotal.inc({ channel: "whatsapp", mode: "async", status: "rejected" });
      return res.status(429).json({ error: "queue_full", queue_length: qlen, queue_limit: QUEUE_LIMIT });
    }

    const job_id = uuidv4();
    const job = {
      job_id,
      status: "queued",
      created_at_ms: Date.now(),
      updated_at_ms: Date.now(),
      payload: { recipient, content, session_id: session_id || null }
    };

    await redis.setex(jobKey(job_id), JOB_TTL_SEC, JSON.stringify(job));
    await redis.rpush("queue:whatsapp", job_id);

    channelSendTotal.inc({ channel: "whatsapp", mode: "async", status: "queued" });
    return res.status(202).json({ ok: true, mode: "async", job_id, status: "queued" });
  }

  try {
    const resp = await axios.post(
      `${WHATSAPP_ADAPTER_URL.replace(/\/+$/,"")}/send`,
      { recipient, content },
      { timeout: 10000, headers: { Authorization: `Bearer ${ADAPTER_API_KEY}` } }
    );

    channelSendTotal.inc({ channel: "whatsapp", mode: "sync", status: "ok" });

    if (session_id) {
      await appendEvent(String(session_id), "channel_send_succeeded", { channel: "whatsapp", result: resp.data });
      await audit({ session_id: String(session_id), event_type: "channel_send_succeeded", payload: { channel: "whatsapp" } });
    }

    return res.json({ ok: true, mode: "sync", result: resp.data });
  } catch (e) {
    channelSendTotal.inc({ channel: "whatsapp", mode: "sync", status: "error" });

    if (session_id) {
      await appendEvent(String(session_id), "channel_send_failed", { channel: "whatsapp", error: e.message || String(e) });
      await audit({ session_id: String(session_id), event_type: "channel_send_failed", payload: { channel: "whatsapp", error: e.message || String(e) } });
    }

    return res.status(502).json({ error: "adapter_send_failed", detail: e.message || String(e) });
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
        if (cached.hash && cached.hash !== inputHash) {
          return res.status(409).json({ error: "idempotency_conflict", message: "Same idempotency key used with different payload" });
        }
        idemHits.inc();
        return res.json(cached.response);
      } catch {}
    }
  }

  if (session_id) {
    const s = await getSession(session_id);
    if (!s) return res.status(404).json({ error: "session_not_found" });
    await appendEvent(session_id, "invoke_requested", { agent_id: agentId, input });
    await audit({ session_id, agent_id: agentId, event_type: "invoke_requested", payload: { input } });
  } else {
    await audit({ agent_id: agentId, event_type: "invoke_requested", payload: { input } });
  }

  const end = latencyMs.startTimer({ agent_id: agentId });
  try {
    const out = await callAgent(agentUrl, session_id, input);
    invocationsTotal.inc({ agent_id: agentId, status: "ok" });
    end();

    if (session_id) {
      await appendEvent(session_id, "invoke_succeeded", { agent_id: agentId, output: out });
      await audit({ session_id, agent_id: agentId, event_type: "invoke_succeeded", payload: { output: out } });
    }

    const body = { ok: true, agent_id: agentId, session_id, result: out };

    if (idem) {
      await redis.setex(idemKey(agentId, idem), IDEM_TTL_SEC, JSON.stringify({ hash: inputHash, response: body }));
    }

    return res.json(body);
  } catch (e) {
    invocationsTotal.inc({ agent_id: agentId, status: "error" });
    end();

    if (session_id) {
      await appendEvent(session_id, "invoke_failed", { agent_id: agentId, error: e.message || String(e) });
      await audit({ session_id, agent_id: agentId, event_type: "invoke_failed", payload: { error: e.message || String(e) } });
    }

    return res.status(502).json({ error: "agent_invoke_failed", detail: e.message || String(e) });
  }
});

app.listen(PORT, () => console.log(`Gateway listening on ${PORT}`));
'@

# =========================
# WhatsApp Adapter (Node)
# =========================
Write-TextFile $personalos_root "integration/gateway/adapters/whatsapp/package.json" @'
{
  "name": "personalos-whatsapp-adapter",
  "version": "0.5.0",
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

app.get("/health", (req,res)=>res.json({status:"ok"}));
app.get("/metrics", async (req,res)=>{ res.set("Content-Type", client.register.contentType); res.end(await client.register.metrics()); });

app.post("/send", async (req,res)=>{
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
    return res.status(502).json({ error: "provider_error" });
  }
});

app.listen(PORT, ()=>console.log(`WhatsApp adapter listening on ${PORT}`));
'@

# =========================
# Agent (Python)
# =========================
Write-TextFile $personalos_root "integration/agents/runtime/requirements.txt" @'
Flask==2.2.5
requests==2.31.0
prometheus-client==0.20.0
'@

Write-TextFile $personalos_root "integration/agents/runtime/Dockerfile.agent" @'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY agent_main.py .
EXPOSE 8080
CMD ["python","agent_main.py"]
'@

Write-TextFile $personalos_root "integration/agents/runtime/agent_main.py" @'
import os, requests
from flask import Flask, jsonify, request
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)
AGENT_ID = os.getenv("AGENT_ID","example-agent-1")
GATEWAY_URL = os.getenv("GATEWAY_URL","http://gateway:8080").rstrip("/")
SELF_URL = os.getenv("SELF_URL","http://agent:8080")

invocations = Counter("agent_invocations_total","Total invocations", ["agent_id","status"])

@app.get("/health")
def health():
    return jsonify({"status":"ok","agent_id":AGENT_ID})

@app.get("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}

@app.post("/invoke")
def invoke():
    payload = request.json or {}
    invocations.labels(agent_id=AGENT_ID, status="ok").inc()
    return jsonify({"agent_id":AGENT_ID,"result":"ok","input":payload})

def register():
    try:
        requests.post(f"{GATEWAY_URL}/agents/register", json={"agent_id": AGENT_ID, "url": SELF_URL}, timeout=2)
    except Exception:
        pass

if __name__ == "__main__":
    register()
    app.run(host="0.0.0.0", port=int(os.getenv("PORT","8080")))
'@

# =========================
# WhatsApp Worker (Node)
# =========================
Write-TextFile $personalos_root "integration/workers/whatsapp-worker/package.json" @'
{
  "name": "personalos-whatsapp-worker",
  "version": "0.1.0",
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

client.collectDefaultMetrics();
const jobsTotal = new client.Counter({ name: "worker_jobs_total", help: "Jobs processed", labelNames: ["status"] });
const jobDuration = new client.Histogram({ name: "worker_job_duration_ms", help: "Job duration ms", buckets: [10,25,50,100,250,500,1000,2000,5000] });

function jobKey(id){ return `job:${id}`; }

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
    const payload = job.payload || {};
    const recipient = payload.recipient;
    const content = payload.content;

    const resp = await axios.post(
      `${ADAPTER_URL.replace(/\/+$/,"")}/send`,
      { recipient, content },
      { timeout: 10000, headers: { Authorization: `Bearer ${API_KEY}` } }
    );

    await updateJob(jobId, { status: "done", result: resp.data });
    jobsTotal.inc({ status: "done" });
    end();
  } catch (e) {
    await updateJob(jobId, { status: "failed", error: e.message || String(e) });
    jobsTotal.inc({ status: "failed" });
    end();
  }
}

async function loop() {
  for (;;) {
    try {
      const r = await redis.brpop("queue:whatsapp", 5);
      if (!r) continue;
      const jobId = r[1];
      await processJob(jobId);
    } catch (e) {
      await new Promise(res => setTimeout(res, 500));
    }
  }
}

const app = express();
app.get("/health", (req, res) => res.json({ status: "ok" }));
app.get("/metrics", async (req, res) => {
  res.set("Content-Type", client.register.contentType);
  res.end(await client.register.metrics());
});

app.listen(PORT, () => console.log(`WhatsApp worker metrics listening on ${PORT}`));
loop();
'@

# =========================
# Compose
# =========================
$compose = @'
name: personalos

services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: personalos
      POSTGRES_PASSWORD: personalos
      POSTGRES_DB: personalos
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 20s

  redis:
    image: redis:7-alpine
    command: ["redis-server","--save","60","1"]
    volumes:
      - redisdata:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 15
      start_period: 10s

  migrate:
    image: postgres:16-alpine
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - ./migration/db-migrations:/migrations:ro
    entrypoint: ["/bin/sh","-lc"]
    command: >
      "psql postgresql://personalos:personalos@postgres:5432/personalos -f /migrations/001_init.sql;
       echo migrations applied"

  gateway:
    build:
      context: ./integration/gateway/service
      dockerfile: Dockerfile
    env_file: ./.env
    environment:
      PORT: "8080"
      DEFAULT_AGENT_URL: "http://agent:8080"
      REDIS_URL: "redis://redis:6379"
      DATABASE_URL: "postgres://personalos:personalos@postgres:5432/personalos"
    ports:
      - "8080:8080"
    depends_on:
      migrate:
        condition: service_completed_successfully
      redis:
        condition: service_healthy
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 10s

  agent:
    build:
      context: ./integration/agents/runtime
      dockerfile: Dockerfile.agent
    env_file: ./.env
    environment:
      PORT: "8080"
      SELF_URL: "http://agent:8080"
      GATEWAY_URL: "http://gateway:8080"
    ports:
      - "8081:8080"
    depends_on:
      gateway:
        condition: service_healthy

  whatsapp-adapter:
    build:
      context: ./integration/gateway/adapters/whatsapp
      dockerfile: Dockerfile
    env_file: ./.env
    environment:
      PORT: "3000"
    ports:
      - "3000:3000"
    depends_on:
      gateway:
        condition: service_healthy

  whatsapp-worker:
    build:
      context: ./integration/workers/whatsapp-worker
      dockerfile: Dockerfile
    env_file: ./.env
    environment:
      PORT: "9101"
      REDIS_URL: "redis://redis:6379"
      WHATSAPP_ADAPTER_URL: "http://whatsapp-adapter:3000"
    depends_on:
      redis:
        condition: service_healthy
      whatsapp-adapter:
        condition: service_started
    ports:
      - "9101:9101"
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:9101/health"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 10s

  prometheus:
    image: prom/prometheus:v2.54.1
    volumes:
      - ./observability/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:10.4.2
    env_file: ./.env
    environment:
      GF_SECURITY_ADMIN_PASSWORD: "${GRAFANA_ADMIN_PASSWORD:-admin}"
    volumes:
      - ./observability/grafana/provisioning:/etc/grafana/provisioning:ro
      - ./observability/grafana/dashboards:/var/lib/grafana/dashboards:ro
    ports:
      - "3001:3000"

volumes:
  pgdata:
  redisdata:
'@

Write-TextFile $personalos_root "compose.yaml" $compose
Write-TextFile $personalos_root "docker-compose.yml" $compose

# ---------- Smoke tests ----------
Write-TextFile $personalos_root "smoke_tests.ps1" @'
$ErrorActionPreference = "Stop"

$token = "devtoken"
$auth  = @{ Authorization = "Bearer $token" }

Write-Host "[SMOKE] Gateway health (no auth)"
Invoke-RestMethod -Uri http://localhost:8080/health -TimeoutSec 12 | Out-Null

Write-Host "[SMOKE] Create session (auth)"
$sid = (Invoke-RestMethod -Method Post -Uri http://localhost:8080/sessions/start -Headers $auth -ContentType "application/json" -Body "{""meta"":{""user"":""AKIN""}}" -TimeoutSec 12).session.session_id
Write-Host ("SID=" + $sid)

Write-Host "[SMOKE] Invoke (idempotency first)"
$headers = @{ "Authorization"="Bearer $token"; "X-Idempotency-Key"="k-1" }
Invoke-RestMethod -Method Post -Uri http://localhost:8080/invoke/example-agent-1 -Headers $headers -ContentType "application/json" -Body ("{""session_id"":"""+$sid+""",""input"":{""hello"":""world""}}") -TimeoutSec 15 | Out-Null

Write-Host "[SMOKE] Invoke (idempotency cached)"
Invoke-RestMethod -Method Post -Uri http://localhost:8080/invoke/example-agent-1 -Headers $headers -ContentType "application/json" -Body ("{""session_id"":"""+$sid+""",""input"":{""hello"":""world""}}") -TimeoutSec 15 | Out-Null

Write-Host "[SMOKE] Invoke (idempotency conflict => expect 409)"
try {
  Invoke-RestMethod -Method Post -Uri http://localhost:8080/invoke/example-agent-1 -Headers $headers -ContentType "application/json" -Body ("{""session_id"":"""+$sid+""",""input"":{""hello"":""DIFFERENT""}}") -TimeoutSec 15 | Out-Null
  throw "Expected 409 but got success"
} catch {
  if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 409) {
    Write-Host "OK: conflict 409"
  } else {
    throw
  }
}

Write-Host "[SMOKE] Async queue send (auth) => job"
$job = Invoke-RestMethod -Method Post -Uri "http://localhost:8080/channels/whatsapp/send?mode=async" -Headers $auth -ContentType "application/json" -Body ("{""session_id"":"""+$sid+""",""recipient"":""+905555555555"",""content"":{""text"":""test-async""}}") -TimeoutSec 15
$jobId = $job.job_id
Write-Host ("JOB=" + $jobId)

Write-Host "[SMOKE] Poll job status"
for ($i=0; $i -lt 15; $i++) {
  $j = Invoke-RestMethod -Uri ("http://localhost:8080/jobs/" + $jobId) -Headers $auth -TimeoutSec 10
  if ($j.job.status -eq "done") { Write-Host "Job done"; break }
  if ($j.job.status -eq "failed") { throw ("Job failed: " + ($j.job.error | Out-String)) }
  Start-Sleep -Seconds 1
}

Write-Host "[SMOKE] Replay (filters)"
Invoke-RestMethod -Method Post -Uri ("http://localhost:8080/sessions/"+$sid+"/replay") -Headers $auth -ContentType "application/json" -Body ("{""from_ts_ms"":0,""max_count"":10}") -TimeoutSec 30 | Out-Null

Write-Host "[SMOKE] Audit"
Invoke-RestMethod -Uri "http://localhost:8080/audit/events?limit=20" -Headers $auth -TimeoutSec 12 | Out-Null

Write-Host "[SMOKE] OK"
'@

# ---------- Start docker compose ----------
Write-Log "Docker kontrolü..."
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Warning "Docker bulunamadı. Docker Desktop kurun ve tekrar çalıştırın."
  Write-Host "https://docs.docker.com/desktop/"
  exit 0
}

Write-Log "Docker Compose ile başlatılıyor..."
Push-Location $personalos_root
try {
  docker compose -f compose.yaml up --build -d
  Write-Log "Servisler başlatıldı. 18s bekleniyor..."
  Start-Sleep -Seconds 18
  Write-Log "Smoke testleri çalıştırılıyor..."
  powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $personalos_root "smoke_tests.ps1")
}
catch {
  Write-Warning ("docker compose/smoke tests hata: " + $_.Exception.Message)
  Write-Host "Tam terminal çıktısını buraya yapıştır; tek seferde patch veririm."
}
finally {
  Pop-Location
}

Write-Log "Tamamlandı."
Write-Log "BuildKit bin: $target_bin"
Write-Log "PersonalOS: $personalos_root"
Write-Host "Endpoints:"
Write-Host "  Gateway    -> http://localhost:8080 (auth: Bearer devtoken)"
Write-Host "  Agent      -> http://localhost:8081"
Write-Host "  Adapter    -> http://localhost:3000"
Write-Host "  Worker     -> http://localhost:9101/metrics"
Write-Host "  Prometheus -> http://localhost:9090"
Write-Host "  Grafana    -> http://localhost:3001 (admin/admin)"
