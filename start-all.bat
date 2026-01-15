@echo off
echo ========================================
echo Starting JDWP Debug Project
echo ========================================
echo.

REM Check if server JAR exists
if not exist "server\target\debug-server-1.0.0.jar" (
    echo ERROR: Server JAR not found. Please run install-dependencies.bat first.
    pause
    exit /b 1
)

REM Check if client JAR exists
if not exist "client\target\debug-client-1.0.0.jar" (
    echo ERROR: Client JAR not found. Please run install-dependencies.bat first.
    pause
    exit /b 1
)

REM Check if UI node_modules exists
if not exist "client\ui\node_modules" (
    echo ERROR: UI dependencies not found. Please run install-dependencies.bat first.
    pause
    exit /b 1
)

echo Starting Spring Boot Client (Backend)...
start "JDWP Debug Client" cmd /k "cd client && java -jar target\debug-client-1.0.0.jar"

REM Wait a bit for backend to start
timeout /t 3 /nobreak >nul

echo Starting React UI (Frontend)...
start "JDWP Debug UI" cmd /k "cd client\ui && npm run start"

echo.
echo ========================================
echo Services started!
echo ========================================
echo Backend API: http://localhost:8080
echo Frontend UI: http://localhost:3000
echo.
echo Note: Make sure to start the Docker container with the server first!
echo Run: docker-compose up (or docker run command)
echo.
pause

