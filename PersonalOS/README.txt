PersonalOS - Kişisel İşletim Sistemi

PersonalOS, AI destekli kişisel asistan ve otomasyon sistemidir.

Kurulum:
1. Docker Desktop'ı başlat
2. Bu klasörde: docker compose up -d
3. Servisler başlayacak

Servisler:
- Gateway: http://localhost:8080
- WhatsApp Adapter: http://localhost:3000
- Agent: http://localhost:8081
- PostgreSQL: localhost:5432
- Redis: localhost:6379
- Vault: http://localhost:8200 (token: root)
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3001 (admin/admin)

Daha fazla bilgi: NEXT_STEPS.md
