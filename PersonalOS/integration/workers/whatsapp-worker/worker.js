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
