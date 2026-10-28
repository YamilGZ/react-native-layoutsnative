#Requires -Version 5.1
$ErrorActionPreference = 'SilentlyContinue'
$ConfirmPreference = 'None'
$ProgressPreference = 'SilentlyContinue'
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "    INICIANDO APP LAYOUTSNATIVE (React Native)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ---------- Funciones de utilidad ----------

function Test-PortInUse {
    param([int]$Port)
    $connections = netstat -ano 2>$null | Select-String ":$Port\s"
    return ($connections.Count -gt 0)
}

function Stop-ProcessOnPort {
    param([int]$Port)
    $listeners = netstat -ano 2>$null | Select-String ":$Port\s+.*LISTENING"
    if ($listeners) {
        foreach ($line in $listeners) {
            $parts = ($line -split '\s+') | Where-Object { $_ -ne "" }
            $procId = $parts[-1]
            if ($procId -match '^\d+$') {
                try {
                    $proc = Get-Process -Id $procId -ErrorAction Stop
                    Write-Host "  Cerrando proceso PID $procId ($($proc.ProcessName)) en puerto $Port..." -ForegroundColor Yellow
                    Stop-Process -Id $procId -Force -ErrorAction Stop
                } catch {
                    Write-Host "  No se pudo cerrar PID $procId : $_" -ForegroundColor Red
                }
            }
        }
    }
}

function Wait-ForMetro {
    param([int]$TimeoutSeconds = 45)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    Write-Host "Esperando que Metro responda" -ForegroundColor Cyan -NoNewline
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            $null = Invoke-WebRequest -Uri "http://localhost:8081" -Method GET -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
            Write-Host " OK!" -ForegroundColor Green
            return $true
        } catch {
            Start-Sleep -Milliseconds 800
            Write-Host "." -ForegroundColor Cyan -NoNewline
        }
    }
    Write-Host ""
    return $false
}

function Wait-ForDevice {
    param([int]$TimeoutSeconds = 120)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    Write-Host "Esperando emulador/dispositivo" -ForegroundColor Cyan -NoNewline
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $device = adb devices 2>$null | Select-String "device$"
        if ($device -and -not ($device -match "offline")) {
            Write-Host " OK!" -ForegroundColor Green
            return $true
        }
        Start-Sleep -Seconds 1
        Write-Host "." -ForegroundColor Cyan -NoNewline
    }
    Write-Host ""
    return $false
}

function Start-EmulatorIfNeeded {
    param([int]$TimeoutSeconds = 180)

    Write-Host "`n[2/7] Verificando dispositivo Android..." -ForegroundColor Green

    # Verificar si ya hay un dispositivo conectado
    $device = adb devices 2>$null | Select-String "device$"
    if ($device -and -not ($device -match "offline")) {
        Write-Host "  Dispositivo/emulador ya conectado." -ForegroundColor Green
        return $true
    }

    Write-Host "  No se detecto dispositivo. Buscando emuladores..." -ForegroundColor Yellow

    # Listar AVDs disponibles
    $avds = emulator -list-avds 2>$null
    if (-not $avds) {
        Write-Host "  No hay emuladores (AVDs) configurados." -ForegroundColor Red
        Write-Host "  Crea uno desde Android Studio: Tools > Device Manager > Create Device" -ForegroundColor Yellow
        return $false
    }

    # Usar el primer AVD disponible
    $avdName = ($avds | Select-Object -First 1).Trim()
    Write-Host "  Iniciando emulador: $avdName ..." -ForegroundColor Yellow

    # Iniciar emulador en segundo plano
    Start-Process -FilePath "emulator" -ArgumentList "-avd", $avdName, "-no-snapshot-load" -WindowStyle Normal

    # Esperar a que adb lo detecte
    Write-Host "  Esperando que el emulador bootee" -ForegroundColor Cyan -NoNewline
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Start-Sleep -Seconds 2
        $device = adb devices 2>$null | Select-String "device$"
        if ($device -and -not ($device -match "offline")) {
            Write-Host " OK!" -ForegroundColor Green
            # Esperar un poco mas para que el sistema termine de cargar
            Write-Host "  Esperando sistema Android..." -ForegroundColor Cyan -NoNewline
            Start-Sleep -Seconds 5
            Write-Host " Listo!" -ForegroundColor Green
            return $true
        }
        Write-Host "." -ForegroundColor Cyan -NoNewline
    }

    Write-Host ""
    Write-Host "  El emulador no inicio a tiempo." -ForegroundColor Red
    return $false
}

# ---------- PASO 1: Cerrar Metro anterior ----------
Write-Host "`n[1/7] Verificando puerto 8081..." -ForegroundColor Green
if (Test-PortInUse -Port 8081) {
    Stop-ProcessOnPort -Port 8081
    Start-Sleep -Seconds 2
    if (Test-PortInUse -Port 8081) {
        Write-Host "  El puerto sigue ocupado. Puede haber problemas." -ForegroundColor Red
    } else {
        Write-Host "  Puerto 8081 liberado." -ForegroundColor Green
    }
} else {
    Write-Host "  Puerto 8081 libre." -ForegroundColor Green
}

# ---------- PASO 2: Verificar / iniciar emulador ----------
$emulatorOk = Start-EmulatorIfNeeded
if (-not $emulatorOk) {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "    ERROR: No se pudo iniciar emulador" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    exit 1
}

# ---------- PASO 3: Cerrar app anterior ----------
Write-Host "`n[3/7] Cerrando app anterior..." -ForegroundColor Green
adb shell am force-stop com.layoutsnative 2>$null
Start-Sleep -Seconds 1
Write-Host "  App cerrada." -ForegroundColor Green

# ---------- PASO 4: Limpiar cache de la app ----------
Write-Host "`n[4/7] Limpiando cache de la app..." -ForegroundColor Green
adb shell pm clear com.layoutsnative 2>$null
Write-Host "  Cache limpiado." -ForegroundColor Green

# ---------- PASO 5: Iniciar Metro en ventana separada ----------
Write-Host "`n[5/7] Iniciando Metro bundler..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit","-ExecutionPolicy","Bypass","-Command","Set-Location '$PWD'; npx react-native start" -WindowStyle Normal

# Esperar a que Metro realmente responda
$metroOk = Wait-ForMetro -TimeoutSeconds 45
if (-not $metroOk) {
    Write-Host "  Metro no respondio a tiempo." -ForegroundColor Red
    Write-Host "  Cerrando e intentando de nuevo..." -ForegroundColor Yellow
    exit 1
}

# ---------- PASO 6: Compilar e instalar ----------
Write-Host "`n[6/7] Compilando e instalando APK..." -ForegroundColor Green

# Intentar con --no-packager para que use el Metro que ya levantamos
try {
    npx react-native run-android --no-packager
} catch {
    Write-Host "  Error con --no-packager, intentando sin flag..." -ForegroundColor Yellow
    npx react-native run-android
}

# ---------- PASO 7: Forzar recarga limpia ----------
Write-Host "`n[7/7] Reiniciando app para conexion limpia..." -ForegroundColor Green
Start-Sleep -Seconds 3
adb shell am force-stop com.layoutsnative 2>$null
Start-Sleep -Seconds 1
adb shell am start -n com.layoutsnative/.MainActivity

Start-Sleep -Seconds 2
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "    APP INICIADA - Metro en otra ventana" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Presiona 'r' en la ventana de Metro para recargar" -ForegroundColor Yellow
Write-Host "Presiona 'j' en la ventana de Metro para DevTools" -ForegroundColor Yellow
