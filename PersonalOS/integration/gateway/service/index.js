const express = require("express");
const bodyParser = require("body-parser");
const axios = require("axios");
const client = require("prom-client");
const Redis = require("ioredis");
const { Pool } = require("pg");
const { v4: uuidv4 } = require("uuid");
const crypto = require("crypto");
const rateLimit = require("express-rate-limit");
const winston = require("winston");
const path = require("path");

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
const QUEUE_LIMIT = parseInt(process.env.QUEUE_LIMIT || "1000", 10);
const JOB_TTL_SEC = parseInt(process.env.JOB_TTL_SEC || "3600", 10);

const logger = winston.createLogger({
    level: "info",
    format: winston.format.combine(winston.format.timestamp(), winston.format.json()),
    transports: [new winston.transports.Console()]
});

const registry = new Map();
const redis = new Redis(REDIS_URL, { maxRetriesPerRequest: 2, retryStrategy: (t) => Math.min(t * 2, 2000) });
const pg = new Pool({ connectionString: DATABASE_URL, max: 10 });

client.collectDefaultMetrics();
const invocationsTotal = new client.Counter({ name: "gateway_invocations_total", help: "Total invocations", labelNames: ["agent_id", "status"] });
const latencyMs = new client.Histogram({ name: "gateway_invoke_latency_ms", help: "Invoke latency (ms)", labelNames: ["agent_id"], buckets: [5, 10, 25, 50, 100, 250, 500, 1000, 2000, 5000] });
const idemHits = new client.Counter({ name: "gateway_idempotency_hits_total", help: "Idempotency cache hits" });
const channelSendTotal = new client.Counter({ name: "gateway_channel_send_total", help: "Channel sends", labelNames: ["channel", "mode", "status"] });
const rateLimitHits = new client.Counter({ name: "gateway_rate_limit_hits_total", help: "Rate limit hits", labelNames: ["endpoint"] });

const analyticsKey = (session_id) => `analytics:${session_id}`;

const generalLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: 100,
    standardHeaders: true,
    legacyHeaders: false,
    handler: (req, res) => {
        rateLimitHits.inc({ endpoint: "general" });
        logger.warn("Rate limit hit", { ip: req.ip, path: req.path });
        res.status(429).json({ error: "rate_limit_exceeded", retry_after: 60 });
    }
});

const invokeLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: 30,
    standardHeaders: true,
    legacyHeaders: false,
    handler: (req, res) => {
        rateLimitHits.inc({ endpoint: "invoke" });
        logger.warn("Rate limit hit on invoke", { ip: req.ip, agent_id: req.params.agent_id });
        res.status(429).json({ error: "rate_limit_exceeded", retry_after: 60 });
    }
});

const webhookLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: 20,
    standardHeaders: true,
    legacyHeaders: false,
    handler: (req, res) => {
        rateLimitHits.inc({ endpoint: "webhook" });
        res.status(429).json({ error: "rate_limit_exceeded", retry_after: 60 });
    }
});

app.use(generalLimiter);

async function trackAnalytics(session_id, event_type, data) {
    if (!session_id) return;
    const key = analyticsKey(session_id);
    const existing = await redis.hgetall(key) || {};
    existing[event_type] = (parseInt(existing[event_type]) || 0) + 1;
    existing.last_updated = Date.now().toString();
    await redis.hset(key, existing);
    await redis.expire(key, 86400 * 30);
}

async function getAnalytics(session_id) {
    const data = await redis.hgetall(analyticsKey(session_id));
    return data || {};
}

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
    res.json({ ok: true, agent_id, url: agentUrl });
});

app.post("/sessions/start", async (req, res) => {
    const meta = (req.body && req.body.meta) ? req.body.meta : {};
    const session_id = uuidv4();
    const now = Date.now();
    const session = { session_id, status: "open", created_at_ms: now, updated_at_ms: now, meta };
    await redis.set(sKey(session_id), JSON.stringify(session));
    await redis.del(eKey(session_id));
    await appendEvent(session_id, "session_started", { meta });
    res.json({ ok: true, session });
});

app.get("/sessions/:session_id", async (req, res) => {
    const s = await getSession(req.params.session_id);
    if (!s) return res.status(404).json({ error: "session_not_found" });
    res.json({ ok: true, session: s });
});

app.get("/jobs/list", async (req, res) => {
    const channel = req.query.channel || "whatsapp";
    const status = req.query.status || "queued";
    const limit = parseInt(req.query.limit || "50", 10);
    const cursor = req.query.cursor || "";

    let jobIds = [];
    if (status === "queued") {
        jobIds = await redis.lrange(`queue:${channel}`, 0, limit - 1);
    } else if (status === "dlq") {
        jobIds = await redis.lrange(`queue:${channel}:dlq`, 0, limit - 1);
    } else {
        const pattern = `job:${channel}:*`;
        const keys = await redis.keys(pattern);
        const jobs = [];
        for (const key of keys.slice(0, 100)) {
            const raw = await redis.get(key);
            if (raw) {
                try {
                    const job = JSON.parse(raw);
                    if (job.status === status) jobs.push(job);
                } catch { }
            }
        }
        jobIds = jobs.slice(0, limit).map(j => j.job_id);
    }

    const jobs = [];
    for (const jobId of jobIds) {
        const raw = await redis.get(`job:${jobId}`);
        if (raw) {
            try {
                jobs.push(JSON.parse(raw));
            } catch { }
        }
    }

    res.json({ ok: true, jobs, count: jobs.length, next_cursor: jobs.length === limit ? "more" : "" });
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

app.post("/invoke/:agent_id", invokeLimiter, async (req, res) => {
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
        await trackAnalytics(session_id, "invocations", 1);
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

app.post("/webhook/:webhook_id", webhookLimiter, async (req, res) => {
    const webhookId = req.params.webhook_id;
    const { session_id, event, data } = req.body || {};

    logger.info("Webhook received", { webhook_id: webhookId, event, session_id });

    if (session_id) {
        const s = await getSession(session_id);
        if (!s) return res.status(404).json({ error: "session_not_found" });
        await appendEvent(session_id, "webhook_received", { webhook_id: webhookId, event, data });
        await trackAnalytics(session_id, "webhooks_received", 1);
    }

    await redis.lpush(`webhook:${webhookId}:events`, JSON.stringify({
        received_at: Date.now(),
        event,
        data,
        session_id
    }));
    await redis.ltrim(`webhook:${webhookId}:events`, 0, 99);

    res.json({ ok: true, webhook_id: webhookId, received: true });
});

app.get("/webhook/:webhook_id/events", async (req, res) => {
    const events = await redis.lrange(`webhook:${req.params.webhook_id}:events`, 0, 49);
    res.json({ ok: true, events: events.map(e => JSON.parse(e)) });
});

app.get("/analytics/:session_id", async (req, res) => {
    const analytics = await getAnalytics(req.params.session_id);
    res.json({ ok: true, session_id: req.params.session_id, analytics });
});

app.post("/analytics/track", async (req, res) => {
    const { session_id, event, data } = req.body || {};
    if (!session_id || !event) return res.status(400).json({ error: "missing_session_id_or_event" });

    await trackAnalytics(session_id, event, data);
    logger.info("Analytics event tracked", { session_id, event });
    res.json({ ok: true, session_id, event });
});

app.get("/queues/status", async (req, res) => {
    const channels = ["whatsapp", "telegram", "email"];
    const status = {};
    for (const ch of channels) {
        status[ch] = {
            main: await redis.llen(`queue:${ch}`),
            delayed: await redis.zcard(`queue:${ch}:delayed`),
            dlq: await redis.llen(`queue:${ch}:dlq`)
        };
    }
    res.json({ ok: true, queues: status });
});

app.post("/jobs/purge-by-status", async (req, res) => {
    const { channel, status, older_than_ms, limit, delete_jobs } = req.body || {};
    if (!channel || !status) return res.status(400).json({ error: "missing_channel_or_status" });

    const olderThan = older_than_ms ? Date.now() - older_than_ms : 0;
    const maxLimit = Math.min(limit || 200, 500);
    let purged = 0;

    if (status === "queued") {
        const jobIds = await redis.lrange(`queue:${channel}`, 0, maxLimit - 1);
        for (const jobId of jobIds) {
            const raw = await redis.get(`job:${jobId}`);
            if (raw) {
                try {
                    const job = JSON.parse(raw);
                    if (job.created_at_ms < olderThan || olderThan === 0) {
                        await redis.lrem(`queue:${channel}`, 1, jobId);
                        if (delete_jobs) await redis.del(`job:${jobId}`);
                        purged++;
                    }
                } catch { }
            }
        }
    } else if (status === "dlq") {
        const jobIds = await redis.lrange(`queue:${channel}:dlq`, 0, maxLimit - 1);
        for (const jobId of jobIds) {
            await redis.lrem(`queue:${channel}:dlq`, 1, jobId);
            if (delete_jobs) await redis.del(`job:${jobId}`);
            purged++;
        }
    }

    res.json({ ok: true, purged });
});

app.get("/dlq/:channel", async (req, res) => {
    const channel = req.params.channel;
    const limit = parseInt(req.query.limit || "50", 10);
    const jobIds = await redis.lrange(`queue:${channel}:dlq`, 0, limit - 1);
    const jobs = [];
    for (const jobId of jobIds) {
        const raw = await redis.get(`job:${jobId}`);
        if (raw) {
            try {
                jobs.push(JSON.parse(raw));
            } catch { }
        }
    }
    res.json({ ok: true, dlq: jobs, count: jobs.length });
});

app.post("/dlq/:channel/retry-bulk", async (req, res) => {
    const channel = req.params.channel;
    const { limit, reset_attempts } = req.body || {};
    const maxLimit = Math.min(limit || 25, 100);
    const jobIds = await redis.lrange(`queue:${channel}:dlq`, 0, maxLimit - 1);
    let retried = 0;

    for (const jobId of jobIds) {
        await redis.lrem(`queue:${channel}:dlq`, 1, jobId);
        const raw = await redis.get(`job:${jobId}`);
        if (raw) {
            try {
                const job = JSON.parse(raw);
                if (reset_attempts) job.attempts = 0;
                job.status = "queued";
                job.updated_at_ms = Date.now();
                await redis.set(`job:${jobId}`, JSON.stringify(job));
                await redis.rpush(`queue:${channel}`, jobId);
                retried++;
            } catch { }
        }
    }

    res.json({ ok: true, retried });
});

app.listen(PORT, () => console.log(`Gateway listening on ${PORT}`));

// ===================== OMEGA ENDPOINTS =====================

const { spawn } = require("child_process");

const OMEGA_PYTHON = process.env.OMEGA_PYTHON || "python3";
const OMEGA_SCRIPT = process.env.OMEGA_SCRIPT || "/app/omega/omega.py";
const OMEGA_DATA = process.env.OMEGA_DATA || "/data/omega";

function omegaSpawn(args) {
    return spawn(OMEGA_PYTHON, [OMEGA_SCRIPT, ...args], { 
        shell: true,
        env: { ...process.env, OMEGA_DATA }
    });
}

app.get("/omega/status", async (req, res) => {
    try {
        const result = omegaSpawn(["DUR"]);
        let output = "";
        
        result.stdout.on("data", (data) => { output += data.toString() });
        result.stderr.on("data", (data) => { output += data.toString() });
        
        result.on("close", (code) => {
            res.json({ ok: true, output: output.trim(), code });
        });
        
        result.on("error", (err) => {
            res.status(500).json({ ok: false, error: err.message });
        });
        
        setTimeout(() => {
            if (!output) {
                res.json({ ok: true, output: "OMEGA çalışıyor", code: 0 });
            }
        }, 5000);
        
    } catch (error) {
        res.status(500).json({ ok: false, error: error.message });
    }
});

app.post("/omega/execute", async (req, res) => {
    const { command } = req.body || {};
    
    if (!command) {
        return res.status(400).json({ ok: false, error: "command required" });
    }
    
    try {
        const result = omegaSpawn([command]);
        let output = "";
        
        result.stdout.on("data", (data) => { output += data.toString() });
        result.stderr.on("data", (data) => { output += data.toString() });
        
        result.on("close", (code) => {
            res.json({ ok: true, output: output.trim(), code });
        });
        
        result.on("error", (err) => {
            res.status(500).json({ ok: false, error: err.message });
        });
        
    } catch (error) {
        res.status(500).json({ ok: false, error: error.message });
    }
});

app.get("/omega/summary", async (req, res) => {
    try {
        const result = omegaSpawn(["O"]);
        let output = "";
        
        result.stdout.on("data", (data) => { output += data.toString() });
        
        result.on("close", (code) => {
            let data;
            try {
                data = JSON.parse(output.trim());
            } catch {
                data = { raw: output.trim() };
            }
            res.json({ ok: true, data, code });
        });
        
    } catch (error) {
        res.status(500).json({ ok: false, error: error.message });
    }
});

app.get("/omega/logs", async (req, res) => {
    try {
        const result = omegaSpawn(["L"]);
        let output = "";
        
        result.stdout.on("data", (data) => { output += data.toString() });
        
        result.on("close", (code) => {
            res.json({ ok: true, logs: output.trim(), code });
        });
        
    } catch (error) {
        res.status(500).json({ ok: false, error: error.message });
    }
});

app.post("/omega/clear", async (req, res) => {
    try {
        const result = omegaSpawn(["TEMIZLE"]);
        let output = "";
        
        result.stdout.on("data", (data) => { output += data.toString() });
        
        result.on("close", (code) => {
            res.json({ ok: true, output: output.trim(), code });
        });
        
    } catch (error) {
        res.status(500).json({ ok: false, error: error.message });
    }
});

app.get("/omega/health", async (req, res) => {
    try {
        const fs = require("fs");
        if (!fs.existsSync(OMEGA_SCRIPT)) {
            return res.json({ ok: false, status: "not_found", script: OMEGA_SCRIPT });
        }
        res.json({ ok: true, status: "ready", script: OMEGA_SCRIPT });
    } catch (error) {
        res.status(500).json({ ok: false, error: error.message });
    }
});

// ===================== SİSTEM ENDPOINTS =====================

app.get("/api/system", async (req, res) => {
    try {
        // Docker stats
        const { execSync } = require("child_process");
        let containers = 0;
        try {
            const out = execSync("docker ps --format '{{.Names}}' | wc -l", { encoding: "utf-8" });
            containers = parseInt(out.trim()) || 0;
        } catch {}
        
        res.json({
            ok: true,
            system: {
                containers,
                nodejs: process.version,
                platform: process.platform,
                uptime: process.uptime(),
                memory: process.memoryUsage(),
                cpu: process.cpuUsage()
            },
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ ok: false, error: error.message });
    }
});

app.get("/api/metrics", async (req, res) => {
    try {
        res.set("Content-Type", client.register.contentType);
        res.end(client.register.metrics());
    } catch (error) {
        res.status(500).json({ ok: false, error: error.message });
    }
});

app.get("/api/redis/keys", async (req, res) => {
    try {
        const pattern = req.query.pattern || "*";
        const keys = await redis.keys(pattern);
        const limited = keys.slice(0, 100);
        const data = {};
        for (const key of limited) {
            const type = await redis.type(key);
            if (type === "string") {
                data[key] = await redis.get(key);
            } else if (type === "hash") {
                data[key] = await redis.hgetall(key);
            } else if (type === "list") {
                data[key] = await redis.lrange(key, 0, 10);
            } else {
                data[key] = `[${type}]`;
            }
        }
        res.json({ ok: true, keys: keys.length, data });
    } catch (error) {
        res.status(500).json({ ok: false, error: error.message });
    }
});

app.post("/api/redis/flush", async (req, res) => {
    try {
        await redis.flushdb();
        res.json({ ok: true, message: "Redis flushed" });
    } catch (error) {
        res.status(500).json({ ok: false, error: error.message });
    }
});

app.get("/api/config", async (req, res) => {
    res.json({
        ok: true,
        config: {
            port: PORT,
            gateway_url: DEFAULT_AGENT_URL,
            redis_url: REDIS_URL,
            admin_token_set: !!ADMIN_TOKEN,
            whatsapp_adapter: WHATSAPP_ADAPTER_URL,
            idempotency_ttl: IDEM_TTL_SEC,
            queue_limit: QUEUE_LIMIT,
            job_ttl: JOB_TTL_SEC
        }
    });
});
