import type { BuiltinSkill } from "../types"

export const omegaSkill: BuiltinSkill = {
  name: "omega",
  description: "OMEGA v120.0 - Köstebek İliği sistem kontrolü. PersonalOS Gateway ve OMEGA script entegrasyonu için.",
  template: `<skill-instruction>
# OMEGA v120.0 - Köstebek İliği Skill

Bu skill, PersonalOS OMEGA v120.0 sistemiyle etkileşim için kullanılır.

## Kullanım

OMEGA sistemi Gateway üzerinden çalışır. Asagidaki endpoint'leri kullan:

### API Endpoints

| Endpoint | Method | Aciklama |
|----------|--------|----------|
| /omega/health | GET | Saglik kontrolu |
| /omega/status | GET | Sistem durumu |
| /omega/summary | GET | Hafiza ozeti |
| /omega/logs | GET | Log kayitlari |
| /omega/execute | POST | Komut calistir |
| /omega/clear | POST | Hafizayi temizle |

### Ornek Kullanim

# Health kontrol
curl -H "Authorization: Bearer devtoken" http://localhost:8080/omega/health

# Status
curl -H "Authorization: Bearer devtoken" http://localhost:8080/omega/status

# Komut calistir
curl -X POST -H "Authorization: Bearer devtoken" -H "Content-Type: application/json" -d '{"command":"DUR"}' http://localhost:8080/omega/execute

### Mevcut Komutlar

- DUR / STATUS - Sistem durumu
- O / OZET - Hafiza ozeti
- L / LOG - Son log kayitlari
- S / SIKI - Sikinti giderici (sprint)
- TEMIZLE - Hafizayi temizle
- YARDIM - Yardim menusu
- Q / CIK - Cikis

### Tool Kullanimi

oh-my-opencode icinden:

omega_status() - Sistem durumu
omega_execute(cmd) - Komut calistir
omega_summary() - Hafiza ozeti
omega_logs() - Log kayitlari
omega_clear() - Hafizayi temizle
omega_sprint() - Hizli dongu
omega_check() - Saglik kontrolu

## Notlar

- OMEGA sistemi Python tabanlidir
- Gateway uzerinden erisilir (port 8080)
- Kalici hafiza Docker volume'da saklanir
- Biyolojik elementler: Toprak, Hava, Su, Ates, Eter, Akil

</skill-instruction>`,
}
