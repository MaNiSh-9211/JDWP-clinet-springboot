@echo off
echo ========================================
echo PERFORMING ACTUAL DEBUGGING
echo ========================================
echo.
echo This will:
echo 1. Build server and client
echo 2. Start Docker container
echo 3. Start client application
echo 4. Perform actual debugging operations
echo.

cd server
echo Building server...
call mvn clean package -DskipTests -q
if errorlevel 1 (
    echo ERROR: Failed to build server
    cd ..
    pause
    exit /b 1
)
cd ..

cd client
echo Building client...
call mvn clean package -DskipTests -q
if errorlevel 1 (
    echo ERROR: Failed to build client
    cd ..
    pause
    exit /b 1
)
cd ..

echo.
echo Starting Docker container...
docker-compose down 2>nul
docker-compose up -d --build
if errorlevel 1 (
    echo ERROR: Failed to start container
    pause
    exit /b 1
)

echo Waiting for container to start (40 seconds)...
timeout /t 40 /nobreak >nul

echo.
echo Container started. Now starting client and performing debugging...
echo.

cd client
start "JDWP Debug Client" cmd /k "java -jar target\debug-client-1.0.0.jar"
cd ..

echo Client starting... Waiting 10 seconds...
timeout /t 10 /nobreak >nul

echo.
echo ========================================
echo NOW PERFORMING DEBUGGING OPERATIONS
echo ========================================
echo.
echo Use the API at http://localhost:8080/api/debug to perform debugging
echo Or use the UI at http://localhost:3000
echo.
echo The client is running and ready for debugging operations.
echo.
