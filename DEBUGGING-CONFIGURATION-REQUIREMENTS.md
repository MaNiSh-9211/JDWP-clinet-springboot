# Debugging Configuration Requirements

## Overview
This document outlines all the **debugging-specific configurations** that have been added to the server project and what needs to be added/modified in a **client's project** (pulled from S3) to make it compatible with the debug client when running in a Docker container.

---

## 🔍 Current Server Project - Debugging Configurations

### 1. **Dockerfile** (`server/Dockerfile`)
**Location**: `server/Dockerfile`

**Key Debugging Configuration**:
```dockerfile
# Expose API port and JDWP port
EXPOSE 8081 5005

# Run with JDWP agent enabled
CMD ["java", "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005", "-jar", "server-app.jar"]
```

**What it does**:
- Exposes port `5005` for JDWP (Java Debug Wire Protocol) debugging
- Adds JVM argument `-agentlib:jdwp` to enable remote debugging
- Parameters:
  - `transport=dt_socket`: Uses socket transport
  - `server=y`: Application acts as server (waits for debugger to connect)
  - `suspend=n`: Application starts immediately (doesn't wait for debugger)
  - `address=*:5005`: Listens on all interfaces, port 5005

---

### 2. **pom.xml** (`server/pom.xml`)
**Location**: `server/pom.xml`

**Key Debugging Configurations**:

#### a) Maven Compiler Plugin - Debug Information
```xml
<properties>
    <maven.compiler.debug>true</maven.compiler.debug>
    <maven.compiler.debuglevel>lines,vars,source</maven.compiler.debuglevel>
</properties>
```

#### b) Maven Compiler Plugin Configuration
```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-compiler-plugin</artifactId>
    <version>3.11.0</version>
    <configuration>
        <source>21</source>
        <target>21</target>
        <debug>true</debug>
        <debuglevel>lines,vars,source</debuglevel>
    </configuration>
</plugin>
```

**What it does**:
- **CRITICAL**: Compiles Java code with full debug information (`-g` flag equivalent)
- `debuglevel=lines,vars,source` includes:
  - **lines**: Line number information (for breakpoints)
  - **vars**: Local variable information (for variable inspection)
  - **source**: Source file information
- Without this, breakpoints and variable inspection **will NOT work**

---

### 3. **docker-compose.yml** (Root Level)
**Location**: `docker-compose.yml`

**Key Debugging Configuration**:
```yaml
services:
  debug-server:
    ports:
      - "5005:5005"  # JDWP port
      - "8081:8081"  # API port
```

**What it does**:
- Maps container's JDWP port (5005) to host port (5005)
- Allows debug client to connect to the containerized application

---

### 4. **application.properties** (`server/src/main/resources/application.properties`)
**Location**: `server/src/main/resources/application.properties`

**Key Debugging Configuration**:
```properties
# Enable debug logging
logging.level.com.jdwp.server=DEBUG
```

**What it does**:
- Enables DEBUG level logging (helpful for troubleshooting, but not required for debugging)

---

## 📋 Requirements for Client Projects (S3 → Docker Container)

When you pull a client's project from S3 and run it in a Docker container, you need to add/modify the following to make it compatible with the debug client:

### ✅ **REQUIRED Changes**

#### 1. **Dockerfile** - Add JDWP Agent
**Action**: Modify or create `Dockerfile` in the client's project root

**Required Changes**:
```dockerfile
# Add JDWP port to EXPOSE
EXPOSE <your-app-port> 5005

# Modify CMD to include JDWP agent
# BEFORE (typical):
# CMD ["java", "-jar", "app.jar"]

# AFTER (with debugging):
CMD ["java", "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005", "-jar", "app.jar"]
```

**Example for Spring Boot**:
```dockerfile
FROM eclipse-temurin:21-jdk
WORKDIR /app
COPY target/your-app.jar /app/app.jar
EXPOSE 8080 5005
CMD ["java", "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005", "-jar", "app.jar"]
```

---

#### 2. **pom.xml** - Enable Debug Compilation
**Action**: Modify `pom.xml` to include debug information

**Required Changes**:

**Option A: Add to Properties Section**
```xml
<properties>
    <!-- Existing properties -->
    <maven.compiler.debug>true</maven.compiler.debug>
    <maven.compiler.debuglevel>lines,vars,source</maven.compiler.debuglevel>
</properties>
```

**Option B: Configure Maven Compiler Plugin**
```xml
<build>
    <plugins>
        <plugin>
            <groupId>org.apache.maven.plugins</groupId>
            <artifactId>maven-compiler-plugin</artifactId>
            <configuration>
                <debug>true</debug>
                <debuglevel>lines,vars,source</debuglevel>
            </configuration>
        </plugin>
    </plugins>
</build>
```

**⚠️ CRITICAL**: Without this, variables will NOT be visible in the debugger!

---

#### 3. **docker-compose.yml** - Expose JDWP Port
**Action**: Modify or create `docker-compose.yml`

**Required Changes**:
```yaml
services:
  your-app:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "<your-app-port>:<your-app-port>"  # Your application port
      - "5005:5005"  # JDWP debugging port (REQUIRED)
    # ... rest of configuration
```

**Example**:
```yaml
version: '3.8'
services:
  client-app:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: client-debug-app
    ports:
      - "8080:8080"  # Application port
      - "5005:5005"  # JDWP port
    networks:
      - debug-network
    restart: unless-stopped

networks:
  debug-network:
    driver: bridge
```

---

### ✅ **OPTIONAL Changes** (Helpful but not required)

#### 4. **application.properties** - Debug Logging
**Action**: Optional - Add debug logging for troubleshooting

```properties
logging.level.com.yourpackage=DEBUG
```

---

## 🔧 Implementation Checklist for Client Projects

When setting up a client's project for debugging:

- [ ] **1. Modify Dockerfile**
  - [ ] Add `EXPOSE 5005` to port list
  - [ ] Modify `CMD` to include `-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005`

- [ ] **2. Modify pom.xml**
  - [ ] Add `<maven.compiler.debug>true</maven.compiler.debug>`
  - [ ] Add `<maven.compiler.debuglevel>lines,vars,source</maven.compiler.debuglevel>`
  - [ ] Or configure `maven-compiler-plugin` with debug settings

- [ ] **3. Modify docker-compose.yml**
  - [ ] Add port mapping `"5005:5005"` for JDWP

- [ ] **4. Rebuild Project**
  - [ ] Run `mvn clean package` to rebuild with debug information
  - [ ] Rebuild Docker image: `docker-compose build` or `docker build -t app .`

- [ ] **5. Verify**
  - [ ] Start container: `docker-compose up -d`
  - [ ] Check container logs: `docker logs <container-name>`
  - [ ] Verify JDWP port is listening: `netstat -an | findstr 5005` (Windows) or `netstat -an | grep 5005` (Linux)

---

## 📝 Summary of Key Differences

| Component | Normal Project | Debug-Enabled Project |
|-----------|---------------|----------------------|
| **Dockerfile CMD** | `java -jar app.jar` | `java -agentlib:jdwp=... -jar app.jar` |
| **Dockerfile EXPOSE** | `<app-port>` | `<app-port> 5005` |
| **pom.xml** | No debug flags | `debug=true`, `debuglevel=lines,vars,source` |
| **docker-compose.yml** | No 5005 port | Port `5005:5005` mapping |
| **JAR Compilation** | May not have debug info | **Must** have debug info |

---

## 🚨 Common Issues and Solutions

### Issue 1: Variables Not Showing in Debugger
**Symptom**: Breakpoints work, but variables are empty or not visible

**Cause**: JAR not compiled with debug information

**Solution**: 
1. Ensure `pom.xml` has `<maven.compiler.debug>true</maven.compiler.debug>`
2. Rebuild: `mvn clean package`
3. Rebuild Docker image
4. Restart container

---

### Issue 2: Cannot Connect to Debugger
**Symptom**: Debug client cannot connect to `localhost:5005`

**Causes**:
- JDWP port not exposed in docker-compose.yml
- JDWP agent not enabled in Dockerfile CMD
- Container not running

**Solution**:
1. Check `docker-compose.yml` has `"5005:5005"` port mapping
2. Check `Dockerfile` CMD includes `-agentlib:jdwp=...`
3. Verify container is running: `docker ps`
4. Check logs: `docker logs <container-name>`

---

### Issue 3: Breakpoints Not Hitting
**Symptom**: Breakpoints set but never hit

**Causes**:
- Wrong class name or line number
- Class not loaded yet
- Code path not executed

**Solution**:
1. Verify class name matches exactly (including package)
2. Ensure line number has executable code (not blank line or comment)
3. Trigger the code path that contains the breakpoint

---

## 🔐 Security Considerations

**⚠️ IMPORTANT**: JDWP is **not encrypted** and should **NOT** be exposed in production!

For production environments:
- Use SSH tunneling: `ssh -L 5005:localhost:5005 user@remote-host`
- Use VPN
- Only enable debugging in development/staging environments
- Consider using environment variables to conditionally enable JDWP:
  ```dockerfile
  CMD ["sh", "-c", "java ${DEBUG_OPTS:--agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005} -jar app.jar"]
  ```

---

## 📚 Reference: Complete Example Dockerfile

```dockerfile
FROM eclipse-temurin:21-jdk

WORKDIR /app

# Copy JAR file
COPY target/your-app.jar /app/app.jar

# Expose application port and JDWP port
EXPOSE 8080 5005

# Run with JDWP agent enabled for remote debugging
CMD ["java", "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005", "-jar", "app.jar"]
```

---

## 📚 Reference: Complete Example pom.xml Section

```xml
<properties>
    <java.version>21</java.version>
    <maven.compiler.source>21</maven.compiler.source>
    <maven.compiler.target>21</maven.compiler.target>
    <!-- Debug information for remote debugging -->
    <maven.compiler.debug>true</maven.compiler.debug>
    <maven.compiler.debuglevel>lines,vars,source</maven.compiler.debuglevel>
</properties>

<build>
    <plugins>
        <plugin>
            <groupId>org.apache.maven.plugins</groupId>
            <artifactId>maven-compiler-plugin</artifactId>
            <configuration>
                <source>21</source>
                <target>21</target>
                <debug>true</debug>
                <debuglevel>lines,vars,source</debuglevel>
            </configuration>
        </plugin>
    </plugins>
</build>
```

---

## ✅ Verification Steps

After making changes, verify everything works:

1. **Build with debug info**:
   ```bash
   mvn clean package
   ```

2. **Build Docker image**:
   ```bash
   docker build -t client-app .
   ```

3. **Start container**:
   ```bash
   docker-compose up -d
   ```

4. **Check JDWP is listening**:
   ```bash
   # Windows
   netstat -an | findstr 5005
   
   # Linux/Mac
   netstat -an | grep 5005
   # or
   lsof -i :5005
   ```

5. **Connect from debug client**:
   - Open debug client UI
   - Connect to `localhost:5005`
   - Set a breakpoint
   - Trigger the code path
   - Verify breakpoint hits and variables are visible

---

## 🤔 Important: JAR vs Source Code - When Do You Need a Separate Container?

### Question: Is the project running as a JAR file or as source code?

This is a **critical distinction** that determines your debugging approach:

---

### ✅ **Scenario 1: Production Server Running JAR File** (Can Attach Directly)

**Situation**: Client's production server is running a **pre-built JAR file** (like `app.jar` or `application.jar`)

**Example**:
```bash
# Production server running like this:
java -jar /app/my-application.jar
```

**What You Can Do**:
- ✅ **Attach debugger directly to production server** (with required changes)
- ✅ Just add JDWP flags to the existing startup command
- ✅ **NO separate container needed**

**How to Enable**:
1. Modify the startup command to include JDWP:
   ```bash
   # BEFORE:
   java -jar /app/my-application.jar
   
   # AFTER:
   java -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005 -jar /app/my-application.jar
   ```

2. Ensure port 5005 is accessible (firewall/security group rules)

3. Connect debug client to production server's IP:5005

**⚠️ Important Requirements**:
- The JAR **MUST** be compiled with debug information (`-g` flag)
- If the JAR was built without debug info, you **CANNOT** inspect variables (only breakpoints will work)
- For full debugging (variables, etc.), you may need to rebuild the JAR with debug flags

**When This Works**:
- ✅ Production server has JAR file
- ✅ You can modify startup command (or restart with new command)
- ✅ Port 5005 can be opened/accessed
- ✅ JAR was compiled with debug information (or you can rebuild it)

---

### ✅ **Scenario 2: Source Code in Container** (Need Separate Container)

**Situation**: Client's project is **source code** that gets compiled and run inside Docker container

**Example Dockerfile**:
```dockerfile
FROM maven:3.8-openjdk-21
WORKDIR /app
COPY . .
RUN mvn clean package
CMD ["java", "-jar", "target/app.jar"]
```

**What You Need to Do**:
- ✅ **Create a separate debug container** with source code
- ✅ Modify Dockerfile to include JDWP and debug compilation
- ✅ Build and run the debug container
- ✅ Connect debug client to the debug container

**Why Separate Container?**:
- Production container may not have debug flags
- Production container may not have debug-compiled JAR
- You don't want to modify production environment
- Debug container can have different configurations

**Steps**:
1. Pull client's source code from S3
2. Create/modify Dockerfile with:
   - Debug compilation in build step
   - JDWP agent in CMD
   - Port 5005 exposed
3. Build debug container: `docker build -t client-app-debug .`
4. Run debug container: `docker run -p 5005:5005 -p 8080:8080 client-app-debug`
5. Connect debug client to `localhost:5005`

---

### 📊 Comparison Table

| Aspect | JAR File (Production) | Source Code (Container) |
|--------|----------------------|-------------------------|
| **Can attach directly?** | ✅ Yes (with JDWP flags) | ❌ No, need separate container |
| **Need separate container?** | ❌ No | ✅ Yes |
| **Modify production?** | ⚠️ Yes (startup command) | ❌ No (use debug container) |
| **Debug info in JAR?** | ⚠️ Maybe (check build) | ✅ Yes (can control) |
| **Rebuild required?** | ⚠️ Maybe (if no debug info) | ✅ Yes (always) |
| **Port access needed?** | ✅ Yes (5005) | ✅ Yes (5005) |

---

### 🔍 How to Determine Which Scenario You Have

**Check 1: Look at Dockerfile**
```dockerfile
# JAR-based (Scenario 1):
COPY target/app.jar /app/app.jar
CMD ["java", "-jar", "app.jar"]

# Source-based (Scenario 2):
COPY . .
RUN mvn clean package
CMD ["java", "-jar", "target/app.jar"]
```

**Check 2: Check Production Server**
```bash
# If you see a JAR file running:
ps aux | grep java
# Output: java -jar /app/myapp.jar

# This is Scenario 1 - can attach directly
```

**Check 3: Check Container Contents**
```bash
# Inspect running container:
docker exec -it <container> ls -la /app

# If you see .jar file → Scenario 1
# If you see src/, pom.xml, target/ → Scenario 2
```

---

### 🎯 Decision Flowchart

```
Is the application running as a JAR file?
│
├─ YES → Can you modify the startup command?
│   │
│   ├─ YES → Add JDWP flags to startup command
│   │         → Attach debugger directly ✅
│   │
│   └─ NO → Need to create debug container with JAR
│
└─ NO (Source code) → Create separate debug container
                      → Build with debug flags
                      → Run debug container
                      → Attach debugger ✅
```

---

### 💡 Best Practices

**For Production JAR (Scenario 1)**:
- ✅ Use environment variables to conditionally enable JDWP:
  ```bash
  java ${DEBUG_OPTS:--agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005} -jar app.jar
  ```
- ✅ Only enable in development/staging environments
- ✅ Use SSH tunneling for security
- ⚠️ Ensure JAR has debug information (may need rebuild)

**For Source Code (Scenario 2)**:
- ✅ Always create a separate debug container
- ✅ Never modify production container
- ✅ Use multi-stage Dockerfile to build with debug info
- ✅ Keep debug container configuration separate from production

---

### 📝 Example: Current Server Project

**Our current setup** (`server/` folder):
- ✅ **JAR-based**: Dockerfile copies `target/debug-server-1.0.0.jar`
- ✅ **Pre-built**: JAR is built before Docker build
- ✅ **Debug-enabled**: JAR compiled with debug info, JDWP in CMD

**This means**:
- If a client has a similar setup (JAR file), you can attach directly
- If a client has source code, you need to create a debug container

---

## 🎯 Quick Reference: Minimum Required Changes

For a client project to work with the debug client, you **MUST**:

1. ✅ Add JDWP agent to Dockerfile CMD (or startup command)
2. ✅ Expose port 5005 in Dockerfile (or open port in production)
3. ✅ Map port 5005 in docker-compose.yml (if using Docker)
4. ✅ Enable debug compilation in pom.xml (if rebuilding)
5. ✅ Rebuild JAR and Docker image (if source code) OR ensure existing JAR has debug info

**Remember**: 
- **JAR file** → Can attach directly (with JDWP flags)
- **Source code** → Need separate debug container

That's it! These 5 changes are the minimum required for remote debugging to work.
