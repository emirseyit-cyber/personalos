# PersonalOS Log Rotation Script
# Log dosyalarını otomatik temizleme ve rotasyon
# Oluşturulma: 2026-02-24

param(
    [int]$MaxLogSizeMB = 100,
    [int]$KeepDays = 7
)

$ErrorActionPreference = "Continue"

Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  PersonalOS Log Temizleme" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Docker log temizleme
Write-Host "[1/3] Docker container logları temizleniyor..." -ForegroundColor Yellow

$containers = docker ps --format "{{.Names}}" | Where-Object { $_ -match "personalos" }

$totalCleaned = 0
foreach ($container in $containers) {
    # Container log boyutu
    $logFile = "$env:ProgramData\docker\containers\$((docker inspect $container --format '{{.Id}}'))\$((docker inspect $container --format '{{.Id}}'))-json.log"
    
    if (Test-Path $logFile) {
        $sizeMB = (Get-Item $logFile).Length / 1MB
        if ($sizeMB -gt $MaxLogSizeMB) {
            # Log dosyasını sıfırla
            Clear-Content $logFile -ErrorAction SilentlyContinue
            Write-Host "    ✓ $container log temizlendi ($([math]::Round($sizeMB, 1)) MB)" -ForegroundColor Green
            $totalCleaned += $sizeMB
        }
    }
}

if ($totalCleaned -eq 0) {
    Write-Host "    ✓ Log dosyaları temiz" -ForegroundColor Green
}

# Docker system prune
Write-Host ""
Write-Host "[2/3] Docker sistem temizliği..." -ForegroundColor Yellow

# Stopped container'ları sil
$stoppedCount = $(docker ps -aq --filter "status=exited" | Measure-Object).Count
if ($stoppedCount -gt 0) {
    docker container prune -f > $null 2>&1
    Write-Host "    ✓ $stoppedCount durmuş container silindi" -ForegroundColor Green
}

# Kullanılmayan image'ları sil
$unusedImages = $(docker images -q --filter "dangling=true" | Measure-Object).Count
if ($unusedImages -gt 0) {
    docker image prune -f > $null 2>&1
    Write-Host "    ✓ $unusedImages kullanılmayan image silindi" -ForegroundColor Green
}

# Kullanılmayan volume'ları sil
$unusedVolumes = $(docker volume ls -qf "dangling=true" | Measure-Object).Count
if ($unusedVolumes -gt 0) {
    docker volume prune -f > $null 2>&1
    Write-Host "    ✓ $unusedVolumes kullanılmayan volume silindi" -ForegroundColor Green
}

# Build cache temizle
docker builder prune -f > $null 2>&1
Write-Host "    ✓ Build cache temizlendi" -ForegroundColor Green

# Windows temp klasörü temizleme
Write-Host ""
Write-Host "[3/3] Geçici dosyalar temizleniyor..." -ForegroundColor Yellow

# Docker temp
$dockerTemp = "$env:TEMP\docker*"
Get-Item $dockerTemp -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Playwright temp
$playwrightTemp = "$env:LOCALAPPDATA\Temp\playwright*"
Get-Item $playwrightTemp -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Genel temp (opsiyonel)
$tempSize = (Get-ChildItem $env:TEMP -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host "    ℹ Geçici dosyalar: $([math]::Round($tempSize, 0)) MB" -ForegroundColor Gray

# Disk alanı raporu
Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Disk Durumu" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan

$drive = Get-PSDrive C
Write-Host "Toplam: $([math]::Round($drive.Used/1GB + $drive.Free/1GB, 2)) GB" -ForegroundColor White
Write-Host "Kullanılan: $([math]::Round($drive.Used/1GB, 2)) GB" -ForegroundColor Yellow
Write-Host "Boş: $([math]::Round($drive.Free/1GB, 2)) GB" -ForegroundColor Green
Write-Host ""

Write-Host "✓ Temizlik tamamlandı!" -ForegroundColor Green
