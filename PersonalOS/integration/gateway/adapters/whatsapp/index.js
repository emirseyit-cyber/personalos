const express = require("express");
const bodyParser = require("body-parser");
const axios = require("axios");
const crypto = require("crypto");
const app = express();
app.use(bodyParser.json());
const API_KEY = process.env.ADAPTER_API_KEY || "changeme";
const PROVIDER_URL = process.env.WHATSAPP_PROVIDER_URL || "https://httpbin.org/post";
const SIGNING_SECRET = process.env.SIGNING_SECRET || "secret";

function verifySignature(req){ 
  const sig = req.headers["x-signature"]||""; 
  const payload = JSON.stringify(req.body||{}); 
  const hmac = crypto.createHmac("sha256", SIGNING_SECRET).update(payload).digest("hex"); 
  return sig===hmac; 
}

app.post("/send", async (req,res)=>{ 
  const { recipient, content } = req.body; 
  if(!recipient||!content) return res.status(400).json({error:"invalid_payload"}); 
  try{ 
    const resp = await axios.post(PROVIDER_URL,{to:recipient,message:content},{headers:{Authorization:`Bearer ${API_KEY}`},timeout:10000}); 
    const messageId = resp.data && resp.data.id ? resp.data.id : `msg-${Date.now()}`; 
    return res.json({message_id:messageId,status:"queued"}); 
  }catch(err){ 
    console.error("Send error", err.message||err); 
    return res.status(502).json({error:"provider_error"}); 
  }
});

app.post("/webhook",(req,res)=>{ 
  if(!verifySignature(req)) return res.status(401).json({ack:false}); 
  console.log("Webhook event", req.body); 
  res.json({ack:true}); 
});

app.get("/health",(req,res)=>res.json({status:"ok"}));

const port = process.env.PORT||3000; 
app.listen(port,()=>console.log(`WhatsApp adapter listening on ${port}`));
