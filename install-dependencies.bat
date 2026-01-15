@echo off
echo ========================================
echo Installing Dependencies for JDWP Debug Project
echo ========================================
echo.

echo [1/3] Installing Server Dependencies...
cd server
if exist "target" (
    echo Server already built. Skipping...
) else (
    echo Building server with Maven...
    call mvn clean package
    if errorlevel 1 (
        echo ERROR: Failed to build server
        cd ..
        pause
        exit /b 1
    )
)
cd ..
echo Server dependencies installed successfully!
echo.

echo [2/3] Installing Client Dependencies...
cd client
if exist "target" (
    echo Client already built. Skipping...
) else (
    echo Building client with Maven...
    call mvn clean install
    if errorlevel 1 (
        echo ERROR: Failed to build client
        cd ..
        pause
        exit /b 1
    )
)
cd ..
echo Client dependencies installed successfully!
echo.

echo [3/3] Installing UI Dependencies...
cd client\ui
if exist "node_modules" (
    echo UI dependencies already installed. Skipping...
) else (
    echo Installing UI dependencies with npm...
    call npm install
    if errorlevel 1 (
        echo ERROR: Failed to install UI dependencies
        cd ..\..
        pause
        exit /b 1
    )
)
cd ..\..
echo UI dependencies installed successfully!
echo.

echo ========================================
echo All dependencies installed successfully!
echo ========================================
pause

