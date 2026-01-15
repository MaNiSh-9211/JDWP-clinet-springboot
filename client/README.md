# JDWP Debugger Client

## 📋 Purpose

This is the **debugger client application** that:
- Connects to Java applications running in Docker containers via JDWP
- Provides a web-based UI for debugging operations
- Manages breakpoints, thread control, variable inspection, and step operations

## 🎯 What This Project Is

This is a **Spring Boot application** that acts as a JDWP client using JDI (Java Debug Interface). It provides:

1. **Backend (Spring Boot)**:
   - JDWP connection management
   - Breakpoint management
   - Thread control (suspend/resume)
   - Stack frame inspection
   - Variable inspection
   - Step operations (step over, step into, step out)
   - REST API for the frontend

2. **Frontend (React UI)**:
   - Web-based debugging interface
   - Visual breakpoint management
   - Thread and stack frame viewer
   - Variable inspector
   - API endpoint tester
   - Real-time debug logs

## 🏗️ Project Structure

```
client/
├── src/
│   └── main/
│       ├── java/com/jdwp/client/
│       │   ├── JdwpDebugClientApplication.java    # Main Spring Boot app
│       │   ├── controller/
│       │   │   ├── DebugController.java          # Debug API endpoints
│       │   │   ├── ServerApiController.java       # Proxy to example project APIs
│       │   │   └── WebController.java             # Serves static UI files
│       │   └── service/
│       │       └── JdwpService.java              # JDI/JDWP client logic
│       └── resources/
│           ├── application.properties             # App config (port 8082)
│           ├── logback-spring.xml                 # Logging config
│           └── static/                            # Built React UI files
├── ui/                                             # React frontend source
│   ├── src/
│   │   ├── App.jsx                                # Main React component
│   │   ├── App.css                                # Styles
│   │   └── main.jsx                               # React entry point
│   ├── package.json                               # Node dependencies
│   └── vite.config.js                             # Vite build config
└── pom.xml                                         # Maven dependencies
```

## 🔧 Key Components

### JdwpService
- Handles JDWP connection to Docker container
- Manages breakpoints using JDI
- Controls thread execution
- Inspects variables and stack frames
- Performs step operations

### DebugController
- REST API endpoints for debugging operations
- `/api/debug/connect` - Connect to JDWP server
- `/api/debug/breakpoints` - Manage breakpoints
- `/api/debug/threads` - Thread operations
- `/api/debug/threads/{name}/frames` - Stack frames
- `/api/debug/threads/{name}/variables-next-line` - Variables

### React UI (ui/src/App.jsx)
- Connection management UI
- Breakpoint list and management
- Thread list with suspend/resume
- Stack frame viewer
- Variable inspector
- API endpoint tester
- Debug logs panel

## 🚀 How It Works

1. **Build UI**: React app is built and placed in `src/main/resources/static/`
2. **Build Client**: Spring Boot app packages everything into a JAR
3. **Start Client**: Runs on port 8082, serves UI and API
4. **Connect**: User clicks "Connect" in UI, client connects to Docker container's JDWP (port 5005)
5. **Debug**: User sets breakpoints, calls APIs, inspects variables through the UI

## 🔧 Configuration

- **Port**: 8082 (client application)
- **JDWP Target**: localhost:5005 (Docker container)
- **Java Version**: 21
- **Framework**: Spring Boot 3.2.0
- **Frontend**: React 18 + Vite

## 📝 API Endpoints (Client)

### Debug Operations
- `POST /api/debug/connect` - Connect to JDWP server
- `POST /api/debug/disconnect` - Disconnect from JDWP server
- `GET /api/debug/status` - Get connection status
- `GET /api/debug/threads` - Get all threads
- `GET /api/debug/threads/{name}/frames` - Get stack frames
- `GET /api/debug/threads/{name}/variables-next-line` - Get variables
- `POST /api/debug/breakpoints` - Set breakpoint
- `DELETE /api/debug/breakpoints/{id}` - Remove breakpoint
- `POST /api/debug/threads/{name}/suspend` - Suspend thread
- `POST /api/debug/threads/{name}/resume` - Resume thread
- `POST /api/debug/threads/{name}/step-over` - Step over
- `POST /api/debug/threads/{name}/step-into` - Step into
- `POST /api/debug/threads/{name}/step-out` - Step out

### Server API Proxy
- `GET /api/server/**` - Proxy requests to example project (port 8081)

## 🔄 Architecture

```
┌─────────────────┐
│   React UI      │  (Browser)
│  (Port 8082)    │
└────────┬────────┘
         │ HTTP
         ▼
┌─────────────────┐
│  Client App     │  (Spring Boot)
│  (Port 8082)    │
└────────┬────────┘
         │ JDWP
         ▼
┌─────────────────┐
│ Docker Container│  (Example Project)
│  (Port 5005)    │  (Port 8081 API)
└─────────────────┘
```

## 📌 Note

This client is **independent** of the example project. It can debug any Java application running in Docker with JDWP enabled, not just the example project in `../server/`.
