const fs = require("fs");
const path = require("path");
const express = require("express");
const axios = require("axios");

const PORT = parseInt(process.env.PORT || "8088", 10);
const GATEWAY_URL = (process.env.GATEWAY_URL || "http://gateway:8080").replace(/\/+$/,"");
const DISPATCHER_URL = (process.env.DISPATCHER_URL || "http://dispatcher:9400").replace(/\/+$/,"");
const CONFIG_DIR = process.env.CONFIG_DIR || "/app/config";

const app = express();
app.use(express.json({ limit: "2mb" }));
app.use("/", express.static(path.join(__dirname, "public")));

function authHeadersFromReq(req){
  const h = (req.headers["authorization"] || "").toString().trim();
  return h ? { Authorization: h } : {};
}

app.get("/health", (req,res)=>res.json({status:"ok"}));

app.get("/api/health", async (req,res)=>{
  try {
    const [g, d] = await Promise.all([
      axios.get(`${GATEWAY_URL}/health`, { timeout: 8000, headers: authHeadersFromReq(req) }),
      axios.get(`${DISPATCHER_URL}/health`, { timeout: 8000 })
    ]);
    res.json({ ok:true, gateway: g.data, dispatcher: d.data });
  } catch (e) {
    res.status(502).json({ ok:false, error: e.message || String(e) });
  }
});

app.get("/api/queues", async (req,res)=>{
  try {
    const r = await axios.get(`${GATEWAY_URL}/queues/status`, { timeout: 12000, headers: authHeadersFromReq(req) });
    res.json(r.data);
  } catch (e) {
    res.status(502).json({ ok:false, error: e.message || String(e) });
  }
});

app.get("/api/jobs", async (req,res)=>{
  try {
    const channel = req.query.channel || "whatsapp";
    const status  = req.query.status  || "queued";
    const limit   = req.query.limit   || "50";
    const r = await axios.get(`${GATEWAY_URL}/jobs/list?channel=${channel}&status=${status}&limit=${limit}`, { timeout: 20000, headers: authHeadersFromReq(req) });
    res.json(r.data);
  } catch (e) {
    res.status(502).json({ ok:false, error: e.message || String(e) });
  }
});

app.post("/api/purge", async (req,res)=>{
  try {
    const r = await axios.post(`${GATEWAY_URL}/jobs/purge-by-status`, req.body || {}, { timeout: 20000, headers: { "Content-Type":"application/json", ...authHeadersFromReq(req) } });
    res.json(r.data);
  } catch (e) {
    res.status(502).json({ ok:false, error: e.message || String(e) });
  }
});

app.get("/api/dlq", async (req,res)=>{
  try {
    const channel = req.query.channel || "whatsapp";
    const limit = req.query.limit || "50";
    const r = await axios.get(`${GATEWAY_URL}/dlq/${encodeURIComponent(channel)}?limit=${encodeURIComponent(limit)}`, { timeout: 12000, headers: authHeadersFromReq(req) });
    res.json(r.data);
  } catch (e) {
    res.status(502).json({ ok:false, error: e.message || String(e) });
  }
});

app.post("/api/dlq/retry", async (req,res)=>{
  try {
    const channel = (req.body && req.body.channel) ? String(req.body.channel) : "whatsapp";
    const body = { limit: Number(req.body.limit || 25), reset_attempts: !!req.body.reset_attempts };
    const r = await axios.post(`${GATEWAY_URL}/dlq/${encodeURIComponent(channel)}/retry-bulk`, body, { timeout: 20000, headers: { "Content-Type":"application/json", ...authHeadersFromReq(req) } });
    res.json(r.data);
  } catch (e) {
    res.status(502).json({ ok:false, error: e.message || String(e) });
  }
});

const workflowsPath = path.join(CONFIG_DIR, "workflows.json");

app.get("/api/workflows", (req,res)=>{
  try {
    const raw = fs.readFileSync(workflowsPath, "utf8");
    res.json({ ok:true, workflows: JSON.parse(raw) });
  } catch (e) {
    res.status(500).json({ ok:false, error: e.message || String(e) });
  }
});

app.put("/api/workflows", (req,res)=>{
  try {
    const wf = req.body && req.body.workflows ? req.body.workflows : req.body;
    fs.writeFileSync(workflowsPath, JSON.stringify(wf, null, 2), "utf8");
    res.json({ ok:true });
  } catch (e) {
    res.status(500).json({ ok:false, error: e.message || String(e) });
  }
});

app.post("/api/workflows/reload", async (req,res)=>{
  try {
    const r = await axios.post(`${DISPATCHER_URL}/reload`, {}, { timeout: 12000, headers: authHeadersFromReq(req) });
    res.json(r.data);
  } catch (e) {
    res.status(502).json({ ok:false, error: e.message || String(e) });
  }
});

app.listen(PORT, ()=>console.log(`UI listening on ${PORT}`));
