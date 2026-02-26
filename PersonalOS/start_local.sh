#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)/personalos_local"
echo "Bootstrapping and starting PersonalOS local bundle at: $ROOT_DIR"
mkdir -p "$ROOT_DIR"

write() {
  local path="$1"; shift
  mkdir -p "$(dirname "$ROOT_DIR/$path")"
  cat > "$ROOT_DIR/$path" <<'EOF'
'"$@"
EOF
}

echo "Writing docker-compose.yml..."
write docker-compose.yml 'version: "3.8"
services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: personalos
      POSTGRES_PASSWORD: personalos
      POSTGRES_DB: personalos
    volumes:
      - pgdata:/var/lib/postgresql/data
    networks:
      - personalos-net

  redis:
    image: redis:7-alpine
    command: ["redis-server", "--save", "60", "1"]
    volumes:
      - redisdata:/data
    networks:
      - personalos-net

  vault:
    image: vault:1.14.0
    environment:
      VAULT_DEV_ROOT_TOKEN_ID: "root"
      VAULT_ADDR: "http://0.0.0.0:8200"
    command: "server -dev -dev-root-token-id=root -dev-listen-address=0.0.0.0:8200"
    ports:
      - "8200:8200"
    networks:
      - personalos-net

  gateway:
    image: hashicorp/http-echo:0.2.3
    command: ["-text=PersonalOS Gateway stub - OK"]
    ports:
      - "8080:5678"
    networks:
      - personalos-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5678/"]
      interval: 10s
      timeout: 5s
      retries: 3

  whatsapp-adapter:
    build:
      context: ./integration/gateway/adapters/whatsapp
      dockerfile: Dockerfile
    environment:
      - ADAPTER_API_KEY=changeme
      - WHATSAPP_PROVIDER_URL=https://httpbin.org/post
      - SIGNING_SECRET=changeme
    ports:
      - "3000:3000"
    depends_on:
      - gateway
    networks:
      - personalos-net

  agent:
    build:
      context: ./integration/agents/runtime
      dockerfile: Dockerfile.agent
    environment:
      - AGENT_ID=example-agent-1
      - GATEWAY_URL=http://gateway:5678
    ports:
      - "8081:8080"
    depends_on:
      - gateway
      - redis
      - postgres
    networks:
      - personalos-net

  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./observability/prometheus/scrape-config.yaml:/etc/prometheus/prometheus.yml:ro
    ports:
      - "9090:9090"
    networks:
      - personalos-net

  grafana:
    image: grafana/grafana:9.5.0
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    ports:
      - "3001:3000"
    networks:
      - personalos-net

volumes:
  pgdata:
  redisdata:

networks:
  personalos-net:
    driver: bridge
'

echo "Writing WhatsApp adapter files..."
write integration/gateway/adapters/whatsapp/index.js 'const express = require("express");
const bodyParser = require("body-parser");
const axios = require("axios");
const crypto = require("crypto");
const app = express();
app.use(bodyParser.json());
const API_KEY = process.env.ADAPTER_API_KEY || "changeme";
const PROVIDER_URL = process.env.WHATSAPP_PROVIDER_URL || "https://httpbin.org/post";
const SIGNING_SECRET = process.env.SIGNING_SECRET || "secret";
function verifySignature(req){ const sig = req.headers["x-signature"]||""; const payload = JSON.stringify(req.body||{}); const hmac = crypto.createHmac("sha256", SIGNING_SECRET).update(payload).digest("hex"); return sig===hmac; }
app.post("/send", async (req,res)=>{ const { recipient, content } = req.body; if(!recipient||!content) return res.status(400).json({error:"invalid_payload"}); try{ const resp = await axios.post(PROVIDER_URL,{to:recipient,message:content},{headers:{Authorization:`Bearer ${API_KEY}`},timeout:10000}); const messageId = resp.data && resp.data.id ? resp.data.id : `msg-${Date.now()}`; return res.json({message_id:messageId,status:"queued"}); }catch(err){ console.error("Send error", err.message||err); return res.status(502).json({error:"provider_error"}); }});
app.post("/webhook",(req,res)=>{ if(!verifySignature(req)) return res.status(401).json({ack:false}); console.log("Webhook event", req.body); res.json({ack:true}); });
app.get("/health",(req,res)=>res.json({status:"ok"}));
const port = process.env.PORT||3000; app.listen(port,()=>console.log(`WhatsApp adapter listening on ${port}`));'

write integration/gateway/adapters/whatsapp/package.json '{
  "name": "personalos-whatsapp-adapter",
  "version": "0.1.0",
  "main": "index.js",
  "scripts": { "start": "node index.js" },
  "dependencies": { "express": "^4.18.2", "body-parser": "^1.20.2", "axios": "^1.4.0" }
}'

write integration/gateway/adapters/whatsapp/Dockerfile 'FROM node:18-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --only=production || npm install --production
COPY . .
ENV NODE_ENV=production
EXPOSE 3000
CMD ["node","index.js"]'

echo "Writing agent files..."
write integration/agents/runtime/agent_main.py 'import os, logging, requests
from flask import Flask, jsonify, request
from prometheus_client import Counter, Gauge, generate_latest, CONTENT_TYPE_LATEST
app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
AGENT_ID = os.getenv("AGENT_ID","example-agent-1")
GATEWAY_URL = os.getenv("GATEWAY_URL","http://gateway:5678")
invocations = Counter("agent_invocations_total","Total invocations")
health_gauge = Gauge("agent_health_percent","Agent health percent")
@app.route("/health", methods=["GET"])
def health(): return jsonify({"status":"ok","agent_id":AGENT_ID})
@app.route("/metrics")
def metrics():
    health_gauge.set(85)
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}
@app.route("/invoke", methods=["POST"])
def invoke():
    payload = request.json or {}
    logging.info("Invoke received: %s", payload)
    invocations.inc()
    return jsonify({"agent_id":AGENT_ID,"result":"ok","input":payload})
def register_to_gateway():
    try:
        requests.post(GATEWAY_URL + "/agents/register", json={"agent_id":AGENT_ID}, timeout=2)
    except Exception:
        pass
if __name__ == "__main__":
    register_to_gateway()
    app.run(host="0.0.0.0", port=int(os.getenv("PORT","8080")))'

write integration/agents/runtime/requirements.txt 'Flask==2.2.5
requests==2.31.0
gunicorn==20.1.0
prometheus_client==0.16.0
'

write integration/agents/runtime/Dockerfile.agent 'FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY agent_main.py .
ENV PYTHONUNBUFFERED=1
EXPOSE 8080
CMD ["gunicorn","--bind","0.0.0.0:8080","agent_main:app","--workers","1"]'

echo "Writing Prometheus config..."
write observability/prometheus/scrape-config.yaml 'scrape_configs:
  - job_name: "gateway"
    metrics_path: /metrics
    static_configs:
      - targets: ["gateway:8080"]
  - job_name: "agents"
    metrics_path: /metrics
    static_configs:
      - targets: ["agent:8080"]'

echo "Writing render files..."
write render/index.html '<!doctype html><html><head><meta charset="utf-8"/><title>OP-ODE Render</title><meta name="viewport" content="width=1280,height=720"><style>body{margin:0;background:#071021;color:#e6eef8;font-family:Arial,Helvetica,sans-serif} .box{width:1280px;height:720px;display:flex;align-items:center;justify-content:center} .card{width:1000px;height:560px;background:#0f1720;border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:28px;color:#cfe9ff}</style></head><body><div class="box"><div class="card">OP-ODE Demo Frame</div></div></body></html>'

write render/capture_frames.js 'const puppeteer = require("puppeteer");
(async()=>{const DURATION=process.env.DURATION?parseInt(process.env.DURATION):30;const FPS=process.env.FPS?parseInt(process.env.FPS):30;const TOTAL=DURATION*FPS;const VIEW={width:1280,height:720};const browser=await puppeteer.launch({headless:true,args:["--no-sandbox"]});const page=await browser.newPage();await page.setViewport(VIEW);await page.goto("file://"+process.cwd()+"/render/index.html",{waitUntil:"networkidle2"});for(let i=0;i<TOTAL;i++){await page.screenshot({path:`frame-${String(i+1).padStart(3,"0")}.png`});await page.waitForTimeout(1000/FPS);}await browser.close();console.log("Captured",TOTAL,"frames");})();'

write render/package.json '{
  "name": "personalos-render",
  "version": "0.1.0",
  "scripts": { "capture": "node capture_frames.js" },
  "dependencies": { "puppeteer": "^20.0.0" }
}'

write render/make_video.sh '#!/usr/bin/env bash
set -euo pipefail
FPS=${FPS:-30}
RAW=opode_raw.mp4
ffmpeg -y -framerate $FPS -i frame-%03d.png -c:v libx264 -pix_fmt yuv420p -vf "scale=1280:720" $RAW
if [ -f voiceover.mp3 ]; then ffmpeg -y -i $RAW -i voiceover.mp3 -c:v copy -c:a aac -b:a 192k -shortest opode_final.mp4; else cp $RAW opode_final.mp4; fi
echo "Video ready: opode_final.mp4"
'
chmod +x "$ROOT_DIR/render/make_video.sh"

echo "Writing helper scripts..."
write health_checks.sh '#!/usr/bin/env bash
set -e
echo "Gateway:"; curl -sS http://localhost:8080 || true
echo "Adapter health:"; curl -sS http://localhost:3000/health || true
echo "Agent health:"; curl -sS http://localhost:8081/health || true
'
chmod +x "$ROOT_DIR/health_checks.sh"

write start_local.sh '#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if ! command -v docker >/dev/null 2>&1; then echo "Docker not found"; exit 1; fi
if ! docker compose version >/dev/null 2>&1; then echo "docker compose plugin not found"; exit 1; fi
echo "Starting local PersonalOS stack..."
docker compose up --build -d
echo "Waiting 8s for services..."
sleep 8
./health_checks.sh || true
echo "Endpoints:
  Gateway -> http://localhost:8080
  Adapter -> http://localhost:3000
  Agent -> http://localhost:8081
  Prometheus -> http://localhost:9090
  Grafana -> http://localhost:3001
  Vault -> http://localhost:8200 (token: root)"
'
chmod +x "$ROOT_DIR/start_local.sh"

write README.txt "PersonalOS local bundle\n\nRun:\n  cd personalos_local\n  ./start_local.sh\n\nIf builds fail, paste the terminal output here and I will provide exact fixes."

echo "Creating zip bundle (if zip available)..."
cd "$ROOT_DIR"
if command -v zip >/dev/null 2>&1; then
  zip -r ../personalos_local_bundle.zip . >/dev/null 2>&1 || true
  echo "Created zip: $(pwd)/../personalos_local_bundle.zip"
fi

echo "Bootstrap complete. Folder: $ROOT_DIR"
echo "Now starting stack..."
cd "$ROOT_DIR"
./start_local.sh

echo
echo "If anything fails, copy the full terminal output here. I will provide the exact fix and a corrected single-file patch."
