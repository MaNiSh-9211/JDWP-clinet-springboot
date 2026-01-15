# 🏗️ Project Architecture

## Overview

This repository contains **two separate projects**:

1. **Example Project** (`server/`) - A sample application that gets debugged
2. **Debugger Client** (`client/`) - The debugging tool with web UI

## Component Details

### 1. Example Project (`server/`)

**Purpose**: This is a **standalone example application** that demonstrates how any Java application can be debugged remotely when running in Docker.

**What it contains**:
- Spring Boot REST API application
- User CRUD operations
- Runs inside Docker container
- Has JDWP enabled for remote debugging

**Key Files**:
- `src/main/java/com/jdwp/server/` - Application source code
- `Dockerfile` - Container definition with JDWP enabled
- `pom.xml` - Maven dependencies

**In Production**:
- This would be **your actual application**
- It would likely be in a **separate repository**
- You would replace this with your own project

**See**: `server/README.md` for more details

---

### 2. Debugger Client (`client/`)

**Purpose**: This is the **main debugging tool** that:
- Connects to Java applications in Docker via JDWP
- Provides a web-based UI for debugging
- Manages breakpoints, threads, variables, and step operations

**What it contains**:

#### Backend (`src/main/java/`)
- **JdwpService**: Core JDWP client using JDI (Java Debug Interface)
- **DebugController**: REST API for debugging operations
- **ServerApiController**: Proxies requests to the example project
- **WebController**: Serves the React UI

#### Frontend (`ui/`)
- **React 18** application
- **Vite** build tool
- Web UI for all debugging operations

**Key Features**:
- Connect/disconnect to JDWP servers
- Set/remove breakpoints
- View threads and stack frames
- Inspect variables
- Step over/into/out
- Test API endpoints
- View debug logs

**See**: `client/README.md` for more details

---

## How They Work Together

### Step 1: Build and Start Example Project
```bash
# Build the example project
cd server
mvn clean package

# Build Docker image
docker build -t debug-server .

# Run with JDWP enabled
docker run -p 8081:8081 -p 5005:5005 debug-server
```

### Step 2: Start Debugger Client
```bash
# Build UI
cd client/ui
npm install
npm run build

# Build and run client
cd ..
mvn clean package
java -jar target/debug-client-1.0.0.jar
```

### Step 3: Debug
1. Open `http://localhost:8082` in browser
2. Click "Connect" (connects to `localhost:5005`)
3. Set breakpoints in the example project
4. Call API endpoints to hit breakpoints
5. Inspect variables and step through code

---

## Data Flow

```
┌──────────────┐
│   Browser    │
│  (Port 8082) │
└──────┬───────┘
       │
       │ HTTP REST API
       │
       ▼
┌─────────────────────────────────────┐
│  Debugger Client (client/)          │
│  ┌───────────────────────────────┐  │
│  │  React UI                     │  │
│  │  - Breakpoint management      │  │
│  │  - Thread viewer              │  │
│  │  - Variable inspector         │  │
│  │  - API tester                 │  │
│  └───────────┬───────────────────┘  │
│              │                       │
│  ┌───────────▼───────────────────┐  │
│  │  Spring Boot Backend          │  │
│  │  - DebugController (REST API)  │  │
│  │  - JdwpService (JDI client)    │  │
│  └───────────┬───────────────────┘  │
└──────────────┼───────────────────────┘
               │
               │ JDWP Protocol
               │ (Port 5005)
               │
               ▼
┌─────────────────────────────────────┐
│  Docker Container                   │
│  ┌───────────────────────────────┐  │
│  │  Example Project (server/)    │  │
│  │  - Spring Boot App             │  │
│  │  - REST API (Port 8081)        │  │
│  │  - JDWP Agent (Port 5005)      │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

---

## Ports

| Component | Port | Purpose |
|-----------|------|---------|
| Example Project API | 8081 | REST API endpoints |
| Example Project JDWP | 5005 | JDWP debugging protocol |
| Debugger Client | 8082 | Web UI and REST API |

---

## Using Your Own Project

To debug your own Java application:

1. **Replace `server/` with your project**:
   - Your project must be buildable into a JAR
   - Your project must have a `Dockerfile`

2. **Update Dockerfile** to enable JDWP:
   ```dockerfile
   CMD ["java", "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005", "-jar", "your-app.jar"]
   ```

3. **Update `docker-compose.yml`**:
   ```yaml
   services:
     debug-server:
       build:
         context: ./your-project  # Point to your project
   ```

4. **The debugger client (`client/`)** works with any JDWP-enabled application - no changes needed!

---

## Summary

- **`server/`** = Example project (replace with your app)
- **`client/`** = Debugger tool (works with any JDWP app)
- They are **independent** - the client can debug any Java app in Docker with JDWP enabled
