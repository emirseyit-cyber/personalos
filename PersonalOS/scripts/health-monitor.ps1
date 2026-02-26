# PersonalOS Health Check & Auto-Restart Script
# Çökme ve bozulmalara karşı koruma sistemi
# Oluşturulma: 2026-02-24

param(
    [switch]$AutoRestart,
    [switch]$Silent,
    [int]$IntervalSeconds = 30
)

$ErrorActionPreference = "Continue"

# Renk kodları
$Green = "`e[32m"
$Red = "`e[31m"
$Yellow = "`e[33m"
$Blue = "`e[34m"
$Reset = "`e[0m"

# Servis listesi
$Services = @(
    @{Name="Gateway"; Port=8080; Endpoint="/health"},
    @{Name="WhatsApp-Adapter"; Port=3000; Endpoint="/health"},
    @{Name="Telegram-Adapter"; Port=3002; Endpoint="/health"},
    @{Name="Email-Adapter"; Port=3003; Endpoint="/health"},
    @{Name="WhatsApp-Worker"; Port=9101; Endpoint="/metrics"},
    @{Name="Telegram-Worker"; Port=9102; Endpoint="/metrics"},
    @{Name="Email-Worker"; Port=9103; Endpoint="/metrics"},
    @{Name="Agent"; Port=8081; Endpoint="/health"},
    @{Name="Dispatcher"; Port=9400; Endpoint="/health"},
    @{Name="UI"; Port=8088; Endpoint="/health"},
    @{Name="PostgreSQL"; Port=5432; Endpoint=""},
    @{Name="Redis"; Port=6379; Endpoint=""},
    @{Name="Prometheus"; Port=9090; Endpoint=""},
    @{Name="Grafana"; Port=3001; Endpoint=""},
    @{Name="Vault"; Port=8200; Endpoint=""},
    @{Name="MinIO"; Port=9000; Endpoint=""},
    @{Name="Mailhog"; Port=8025; Endpoint=""},
    @{Name="Portainer"; Port=9443; Endpoint=""}
)

function Write-Status {
    param($Message, $Type = "info")
    if (-not $Silent) {
        switch ($Type) {
            "ok" { Write-Host "${Green}✓${Reset} $Message" -ForegroundColor Green }
            "error" { Write-Host "${Red}✗${Reset} $Message" -ForegroundColor Red }
            "warn" { Write-Host "${Yellow}⚠${Reset} $Message" -ForegroundColor Yellow }
            "info" { Write-Host "${Blue}ℹ${Reset} $Message" -ForegroundColor Cyan }
        }
    }
}

function Test-ServiceHealth {
    param($Service)
    
    # Önce Docker container kontrolü
    $containerName = "personalos_transfer-$($Service.Name.ToLower())-1"
    $containerName = $containerName -replace "-adapter", "-adapter" -replace "-worker", "-worker"
    
    $dockerStatus = docker ps --filter "name=$($Service.Name.ToLower())" --format "{{.Names}}" 2>$null
    if ($dockerStatus -notmatch $Service.Name) {
        return @{Status="down"; Reason="Container not running"; Container=$null}
    }
    
    # Port kontrolü
    try {
        $tcpTest = Test-NetConnection -ComputerName "localhost" -Port $Service.Port -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if (-not $tcpTest.TcpTestSucceeded) {
            return @{Status="down"; Reason="Port $($Service.Port) not accessible"; Container=$dockerStatus}
        }
    } catch {
        return @{Status="down"; Reason="Port test failed"; Container=$dockerStatus}
    }
    
    # HTTP endpoint kontrolü (varsa)
    if ($Service.Endpoint) {
        try {
            $url = "http://localhost:$($Service.Port)$($Service.Endpoint)"
            $response = Invoke-WebRequest -Uri $url -TimeoutSec 5 -UseBasicParsing -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                return @{Status="ok"; Reason="Healthy"; Container=$dockerStatus}
            } else {
                return @{Status="degraded"; Reason="HTTP $($response.StatusCode)"; Container=$dockerStatus}
            }
        } catch {
            return @{Status="degraded"; Reason="HTTP request failed"; Container=$dockerStatus}
        }
    }
    
    return @{Status="ok"; Reason="Port open"; Container=$dockerStatus}
}

function Restart-Service {
    param($Service)
    
    Write-Status "Restarting $($Service.Name)..." "warn"
    
    $composeFile = "D:\OpenCode\PersonalOS\docker-compose.yml"
    if (Test-Path $composeFile) {
        Push-Location "D:\OpenCode\PersonalOS"
        docker compose restart $Service.Name 2>$null
        Pop-Location
        Write-Status "$($Service.Name) restarted" "info"
    }
}

function Get-SystemStats {
    $cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue).CounterSamples.CookedValue
    $memory = (Get-Counter '\Memory\% Committed Bytes In Use' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue).CounterSamples.CookedValue
    $disk = (Get-Counter '\LogicalDisk(C:)\% Free Space' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue).CounterSamples.CookedValue
    
    return @{
        CPU = [math]::Round($cpu, 1)
        Memory = [math]::Round($memory, 1)
        Disk = [math]::Round($disk, 1)
    }
}

function Start-Monitoring {
    Write-Status "PersonalOS Health Monitor başlatıldı" "info"
    Write-Status "Otomatik yeniden başlatma: $(if($AutoRestart){'AÇIK'}else{'KAPALI'})" "info"
    Write-Status "Kontrol aralığı: $IntervalSeconds saniye" "info"
    Write-Host ""
    
    $failCount = @{}
    $maxFailBeforeRestart = 3
    
    while ($true) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $stats = Get-SystemStats
        
        if (-not $Silent) {
            Clear-Host
            Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host "  PersonalOS Health Monitor" -ForegroundColor Cyan
            Write-Host "  $timestamp" -ForegroundColor Gray
            Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host "CPU: $($stats.CPU)% | RAM: $($stats.Memory)% | Disk: $($stats.Disk)%" -ForegroundColor Gray
            Write-Host ""
        }
        
        $totalServices = $Services.Count
        $healthyServices = 0
        $downServices = @()
        
        foreach ($service in $Services) {
            $health = Test-ServiceHealth -Service $service
            
            if ($health.Status -eq "ok") {
                $healthyServices++
                Write-Status "$($service.Name) - OK" "ok"
                
                # Başarılı = sayacı sıfırla
                $failCount[$service.Name] = 0
            } else {
                $currentFail = $failCount[$service.Name] + 1
                $failCount[$service.Name] = $currentFail
                $downServices += $service
                
                Write-Status "$($service.Name) - $($health.Reason)" "error"
                
                # Otomatik yeniden başlatma
                if ($AutoRestart -and $currentFail -ge $maxFailBeforeRestart) {
                    Restart-Service -Service $service
                    $failCount[$service.Name] = 0
                }
            }
        }
        
        Write-Host ""
        Write-Host "Durum: $healthyServices / $totalServices sağlıklı" -ForegroundColor $(if($healthyServices -eq $totalServices){"Green"}else{"Yellow"})
        
        if ($downServices.Count -gt 0) {
            Write-Host "Sorunlu servisler: $($downServices.Name -join ', ')" -ForegroundColor Red
        }
        
        Start-Sleep -Seconds $IntervalSeconds
    }
}

function Test-DockerRunning {
    try {
        docker ps > $null 2>&1
        return $true
    } catch {
        return $false
    }
}

# Ana mantık
if (-not (Test-DockerRunning)) {
    Write-Status "Docker çalışmıyor! Lütfen Docker Desktop'ı başlatın." "error"
    exit 1
}

# Tek seferlik kontrol veya sürekli izleme
if ($AutoRestart -or $IntervalSeconds -ne 30) {
    Start-Monitoring
} else {
    # Tek seferlik sağlık kontrolü
    Write-Host "PersonalOS Sağlık Kontrolü" -ForegroundColor Cyan
    Write-Host "===========================" -ForegroundColor Cyan
    Write-Host ""
    
    $totalServices = $Services.Count
    $healthyServices = 0
    
    foreach ($service in $Services) {
        $health = Test-ServiceHealth -Service $service
        if ($health.Status -eq "ok") {
            $healthyServices++
            Write-Status "$($service.Name) - OK" "ok"
        } else {
            Write-Status "$($service.Name) - $($health.Reason)" "error"
        }
    }
    
    Write-Host ""
    Write-Host "===========================" -ForegroundColor Cyan
    Write-Host "Sonuç: $healthyServices / $totalServices servis sağlıklı"
    
    if ($healthyServices -eq $totalServices) {
        exit 0
    } else {
        exit 1
    }
}
