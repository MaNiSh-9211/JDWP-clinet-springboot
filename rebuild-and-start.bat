@echo off
setlocal enabledelayedexpansion
echo ========================================
echo Rebuilding and Starting JDWP Debug Project
echo ========================================
echo.

REM Set Java environment
set JAVA_HOME=C:\Program Files\Java\jdk-21
set PATH=%JAVA_HOME%\bin;%PATH%

REM Step 1: Kill existing processes
echo [1/8] Cleaning up existing processes...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr :8082') do (
    taskkill /F /PID %%a >nul 2>&1
)
taskkill /F /IM java.exe /T >nul 2>&1
echo    Done.

REM Step 2: Build Server
echo [2/8] Building Server JAR...
cd server
call mvn clean package -DskipTests
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Server build failed!
    cd ..
    pause
    exit /b 1
)
cd ..

REM Step 3: Docker Reset
echo [3/8] Resetting Docker...
docker-compose down --volumes --remove-orphans >nul 2>&1
echo    Done.

REM Step 4: Docker Build (Force No Cache)
echo [4/8] Building Docker Image (No Cache)...
docker-compose build --no-cache
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Docker build failed!
    pause
    exit /b 1
)
echo    Done.

REM Step 5: Start Docker
echo [5/8] Starting Docker Containers...
docker-compose up -d
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Docker up failed!
    pause
    exit /b 1
)
echo    Done.

REM Step 6: Build UI & Client
echo [6/8] Building UI and Client Application...
cd client\ui
echo    - Installing UI dependencies (this may take a while)...
call npm install
echo    - Building UI...
call npm run build
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] UI build failed!
    cd ..\..
    pause
    exit /b 1
)
cd ..
echo    - Building Client JAR...
call mvn clean package -DskipTests
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Client build failed!
    cd ..
    pause
    exit /b 1
)
cd ..

REM Step 7: Final Health Check
echo [7/8] Waiting for Server Health Check...
set WAIT_COUNT=0
:server_wait
powershell -Command "try { $r = Invoke-WebRequest -Uri 'http://localhost:8081/health' -UseBasicParsing; exit 0 } catch { exit 1 }" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo    ✓ Server is UP!
    goto server_ready
)
set /a WAIT_COUNT+=1
if %WAIT_COUNT% GEQ 30 (
    echo [WARNING] Server health check timed out.
    goto server_ready
)
timeout /t 1 >nul
goto server_wait
:server_ready

REM Step 8: Start Client
echo [8/8] Starting Client...
start "JDWP Debug Client" cmd /k "cd /d client && set JAVA_HOME=%JAVA_HOME% && set PATH=%JAVA_HOME%\bin;%PATH% && java -jar target\debug-client-1.0.0.jar"

echo.
echo ========================================
echo BUILD COMPLETE AND SERVICES STARTED
echo ========================================
echo Client UI: http://localhost:8082
echo Server API: http://localhost:8081
echo ========================================
echo.
pause
