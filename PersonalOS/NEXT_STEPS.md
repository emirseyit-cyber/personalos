# PersonalOS - Sonraki Adımlar

## Hızlı Başlangıç

1. **Docker'ı başlat**
   ```powershell
   docker compose up -d
   ```

2. **Servisleri kontrol et**
   ```bash
   ./health_checks.sh
   ```

## Servisler

| Servis | Port | URL |
|--------|------|-----|
| Gateway | 8080 | http://localhost:8080 |
| WhatsApp Adapter | 3000 | http://localhost:3000 |
| Agent | 8081 | http://localhost:8081 |
| Vault | 8200 | http://localhost:8200 |
| Prometheus | 9090 | http://localhost:9090 |
| Grafana | 3001 | http://localhost:3001 |

## Geliştirme

### WhatsApp Adapter
```bash
cd integration/gateway/adapters/whatsapp
npm install
npm start
```

### Agent
```bash
cd integration/agents/runtime
pip install -r requirements.txt
python agent_main.py
```

## Altyapı

### Kubernetes Dağıtımı
```bash
kubectl apply -f k8s-deployment.yaml
```

### CI/CD
GitHub Actions ile otomatik build için `.github/workflows/ci.yml` ekleyin.

## Sorun Giderme

- Servisler çalışmıyor: `docker compose logs`
- Container'ları yeniden başlat: `docker compose restart`
- Tam temizlik: `docker compose down -v`
