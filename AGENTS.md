# OpenCode - Ana Çalışma Alanı

> **HER AÇILIŞTA OKU!** Bu dosya senin belleğin.

---

## 🧠 OTOMATİK ENTEGRASYON PROTOKOLÜ

### Kurallar

1. **Her işlemi otomatik yap** - Kullanıcı istemezse sorma, doğrudan yap
2. **Türkçe açıkla** - Yaptığım her işlemi ekrana Türkçe yaz
3. **Arkaplanda çalış** - Tüm kontrolleri arkaplanda yap, sonucu göster
4. **Entegre çalış** - Servislerin birbiriyle iletişimini kontrol et
5. **Hata olursa düzelt** - Sorun varsa otomatik çöz

### Otomatik Kontrol Listesi (Her Oturum Başında)

```
PersonalOS Kontrol Protokolü:
├── Docker çalışıyor mu? → Kontrol et
├── Tüm servisler ayakta mı? → Kontrol et
├── Gateway erişilebilir mi? → Kontrol et
├── Database bağlantısı var mı? → Kontrol et
├── Redis çalışıyor mu? → Kontrol et
└── UI çalışıyor mu? → Kontrol et
```

---

## 🛡️ ÇÖKME VE BOZULMAYA KARŞI KORUMA SİSTEMİ

### Koruma Scriptleri

| Script | Konum | Kullanım |
|--------|-------|----------|
| Health Monitor | `PersonalOS/scripts/health-monitor.ps1` | Servis sağlık kontrolü |
| Backup | `PersonalOS/scripts/backup.ps1` | Otomatik yedekleme |
| Cleanup | `PersonalOS/scripts/cleanup.ps1` | Log temizleme |

### Health Monitor Kullanımı

```powershell
# Tek seferlik kontrol
.\scripts\health-monitor.ps1 -Silent

# Sürekli izleme + otomatik restart
.\scripts\health-monitor.ps1 -AutoRestart

# Özel aralık (saniye)
.\scripts\health-monitor.ps1 -AutoRestart -IntervalSeconds 60
```

**Özellikler:**
- Tüm servisleri otomatik kontrol eder
- Port ve HTTP endpoint kontrolü
- 3 kez ardışık hata = otomatik restart
- CPU/RAM/Disk istatistikleri

### Backup Kullanımı

```powershell
# Tek seferlik yedekleme
.\scripts\backup.ps1

# Otomatik (eski yedekleri siler)
.\scripts\backup.ps1 -Auto -KeepDays 7
```

**Yedeklenenler:**
- Docker volume'ları (PostgreSQL, Redis, MinIO, Elasticsearch)
- Konfigürasyon dosyaları
- Database dump
- Redis verileri

### Cleanup Kullanımı

```powershell
# Log temizleme
.\scripts\cleanup.ps1 -MaxLogSizeMB 100 -KeepDays 7
```

---

### 2026-02-24 (Bugün)
- **Koruma sistemi kuruldu:**
  - Health Monitor: Otomatik sağlık kontrolü + restart
  - Backup Script: Otomatik yedekleme (volume, DB, Redis)
  - Cleanup Script: Log temizleme ve disk optimizasyonu
- **PersonalOS UI düzeltildi:**
  - Favicon 404 hatası giderildi
  - Network sorunu çözüldü (yanlış network'teydi)
  - Artık Gateway ve Dispatcher ile doğru çalışıyor
- **Eksiklikler tespit edildi:**
  - Environment değişkenleri eksik (TELEGRAM_BOT_TOKEN vb.)
  - Traefik yapılandırması yok (pasif durumda)
  - Monitoring eksik (sadece Gateway metrik üretiyor)
- **Servisler durumu:** 25/25 çalışıyor ✅

### 2026-02-23 (Devam)
- **PersonalOS'a yeni servisler eklendi:**
  - MinIO (9000, 9001) - S3 uyumlu depolama
  - Mailhog (1025, 8025) - E-posta test
  - Portainer (9443) - Docker yönetim UI
  - Meilisearch (7700) - Arama motoru
- **WhatsApp adapter** hazır (mock provider ile test edildi)
- **Agent genişletildi:**
  - Tool execution (weather, search, calculator, memory)
  - Conversation history
  - Hata sayacı
  - Latency ölçümü
  - Gateway'e tool listesi kaydı

### 2026-02-23 (Devam)
- **PersonalOS Gateway** yeniden yazıldı (Node.js):
  - RBAC Auth (Bearer token)
  - Idempotency (X-Idempotency-Key)
  - Session yönetimi
  - Async Queue (WhatsApp)
  - Prometheus metrics
- **Test sonuçları başarılı:**
  - Session oluştur: ✓
  - Agent invoke: ✓
  - Idempotency cache: ✓
  - Async job queue: ✓
- **PowerShell entegrasyonu:** personalos.ps1 hazır

### 2026-02-23 (En Son)
- **personalos_full_windows.ps1** oluşturuldu (12 adım):
  1. BuildKit indir/kur
  2. Klasör yapısı (30+ klasör)
  3. Config dosyaları
  4. Gateway, Adapter, Agent, Worker kodları
  5. Prometheus, Grafana, Alertmanager
  6. Vault bootstrap
  7. Helm chart, Terraform
  8. CI/CD workflows
  9. Render pipeline
  10. Smoke test
  11. Docker compose
  12. Test

- **Versiyonlar sabitlendi:** VERSIONS.txt olusturuldu
  - postgres: 15-alpine
  - redis: 7-alpine
  - vault: 1.14.0
  - prometheus: v2.54.1
  - grafana: 10.4.2
  - minio: 2024-01-16
  - alertmanager: v0.27.0
  - Tum servislerde `restart: unless-stopped` eklendi

---

## Çalışma Geçmişi

### 2026-02-23
- Dokümanlar temizlendi (gereksiz dosyalar silindi)
- OneDrive dokümanları da temizlendi
- Amasya 3. Asliye Hukuk Mahkemesi 2025/2241 dava klasörü incelendi
- Eski OpenCode exe'leri silindi (scoop kullanılıyor)
- Eski tool server dosyaları silindi
- Gereksiz scriptler temizlendi
- Klasörler gruplandırıldı (Calisma-Alanlari, Projeler, Veriler)
- OpenCode-Sistem tek klasöre birleştirildi (75 araç)
- Projeler Türkçe gruplandırıldı
- **PersonalOS kuruldu ve çalışıyor** (Docker, 8 servis)
- **Docker Desktop kuruldu**

---

## Proje Yapısı

```
D:\OpenCode\
├── AGENTS.md              # ← HER ZAMAN OKU (bellek)
├── Dokümanlar\           # README.md (tek dosya)
├── Bellek\               # Oturum belleği (bellek.json)
├── Calisma-Alanlari\
│   ├── Araçlar\         # Java & JS araçları
│   ├── Scriptler\        # PowerShell, Python, Diğer
│   └── OpenCode-Sistem\ # 75 araç (Temel klasöründe)
├── Projeler\
│   ├── OpenCode-Eklentileri\ # 25 proje
│   └── Diğer\               # 17 proje
├── PersonalOS\           # Kişisel işletim sistemi
│   ├── docker-compose.yml
│   ├── integration\     # Adapter & Agent
│   ├── observability\   # Prometheus
│   └── render\          # Video render
└── Veriler\             # Veriler, yedekler
```

---

## PersonalOS (Çalışıyor!)

**Servisler (25):**
| Servis | Port | URL | Durum |
|--------|------|-----|-------|
| Gateway | 8080 | http://localhost:8080 | ✅ |
| WhatsApp Adapter | 3000 | http://localhost:3000 | ✅ |
| Telegram Adapter | 3002 | http://localhost:3002 | ✅ |
| Email Adapter | 3003 | http://localhost:3003 | ✅ |
| WhatsApp Worker | 9101 | http://localhost:9101 | ✅ |
| Telegram Worker | 9102 | http://localhost:9102 | ✅ |
| Email Worker | 9103 | http://localhost:9103 | ✅ |
| Agent | 8081 | http://localhost:8081 | ✅ |
| Dispatcher | 9400 | http://localhost:9400 | ✅ |
| UI | 8088 | http://localhost:8088 | ✅ |
| PostgreSQL | 5432 | localhost:5432 | ✅ |
| Redis | 6379 | localhost:6379 | ✅ |
| Vault | 8200 | http://localhost:8200 | ✅ |
| Prometheus | 9090 | http://localhost:9090 | ✅ |
| Alertmanager | 9093 | http://localhost:9093 | ✅ |
| Grafana | 3001 | http://localhost:3001 | ✅ |
| MinIO | 9000, 9001 | http://localhost:9000 | ✅ |
| Mailhog | 1025, 8025 | http://localhost:8025 | ✅ |
| Portainer | 9443 | https://localhost:9443 | ✅ |
| Meilisearch | 7700 | http://localhost:7700 | ✅ |
| Elasticsearch | 9200 | http://localhost:9200 | ✅ |
| Kibana | 5601 | http://localhost:5601 | ✅ |
| RabbitMQ | 5672, 15672 | http://localhost:15672 | ✅ |
| Jenkins | 9094 | http://localhost:9094 | ✅ |
| Traefik | 8082 | http://localhost:8082 | ⚠️ Pasif |

### Entegrasyon Akışı

```
Kullanıcı (Telegram/WhatsApp/Email)
        ↓
Adapter (WebHook alır)
        ↓
Gateway (İşler, kuyruğa ekler)
        ↓
Redis Queue (Job saklar)
        ↓
Worker (İşleri alır, işler)
        ↓
Agent (AI yanıt üretir)
        ↓
Worker (Yanıtı kanala gönderir)
        ↓
Adapter (Mesajı iletir)
        ↓
Kullanıcı
```

### Gateway API:
- Auth: `Authorization: Bearer devtoken`
- Idempotency: `X-Idempotency-Key`
- `GET /health` - Sağlık kontrolü
- `POST /session` - Oturum oluştur
- `POST /agent/invoke` - Agent çağır
- `GET /queues/status` - Kuyruk durumu

### Çalıştırma:
```bash
cd D:\OpenCode\PersonalOS
docker compose up -d
```

---

## OpenCode CLI

**Konum:** `scoop\apps\opencode\current\opencode.exe`

**Çalıştırma:**
```powershell
opencode
# veya
scoop run opencode
```

---

## Temel Yetenekler

### 1. Dosya İşlemleri ✓
- `read` - Dosya oku
- `write` - Dosya oluştur/güncelle
- `edit` - Satır düzenle
- `grep` - İçerik ara
- `glob` - Dosya ara

### 2. Kod Analizi ✓
- LSP: Tanımlama, referanslar, hover
- Go to definition
- Refactoring, bug bulma

### 3. Komut Çalıştırma ✓
- Bash, Git, npm, PowerShell
- Docker, docker compose

### 4. Web Araştırma ✓
- `websearch` - İnternet araması
- `webfetch` - URL içerik çekme
- `codesearch` - Kod dokümanları

### 5. Agent Sistemi ✓
- Çoklu agent, alt oturumlar, görev dağıtma

---

## Slash Komutları

| Komut | Açıklama |
|-------|-----------|
| `/help` | Yardım |
| `/connect` | Bağlan |
| `/providers` | Sağlayıcılar |
| `/share` | Paylaş |
| `/undo` | Geri al |
| `/redo` | Yeniden yap |
| `/init` | Başlat |
| `/zen` | Zen mod |
| `/lsp restart` | LSP yeniden başlat |

---

## Dosya Referansı

```
@dosya.ts          # Tek dosya
@src/              # Klasör
@dosya.ts:10       # Satır
```

---

## Sorun Giderme

- **LSP çalışmıyor**: `/lsp restart`
- **Provider hatası**: `/connect` tekrar bağlan
- **Docker çalışmıyor**: Docker Desktop'ı başlat
- **Port çakışması**: `docker ps` kontrol et

---

## Dokümanlar

- `Dokümanlar/README.md` - Tüm yetenekler ve rehber (TEK DOSYA)

---

## 2026-02-23 (Genişletme)

### Yeni Servisler (19 toplam)
| Servis | Port | URL |
|--------|------|-----|
| Elasticsearch | 9200, 9300 | http://localhost:9200 |
| Kibana | 5601 | http://localhost:5601 |
| RabbitMQ | 5672, 15672 | http://localhost:15672 |
| Jenkins | 9094, 50000 | http://localhost:9094 |
| Traefik | 80, 443, 8090 | http://localhost:8090 |

### Gateway v1.1.0 Güncellemeleri
- **Rate Limiting**: express-rate-limit (general: 60req/dk, invoke: 30req/dk, webhook: 20req/dk)
- **Webhook API**: `/webhook/:webhook_id` ve `/webhook/:webhook_id/events`
- **Analytics**: `/analytics/track` ve `/analytics/:session_id`
- **Logging**: Winston entegrasyonu

### CI/CD Pipeline
- GitHub Actions workflow (`.github/workflows/ci-cd.yml`)
- Test, Build, Deploy aşamaları
- Docker Buildx ile multi-platform build

### Testler
- Jest testleri (`integration/gateway/service/tests/gateway.test.js`)
- Session, Agent Invoke, Webhook, Analytics, Rate Limiting testleri

### Grafana Dashboard
- `observability/grafana/dashboards/gateway.json`
- Latency, invocations, errors, rate limit, channel sends, memory metrikleri

### 2026-02-23 (UI Pack)
- **Dispatcher** (9400): Workflow engine, agent çağrısı
- **UI Servisi** (8088): Web dashboard
  - Status, Inbox, Jobs, DLQ, Rules Editor sekmeleri
- **Adapterlar**:
  - WhatsApp (3000) - mevcut
  - Telegram (3002) - yeni
  - Email (3003) - yeni
- **Workerlar**:
  - WhatsApp Worker (9101) - mevcut
  - Telegram Worker (9102) - yeni
  - Email Worker (9103) - yeni
- **Config**: channels.json, workflows.json

---

### 2026-02-26 (Bugün)
- **oh-my-opencode v3.8.0 hazırlandı:**
  - 13 yeni personalos tool eklendi
  - 8 yeni omega tool eklendi
  - omega skill eklendi (7. skill)
  - 3 yeni MCP eklendi (personalos-gateway, personalos-agent, personalos-dispatcher)
- **PersonalOS Gateway güncellendi:**
  - OMEGA v120.0 entegrasyonu (Python)
  - 6 yeni OMEGA endpoint
  - 5 yeni Sistem endpoint
  - Docker volume entegrasyonu
- **PersonalOS UI güncellendi:**
  - OMEGA sekmesi eklendi
  - Dark/Light mode
  - Tooltip sistemi
- **OMEGA v120.0 - Köstebek İliği:**
  - Python script hazır
  - Kalıcı hafıza (Docker volume)
  - CLI emülasyonu
  - Biyolojik elementler sistemi
- **NPM Publish hazır:**
  - Build tamam (2.53 MB)
  - Author: PersonalOS Team
  - Token bekleniyor

---

*Son güncelleme: 2026-02-26*
*Bu dosya her oturumda okunur - önceki çalışmalar buraya kaydedilir.*
