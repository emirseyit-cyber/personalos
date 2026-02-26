const fs = require("fs");
const path = require("path");
const express = require("express");
const Redis = require("ioredis");
const axios = require("axios");

const PORT = parseInt(process.env.PORT || "9400", 10);
const REDIS_URL = process.env.REDIS_URL || "redis://redis:6379";
const GATEWAY_URL = (process.env.GATEWAY_URL || "http://gateway:8080").replace(/\/+$/, "");
const CONFIG_DIR = process.env.CONFIG_DIR || "/app/config";
const WORKFLOWS_FILE = path.join(CONFIG_DIR, "workflows.json");
const CHANNELS_FILE = path.join(CONFIG_DIR, "channels.json");

const app = express();
app.use(express.json({ limit: "2mb" }));

const redis = new Redis(REDIS_URL, { maxRetriesPerRequest: 2, retryStrategy: (t) => Math.min(t * 2, 2000) });

let channels = { whatsapp: {}, telegram: {}, email: {} };
let workflows = [];

function loadConfig() {
    try {
        if (fs.existsSync(CHANNELS_FILE)) {
            channels = JSON.parse(fs.readFileSync(CHANNELS_FILE, "utf8"));
        }
    } catch (e) { console.error("Error loading channels:", e.message); }
    try {
        if (fs.existsSync(WORKFLOWS_FILE)) {
            workflows = JSON.parse(fs.readFileSync(WORKFLOWS_FILE, "utf8"));
        }
    } catch (e) { console.error("Error loading workflows:", e.message); }
}

loadConfig();

app.get("/health", (req, res) => res.json({ status: "ok" }));

app.post("/reload", async (req, res) => {
    loadConfig();
    res.json({ ok: true, channels: Object.keys(channels), workflows_count: workflows.length });
});

app.get("/channels", (req, res) => res.json({ ok: true, channels }));

app.get("/workflows", (req, res) => res.json({ ok: true, workflows }));

async function invokeAgent(sessionId, input) {
    try {
        const resp = await axios.post(`${GATEWAY_URL}/invoke/example-agent-1`, {
            session_id: sessionId,
            input
        }, { timeout: 30000 });
        return resp.data;
    } catch (e) {
        console.error("Agent invoke error:", e.message);
        return { error: e.message };
    }
}

async function enqueueReply(sessionId, reply) {
    const jobId = require("uuid").v4();
    const job = {
        job_id: jobId,
        status: "queued",
        created_at_ms: Date.now(),
        channel: reply.channel || "whatsapp",
        payload: { recipient: reply.recipient, content: reply.content, session_id: sessionId }
    };
    const key = `job:${jobId}`;
    await redis.setex(key, 3600, JSON.stringify(job));
    const queue = `queue:${reply.channel || "whatsapp"}`;
    await redis.rpush(queue, jobId);
    return jobId;
}

app.post("/dispatch", async (req, res) => {
    const { channel, from, text, session_id, raw } = req.body || {};
    if (!channel || !from || !text) {
        return res.status(400).json({ error: "missing_channel_or_from_or_text" });
    }

    const sid = session_id || `session:${channel}:${from}:${Date.now()}`;
    console.log(`[Dispatcher] ${channel} from ${from}: ${text.substring(0, 50)}`);

    let matchedWorkflow = null;
    for (const wf of workflows) {
        if (wf.channel === channel && wf.trigger && text.toLowerCase().includes(wf.trigger.toLowerCase())) {
            matchedWorkflow = wf;
            break;
        }
    }

    const agentInput = { channel, from, text, session_id: sid, raw };
    const agentResult = await invokeAgent(sid, agentInput);

    let reply = null;
    if (matchedWorkflow && matchedWorkflow.reply) {
        reply = { channel, recipient: from, content: matchedWorkflow.reply };
    } else if (agentResult && agentResult.result && agentResult.result.reply) {
        reply = { channel, recipient: from, content: agentResult.result.reply };
    }

    if (reply) {
        const jobId = await enqueueReply(sid, reply);
        res.json({ ok: true, session_id: sid, workflow: matchedWorkflow ? matchedWorkflow.name : null, reply_job_id: jobId });
    } else {
        res.json({ ok: true, session_id: sid, workflow: matchedWorkflow ? matchedWorkflow.name : null, agent_result: agentResult });
    }
});

app.listen(PORT, () => console.log(`Dispatcher listening on ${PORT}`));
