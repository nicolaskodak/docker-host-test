@echo off
REM ============================================================
REM Docker Host Connectivity Test (Windows / CMD)
REM ============================================================
REM
REM Prerequisites:
REM   1. Docker Desktop for Windows installed and running
REM      - Download: https://docs.docker.com/desktop/install/windows-install/
REM      - Must be running (check system tray icon)
REM   2. Python 3 installed and added to PATH
REM      - Download: https://www.python.org/downloads/
REM      - During install, check "Add Python to PATH"
REM      - Verify: python --version
REM   3. curl available (built-in on Windows 10 1803+)
REM      - Verify: curl --version
REM   4. Run this script from the directory containing index.html
REM      - cd path\to\docker-host-test
REM      - test-docker-host-windows.bat
REM   5. Port 8000 must be available
REM      - Check: netstat -an | findstr :8000
REM   6. Windows Firewall may need to allow:
REM      - Python through firewall (prompted on first run)
REM      - Docker Desktop networking (usually configured automatically)
REM
REM ============================================================

echo === Docker Host Connectivity Test (Windows / CMD) ===
echo.

REM --- Check Docker ---
docker info >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [FAIL] Docker is not running. Please start Docker Desktop first.
    exit /b 1
)
echo [PASS] Docker is running

REM --- Ensure index.html exists ---
if not exist index.html (
    echo hello from host> index.html
)

REM --- Start HTTP server in background ---
echo Starting HTTP server on port 8000...
start /b "" python -m http.server 8000 >nul 2>&1
timeout /t 2 /nobreak >nul

REM Verify server is reachable
curl -s http://localhost:8000/ >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [FAIL] Failed to start HTTP server. Port 8000 might be in use.
    exit /b 1
)
echo [PASS] HTTP server started

REM === Test 1: curl from host ===
echo.
echo --- Test 1: curl from host (localhost:8000) ---
for /f "delims=" %%i in ('curl -s http://localhost:8000/') do set "HOST_RESULT=%%i"
if "%HOST_RESULT%"=="hello from host" (
    echo [PASS] Host test passed: %HOST_RESULT%
) else (
    echo [FAIL] Host test failed. Got: %HOST_RESULT%
    goto :cleanup
)

REM === Test 2: Docker container via host.docker.internal ===
echo.
echo --- Test 2: curl from Docker container via host.docker.internal ---
for /f "delims=" %%i in ('docker run --rm curlimages/curl:latest -s http://host.docker.internal:8000/ 2^>nul') do set "DOCKER_RESULT=%%i"
if "%DOCKER_RESULT%"=="hello from host" (
    echo [PASS] Docker container -^> host test passed: %DOCKER_RESULT%
) else (
    echo [FAIL] Docker container -^> host test failed. Got: %DOCKER_RESULT%
)

REM === Test 3: Docker Compose ===
echo.
echo --- Test 3: Docker Compose test ---
if exist docker-compose.yml (
    for /f "delims=" %%i in ('docker compose run --rm test 2^>nul') do set "COMPOSE_RESULT=%%i"
    if "!COMPOSE_RESULT!"=="hello from host" (
        echo [PASS] Docker Compose -^> host test passed: !COMPOSE_RESULT!
    ) else (
        echo [FAIL] Docker Compose -^> host test failed. Got: !COMPOSE_RESULT!
    )
) else (
    echo [WARN] docker-compose.yml not found, skipping
)

:cleanup
echo.
echo Stopping HTTP server...
for /f "tokens=5" %%p in ('netstat -ano ^| findstr :8000 ^| findstr LISTENING') do (
    taskkill /PID %%p /F >nul 2>&1
)
echo [PASS] Cleanup done
echo.
echo === All tests complete ===
