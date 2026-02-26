const express = require("express");
const axios = require("axios");
const crypto = require("crypto");

const app = express();
app.use(express.json());

const PORT = parseInt(process.env.PORT || "3002", 10);
const GATEWAY_URL = (process.env.GATEWAY_URL || "http://gateway:8080").replace(/\/+$/, "");
const DISPATCHER_URL = (process.env.DISPATCHER_URL || "http://dispatcher:9400").replace(/\/+$/, "");
const API_KEY = process.env.ADAPTER_API_KEY || "changeme";
const SIGNING_SECRET = process.env.SIGNING_SECRET || "changeme";

function verifySignature(req, res, next) {
    const sig = req.headers["x-telegram-signature"] || "";
    const data = JSON.stringify(req.body);
    const expected = crypto.createHmac("sha256", SIGNING_SECRET).update(data).digest("hex");
    if (sig && sig !== expected) {
        console.warn("Invalid signature");
    }
    next();
}

function requireAuth(req, res, next) {
    const h = (req.headers["authorization"] || "").toString().trim();
    if (h !== `Bearer ${API_KEY}`) {
        return res.status(401).json({ error: "unauthorized" });
    }
    next();
}

app.get("/health", (req, res) => res.json({ status: "ok" }));

app.post("/webhook", async (req, res) => {
    const { message } = req.body || {};
    if (!message || !message.from || !message.text) {
        return res.json({ ok: true });
    }

    const from = String(message.from.id);
    const text = message.text;

    console.log(`[Telegram Adapter] From ${from}: ${text}`);

    try {
        const resp = await axios.post(`${DISPATCHER_URL}/dispatch`, {
            channel: "telegram",
            from,
            text,
            raw: message
        }, { timeout: 15000 });
        console.log("[Telegram Adapter] Dispatch result:", resp.data);
    } catch (e) {
        console.error("[Telegram Adapter] Dispatch error:", e.message);
    }

    res.json({ ok: true });
});

app.post("/send", requireAuth, async (req, res) => {
    const { recipient, content } = req.body || {};
    if (!recipient || !content) {
        return res.status(400).json({ error: "invalid_payload" });
    }

    console.log(`[Telegram Adapter] Send to ${recipient}: ${content}`);

    res.json({ ok: true, channel: "telegram", recipient, content });
});

app.listen(PORT, () => console.log(`Telegram adapter listening on ${PORT}`));
