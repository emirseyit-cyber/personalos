# PersonalOS Backup Script
# Veri kaybına karşı otomatik yedekleme sistemi
# Oluşturulma: 2026-02-24

param(
    [switch]$Auto,
    [int]$KeepDays = 7
)

$ErrorActionPreference = "Continue"

# Konfigürasyon
$BackupDir = "D:\OpenCode\PersonalOS\backups"
$DateStamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$BackupName = "personalos_backup_$DateStamp"

# Docker volume'ları
$Volumes = @(
    "personalos_transfer_pgdata",
    "personalos_transfer_redisdata",
    "personalos_transfer_miniodata",
    "personalos_transfer_meilisearchdata",
    "personalos_transfer_promdata",
    "personalos_transfer_elasticsearchdata",
    "personalos_transfer_rabbitmqdata"
)

# Önemli dosyalar
$ImportantFiles = @(
    "D:\OpenCode\PersonalOS\config\channels.json",
    "D:\OpenCode\PersonalOS\config\workflows.json",
    "D:\OpenCode\PersonalOS\.env",
    "D:\OpenCode\PersonalOS\docker-compose.yml"
)

Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  PersonalOS Yedekleme Sistemi" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Backup dizini oluştur
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Host "[+] Backup dizini oluşturuldu: $BackupDir" -ForegroundColor Green
}

# Yedekleme klasörü
$BackupPath = Join-Path $BackupDir $BackupName
New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
Write-Host "[+] Yedekleme başlatıldı: $BackupName" -ForegroundColor Cyan
Write-Host ""

# 1. Docker Volume yedekleme
Write-Host "[1/4] Docker volume'ları yedekleniyor..." -ForegroundColor Yellow

foreach ($volume in $Volumes) {
    $volumeBackup = Join-Path $BackupPath "$volume.tar.gz"
    
    # Volume var mı kontrol et
    $volumeExists = docker volume ls -q -f "name=$volume"
    if ($volumeExists) {
        Write-Host "    ↳ $volume -> $volumeBackup" -ForegroundColor Gray
        docker run --rm -v $volume:/data -v "${BackupPath}:/backup" alpine:latest tar czf "/backup/$($volume).tar.gz" -C /data . 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    ✓ $volume yedeklendi" -ForegroundColor Green
        } else {
            Write-Host "    ✗ $volume yedekleme hatası" -ForegroundColor Red
        }
    } else {
        Write-Host "    ⊘ $volume bulunamadı (atlandı)" -ForegroundColor Gray
    }
}

# 2. Konfigürasyon dosyaları yedekleme
Write-Host ""
Write-Host "[2/4] Konfigürasyon dosyaları yedekleniyor..." -ForegroundColor Yellow

$configBackup = Join-Path $BackupPath "config"
New-Item -ItemType Directory -Path $configBackup -Force | Out-Null

foreach ($file in $ImportantFiles) {
    if (Test-Path $file) {
        $fileName = Split-Path $file -Leaf
        Copy-Item $file -Destination (Join-Path $configBackup $fileName) -Force
        Write-Host "    ✓ $fileName" -ForegroundColor Green
    } else {
        Write-Host "    ✗ $file bulunamadı" -ForegroundColor Red
    }
}

# 3. Database dump (PostgreSQL)
Write-Host ""
Write-Host "[3/4] PostgreSQL veritabanı yedekleniyor..." -ForegroundColor Yellow

$dbBackup = Join-Path $BackupPath "database.sql"
$dbContainer = "personalos_transfer-postgres-1"

if (docker ps -q -f "name=$dbContainer") {
    docker exec $dbContainer pg_dumpall -U personalos > $dbBackup 2>$null
    if ($LASTEXITCODE -eq 0 -and (Test-Path $dbBackup)) {
        Write-Host "    ✓ Veritabanı yedeklendi" -ForegroundColor Green
    } else {
        Write-Host "    ✗ Veritabanı yedekleme hatası" -ForegroundColor Red
    }
} else {
    Write-Host "    ⊘ PostgreSQL çalışmıyor (atlandı)" -ForegroundColor Gray
}

# 4. Redis dump
Write-Host ""
Write-Host "[4/4] Redis verileri yedekleniyor..." -ForegroundColor Yellow

$redisBackup = Join-Path $BackupPath "redis.rdb"
$redisContainer = "personalos_transfer-redis-1"

if (docker ps -q -f "name=$redisContainer") {
    docker exec $redisContainer redis-cli SAVE 2>$null
    docker cp "$redisContainer:/data/dump.rdb" $redisBackup 2>$null
    if ($LASTEXITCODE -eq 0 -and (Test-Path $redisBackup)) {
        Write-Host "    ✓ Redis verileri yedeklendi" -ForegroundColor Green
    } else {
        Write-Host "    ✗ Redis yedekleme hatası" -ForegroundColor Red
    }
} else {
    Write-Host "    ⊘ Redis çalışmıyor (atlandı)" -ForegroundColor Gray
}

# Boyut hesapla
$backupSize = (Get-ChildItem $BackupPath -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
$backupSize = [math]::Round($backupSize, 2)

# Eski yedekleri temizle
Write-Host ""
Write-Host "[+] Eski yedekler temizleniyor (son $KeepDays gün)..." -ForegroundColor Yellow

$cutoffDate = (Get-Date).AddDays(-$KeepDays)
$oldBackups = Get-ChildItem $BackupDir -Directory | Where-Object { $_.LastWriteTime -lt $cutoffDate }

if ($oldBackups.Count -gt 0) {
    foreach ($old in $oldBackups) {
        Remove-Item $old.FullName -Recurse -Force
        Write-Host "    ⊘ Silinen: $($old.Name)" -ForegroundColor Gray
    }
    Write-Host "    ✓ $($oldBackups.Count) eski yedek silindi" -ForegroundColor Green
} else {
    Write-Host "    ✓ Silinecek eski yedek yok" -ForegroundColor Green
}

# Özet
Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Yedekleme Tamamlandı" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Yedek konumu: $BackupPath" -ForegroundColor White
Write-Host "Yedek boyutu: $backupSize MB" -ForegroundColor White
Write-Host "Son yedekleme: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host ""

# İndicators dosyası oluştur
$indicatorFile = Join-Path $BackupPath "backup_info.txt"
@"
Backup Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Backup Size: $backupSize MB
Keep Days: $KeepDays
Volumes: $($Volumes -join ', ')
"@ | Out-File $indicatorFile -Encoding UTF8

Write-Host "✓ Yedekleme başarılı!" -ForegroundColor Green

exit 0
