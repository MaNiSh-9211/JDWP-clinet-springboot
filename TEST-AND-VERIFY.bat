@echo off
echo ========================================
echo Testing JDWP Debug Setup
echo ========================================
echo.

REM Set Java environment
set JAVA_HOME=C:\Program Files\Java\jdk-21
set PATH=%JAVA_HOME%\bin;%PATH%

echo [1/4] Testing Java/JDK setup...
java -version
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Java not found
    pause
    exit /b 1
)
javac -version
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: javac not found - JAVA_HOME might point to JRE instead of JDK
    echo Current JAVA_HOME: %JAVA_HOME%
    pause
    exit /b 1
)
echo    ✓ Java and javac found

echo.
echo [2/4] Testing server build with debug info...
cd server
call mvn clean package -DskipTests 2>&1 | findstr /i "debug\|compiling\|BUILD"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Server build failed
    cd ..
    pause
    exit /b 1
)
if exist target\debug-server-1.0.0.jar (
    echo    ✓ Server JAR built successfully
    echo    JAR location: server\target\debug-server-1.0.0.jar
    echo    JAR size: 
    dir target\debug-server-1.0.0.jar | findstr debug-server
) else (
    echo    ERROR: JAR file not found!
    cd ..
    pause
    exit /b 1
)
cd ..

echo.
echo [3/4] Verifying pom.xml has debug configuration...
findstr /i "debug.*true\|debuglevel.*vars" server\pom.xml > nul
if %ERRORLEVEL% EQU 0 (
    echo    ✓ pom.xml has debug configuration
) else (
    echo    WARNING: Could not verify debug configuration in pom.xml
)

echo.
echo [4/4] Summary:
echo    - Java/JDK: OK
echo    - Server build: OK
echo    - Debug config: Checked
echo.
echo Next steps:
echo    1. Run rebuild-and-start.bat to rebuild Docker and start everything
echo    2. Connect to debugger and set breakpoints
echo    3. Variables should now be visible
echo.
pause
