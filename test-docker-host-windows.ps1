### Docker Host Connectivity Test (Windows / PowerShell)
### Run: powershell -ExecutionPolicy Bypass -File test-docker-host-windows.ps1

$ErrorActionPreference = "Stop"

Write-Host "=== Docker Host Connectivity Test (Windows) ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check Docker is running
try {
    docker info 2>$null | Out-Null
    Write-Host "[PASS] Docker is running" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Docker is not running. Please start Docker Desktop first." -ForegroundColor Red
    exit 1
}

# Step 2: Make sure index.html exists
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

if (-not (Test-Path "index.html")) {
    "hello from host" | Out-File -Encoding ascii -NoNewline "index.html"
    # Append a newline
    Add-Content -Path "index.html" -Value ""
}

# Step 3: Start HTTP server in background
Write-Host "Starting HTTP server on port 8000..." -ForegroundColor Yellow

# Check if port 8000 is already in use
$portInUse = Get-NetTCPConnection -LocalPort 8000 -ErrorAction SilentlyContinue
if ($portInUse) {
    Write-Host "[WARN] Port 8000 is already in use. Attempting to use it anyway..." -ForegroundColor Yellow
}

$serverJob = Start-Job -ScriptBlock {
    param($dir)
    Set-Location $dir
    python -m http.server 8000 2>&1
} -ArgumentList $ScriptDir

Start-Sleep -Seconds 2

# Verify server is running
if ($serverJob.State -eq "Failed") {
    Write-Host "[FAIL] Failed to start HTTP server." -ForegroundColor Red
    Remove-Job $serverJob -Force
    exit 1
}
Write-Host "[PASS] HTTP server started (Job ID: $($serverJob.Id))" -ForegroundColor Green

# Cleanup function
function Cleanup {
    Write-Host ""
    Write-Host "Stopping HTTP server..." -ForegroundColor Yellow
    Stop-Job $serverJob -ErrorAction SilentlyContinue
    Remove-Job $serverJob -Force -ErrorAction SilentlyContinue
    Write-Host "[PASS] Cleanup done" -ForegroundColor Green
}

try {
    # Step 4: Test from host first
    Write-Host ""
    Write-Host "--- Test 1: curl from host (localhost:8000) ---"
    try {
        $hostResult = (Invoke-WebRequest -Uri "http://localhost:8000/" -UseBasicParsing -TimeoutSec 5).Content.Trim()
        if ($hostResult -eq "hello from host") {
            Write-Host "[PASS] Host test passed: $hostResult" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Host test failed. Got: $hostResult" -ForegroundColor Red
        }
    } catch {
        Write-Host "[FAIL] Host test failed: $_" -ForegroundColor Red
    }

    # Step 5: Test from Docker container (Docker Desktop handles host.docker.internal)
    Write-Host ""
    Write-Host "--- Test 2: curl from Docker container via host.docker.internal ---"
    try {
        $dockerResult = (docker run --rm curlimages/curl:latest -s http://host.docker.internal:8000/ 2>$null).Trim()
        if ($dockerResult -eq "hello from host") {
            Write-Host "[PASS] Docker container -> host test passed: $dockerResult" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Docker container -> host test failed. Got: $dockerResult" -ForegroundColor Red
        }
    } catch {
        Write-Host "[FAIL] Docker container -> host test failed: $_" -ForegroundColor Red
    }

    # Step 6: Test with Docker Compose
    Write-Host ""
    Write-Host "--- Test 3: Docker Compose test ---"
    if (Test-Path "docker-compose.yml") {
        try {
            $composeResult = (docker compose run --rm test 2>$null).Trim()
            if ($composeResult -eq "hello from host") {
                Write-Host "[PASS] Docker Compose -> host test passed: $composeResult" -ForegroundColor Green
            } else {
                Write-Host "[FAIL] Docker Compose -> host test failed. Got: $composeResult" -ForegroundColor Red
            }
        } catch {
            Write-Host "[FAIL] Docker Compose -> host test failed: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "[WARN] docker-compose.yml not found, skipping" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "=== All tests complete ===" -ForegroundColor Cyan

} finally {
    Cleanup
}
