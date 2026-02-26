const Redis = require("ioredis");
const axios = require("axios");

const CHANNEL = process.env.CHANNEL || "whatsapp";
const PORT = parseInt(process.env.PORT || "9101", 10);
const REDIS_URL = process.env.REDIS_URL || "redis://redis:6379";
const ADAPTER_URL = (process.env.ADAPTER_URL || "http://whatsapp-adapter:3000").replace(/\/+$/, "");
const ADAPTER_API_KEY = process.env.ADAPTER_API_KEY || "changeme";
const QUEUE_MAIN = process.env.QUEUE_MAIN || `queue:${CHANNEL}`;
const QUEUE_DELAYED = process.env.QUEUE_DELAYED || `queue:${CHANNEL}:delayed`;
const QUEUE_DLQ = process.env.QUEUE_DLQ || `queue:${CHANNEL}:dlq`;

const MAX_RETRIES = 3;
const RETRY_DELAY_MS = 5000;

const redis = new Redis(REDIS_URL, { maxRetriesPerRequest: null });
const processing = new Set();

async function processJob(jobId) {
    const key = `job:${jobId}`;
    const raw = await redis.get(key);
    if (!raw) {
        console.log(`[${CHANNEL}] Job ${jobId} not found, skipping`);
        return;
    }

    let job;
    try {
        job = JSON.parse(raw);
    } catch (e) {
        console.error(`[${CHANNEL}] Job ${jobId} parse error:`, e.message);
        return;
    }

    if (processing.has(jobId)) {
        console.log(`[${CHANNEL}] Job ${jobId} already processing, skipping`);
        return;
    }

    processing.add(jobId);
    job.status = "processing";
    job.updated_at_ms = Date.now();
    await redis.set(key, JSON.stringify(job));

    console.log(`[${CHANNEL}] Processing job ${jobId}:`, job.payload);

    try {
        const resp = await axios.post(`${ADAPTER_URL}/send`, job.payload, {
            timeout: 10000,
            headers: { Authorization: `Bearer ${ADAPTER_API_KEY}` }
        });

        job.status = "done";
        job.updated_at_ms = Date.now();
        job.result = resp.data;
        await redis.set(key, JSON.stringify(job));

        console.log(`[${CHANNEL}] Job ${jobId} done`);
    } catch (e) {
        console.error(`[${CHANNEL}] Job ${jobId} failed:`, e.message);

        job.attempts = (job.attempts || 0) + 1;
        job.last_error = e.message;
        job.updated_at_ms = Date.now();

        if (job.attempts < MAX_RETRIES) {
            job.status = "retry_scheduled";
            await redis.set(key, JSON.stringify(job));
            await redis.zadd(QUEUE_DELAYED, Date.now() + RETRY_DELAY_MS, jobId);
            console.log(`[${CHANNEL}] Job ${jobId} scheduled for retry (attempt ${job.attempts})`);
        } else {
            job.status = "dlq";
            await redis.set(key, JSON.stringify(job));
            await redis.rpush(QUEUE_DLQ, jobId);
            console.log(`[${CHANNEL}] Job ${jobId} moved to DLQ`);
        }
    } finally {
        processing.delete(jobId);
    }
}

async function loop() {
    console.log(`[${CHANNEL}] Worker started, main queue: ${QUEUE_MAIN}`);

    while (true) {
        try {
            const now = Date.now();

            const delayedJobs = await redis.zrangebyscore(QUEUE_DELAYED, 0, now);
            for (const jobId of delayedJobs) {
                await redis.zrem(QUEUE_DELAYED, jobId);
                await redis.rpush(QUEUE_MAIN, jobId);
            }

            const jobId = await redis.lpop(QUEUE_MAIN);
            if (jobId) {
                await processJob(jobId);
            } else {
                await new Promise(r => setTimeout(r, 500));
            }
        } catch (e) {
            console.error(`[${CHANNEL}] Loop error:`, e.message);
            await new Promise(r => setTimeout(r, 1000));
        }
    }
}

loop();
