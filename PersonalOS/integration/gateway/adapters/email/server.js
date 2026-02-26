const express = require("express");
const axios = require("axios");

const app = express();
app.use(express.json({ limit: "2mb" }));

const PORT = parseInt(process.env.PORT || "3003", 10);
const GATEWAY_URL = (process.env.GATEWAY_URL || "http://gateway:8080").replace(/\/+$/, "");
const DISPATCHER_URL = (process.env.DISPATCHER_URL || "http://dispatcher:9400").replace(/\/+$/, "");
const API_KEY = process.env.ADAPTER_API_KEY || "changeme";

function requireAuth(req, res, next) {
    const h = (req.headers["authorization"] || "").toString().trim();
    if (h !== `Bearer ${API_KEY}`) {
        return res.status(401).json({ error: "unauthorized" });
    }
    next();
}

app.get("/health", (req, res) => res.json({ status: "ok" }));

app.post("/webhook", async (req, res) => {
    const { from, subject, text } = req.body || {};
    if (!from) {
        return res.json({ ok: true });
    }

    const content = subject ? `${subject}\n${text || ""}` : (text || "");

    console.log(`[Email Adapter] From ${from}: ${content.substring(0, 50)}`);

    try {
        const resp = await axios.post(`${DISPATCHER_URL}/dispatch`, {
            channel: "email",
            from,
            text: content,
            raw: req.body
        }, { timeout: 15000 });
        console.log("[Email Adapter] Dispatch result:", resp.data);
    } catch (e) {
        console.error("[Email Adapter] Dispatch error:", e.message);
    }

    res.json({ ok: true });
});

app.post("/send", requireAuth, async (req, res) => {
    const { recipient, subject, content } = req.body || {};
    if (!recipient || !content) {
        return res.status(400).json({ error: "invalid_payload" });
    }

    const fullContent = subject ? `Subject: ${subject}\n\n${content}` : content;
    console.log(`[Email Adapter] Send to ${recipient}: ${fullContent.substring(0, 50)}`);

    res.json({ ok: true, channel: "email", recipient, subject, content });
});

app.listen(PORT, () => console.log(`Email adapter listening on ${PORT}`));
