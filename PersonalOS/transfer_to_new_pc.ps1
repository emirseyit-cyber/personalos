# PersonalOS Taşıma Scripti
# Bu script PersonalOS'u yeni PC'ye taşımak için gerekli her şeyi hazırlar
# Kullanım: .\transfer_to_new_pc.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

Write-Host "=== PersonalOS Taşıma Scripti ===" -ForegroundColor Cyan
Write-Host ""

# 1. Klasör yapısını kopyala
Write-Host "[1/4] Dosyalar kopyalanıyor..." -ForegroundColor Yellow
$OutputPath = Join-Path $ScriptDir "PersonalOS_Transfer"
if (Test-Path $OutputPath) { Remove-Item $OutputPath -Recurse -Force }
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

$excludeDirs = @("node_modules", ".git", "pgdata", "redisdata", "miniodata", "portainerdata", "meilisearchdata", "promdata", "elasticsearchdata", "rabbitmqdata", "jenkinsdata", "volumes")

function Copy-Filtered {
    param($Source, $Dest)
    Get-ChildItem -Path $Source -Recurse -File | ForEach-Object {
        $relPath = $_.FullName.Substring($Source.Length + 1)
        $dir = Split-Path (Join-Path $Dest $relPath) -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Copy-Item $_.FullName (Join-Path $Dest $relPath) -Force
    }
}

Copy-Item "docker-compose.yml" $OutputPath
Copy-Item ".env" $OutputPath -ErrorAction SilentlyContinue
Copy-Item "VERSIONS.txt" $OutputPath -ErrorAction SilentlyContinue
Copy-Item "integration" $OutputPath -Recurse -Force
Copy-Item "config" $OutputPath -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "observability" $OutputPath -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "migration" $OutputPath -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item ".github" $OutputPath -Recurse -Force -ErrorAction SilentlyContinue

# 3. Kurulum scripti oluştur
Write-Host "[3/4] Kurulum scripti oluşturuluyor..." -ForegroundColor Yellow

$installScript = @'
# PersonalOS Kurulum Scripti (Yeni PC'de çalıştır)
# Bu script otomatik kurulum yapar

param(
    [switch]$SkipDockerCheck
)

$ErrorActionPreference = "Stop"

Write-Host "=== PersonalOS Kurulum ===" -ForegroundColor Cyan
Write-Host ""

# Docker kontrolü
if (-not $SkipDockerCheck) {
    Write-Host "[1/4] Docker kontrolü..." -ForegroundColor Yellow
    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $docker) {
        Write-Host "Docker Desktop kurulu değil! Önce kurun: https://www.docker.com/products/docker-desktop" -ForegroundColor Red
        exit 1
    }
    Write-Host "Docker OK" -ForegroundColor Green
}

# Servisleri başlat
Write-Host "[2/4] Servisler başlatılıyor..." -ForegroundColor Yellow
docker compose up -d

# Bekleme
Write-Host "[3/4] Servisler hazırlanıyor..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Durum kontrolü
Write-Host "[4/4] Durum kontrolü..." -ForegroundColor Yellow
docker compose ps

Write-Host ""
Write-Host "=== Kurulum Tamamlandı! ===" -ForegroundColor Green
Write-Host ""
Write-Host "Servisler:" -ForegroundColor Cyan
Write-Host "  Gateway:  http://localhost:8080"
Write-Host "  UI:       http://localhost:8088"
Write-Host "  Grafana:  http://localhost:3001"
Write-Host ""
Write-Host "Token: Bearer devtoken"
'@

$installScript | Out-File -FilePath (Join-Path $OutputPath "install.ps1") -Encoding UTF8

# 4. README oluştur
$readme = @'
# PersonalOS Transfer Paketi

## Kurulum

1. Bu klasörü yeni PC'ye kopyalayın
2. Docker Desktop'ı kurun
3. `install.ps1` scriptini çalıştırın:

```powershell
.\install.ps1
```

## Servisler

| Servis | Port |
|--------|------|
| Gateway | 8080 |
| UI | 8088 |
| Grafana | 3001 |

Token: Bearer devtoken

## Not

- Veriler (database, redis) dahil DEĞİLDİR
- Sadece kod ve konfigürasyon taşınır
- İlk çalıştırmada fresh başlar
'@

$readme | Out-File -FilePath (Join-Path $OutputPath "README.md") -Encoding UTF8

# 5. Sıkıştır
Write-Host "[4/5] Sıkıştırılıyor..." -ForegroundColor Yellow
if (Test-Path "PersonalOS_Transfer.zip") { Remove-Item "PersonalOS_Transfer.zip" -Force }
Compress-Archive -Path $OutputPath -DestinationPath "PersonalOS_Transfer.zip" -Force

# Temizlik
Remove-Item $OutputPath -Recurse -Force

Write-Host "[5/5] Tamamlandı!" -ForegroundColor Green
Write-Host ""
Write-Host "Çıktı: PersonalOS_Transfer.zip" -ForegroundColor Cyan
Write-Host "Bu dosyayı yeni PC'ye kopyalayın ve içindeki install.ps1'i çalıştırın." -ForegroundColor White
