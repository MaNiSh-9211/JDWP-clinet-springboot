# 🛠️ JDWP Remote Debugging Project

**🎯 Core Purpose: Debug Java applications running INSIDE Docker containers through a web-based UI.**

This project enables you to remotely debug Spring Boot applications that are containerized in Docker. The application runs in a Docker container with JDWP enabled, and you debug it from your local machine via a web interface.

## 📋 Architecture

This project consists of **two separate components**:

### 1. Example Project (`server/`) - The Application Being Debugged
- **Purpose**: This is a **standalone example Spring Boot application** that runs inside Docker
- **What it is**: A sample REST API application (User CRUD) that demonstrates any Java app you want to debug
- **Location**: `server/` directory
- **Runs in**: Docker container with JDWP enabled
- **Ports**: 
  - 8081 (REST API)
  - 5005 (JDWP debugging port)
- **Note**: In a real scenario, this would be **your actual application** in a separate repository

### 2. Debugger Client (`client/`) - The Debugging Tool
- **Purpose**: The **debugger application** that connects to Docker containers and provides debugging capabilities
- **What it is**: Spring Boot app with JDI (Java Debug Interface) + React UI
- **Location**: `client/` directory  
- **Runs on**: Your local machine (port 8082)
- **Components**:
  - **Backend**: Spring Boot app that connects to JDWP (port 5005) and provides REST API
  - **Frontend**: React web UI for debugging operations
- **Features**: Breakpoints, thread control, variable inspection, step operations, API testing

### Architecture Flow

```
┌─────────────────────────────────────────────────────────┐
│  Your Browser                                           │
│  http://localhost:8082                                  │
└────────────────────┬────────────────────────────────────┘
                     │ HTTP
                     ▼
┌─────────────────────────────────────────────────────────┐
│  Debugger Client (client/)                              │
│  - Spring Boot Backend (JDI/JDWP Client)              │
│  - React UI                                             │
│  Port: 8082                                             │
└────────────────────┬────────────────────────────────────┘
                     │ JDWP Protocol
                     │ (Port 5005)
                     ▼
┌─────────────────────────────────────────────────────────┐
│  Docker Container                                       │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Example Project (server/)                      │   │
│  │  - Spring Boot Application                     │   │
│  │  - REST API (Port 8081)                        │   │
│  │  - JDWP Agent (Port 5005)                      │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- Java 21 JDK
- Maven 3.6+
- Node.js 18+ and npm
- Docker and Docker Compose

### Installation

1. **Install all dependencies** (builds server, client, and installs UI packages):
   ```bash
   install-dependencies.bat
   ```

### Running the Project

1. **Start the Docker container** (application runs INSIDE Docker with JDWP):
   ```bash
   docker-compose up -d --build
   ```
   
   **⚠️ IMPORTANT**: The Spring Boot application runs INSIDE the Docker container!
   - Container exposes JDWP port 5005 → localhost:5005
   - Container exposes API port 8081 → localhost:8081
   - You debug the containerized application remotely
   
   Verify container is running:
   ```bash
   docker ps
   docker logs jdwp-debug-server
   ```

2. **Start both backend and frontend**:
   ```bash
   start-all.bat
   ```

   This will:
   - Start the Spring Boot client on `http://localhost:8080`
   - Start the React UI on `http://localhost:3000`

3. **Access the Web UI and Debug the Docker Container**:
   - Open your browser and go to `http://localhost:3000`
   - Click "Connect" (default: localhost:5005)
     - **This connects to the JDWP agent running INSIDE the Docker container**
   - Set breakpoint: `com.jdwp.server.controller.UserController:19`
   - Click "GET /users" in API panel
     - **This calls the API running INSIDE the Docker container**
   - Breakpoint hits in the container → inspect variables from container's execution
   - **All debugging happens on the Docker containerized application!**

## 📁 Project Structure

```
.
├── server/                 # ⚠️ EXAMPLE PROJECT - The application being debugged
│   ├── src/                 #   (In real scenario, this would be your actual app)
│   ├── Dockerfile            #   This is a separate, standalone project
│   ├── pom.xml              #   See server/README.md for details
│   └── README.md
│
├── client/                   # 🔧 DEBUGGER CLIENT - The debugging tool
│   ├── src/                 #   This connects to Docker containers via JDWP
│   │   ├── java/            #   - Spring Boot backend (JDI client)
│   │   └── resources/      #   - Built React UI (in static/)
│   ├── ui/                  #   React frontend source code
│   │   ├── src/            #   See client/README.md for details
│   │   └── package.json
│   ├── pom.xml
│   └── README.md
│
├── docker-compose.yml       # Docker configuration for example project
├── rebuild-and-start.bat    # Rebuilds everything and starts services
├── install-dependencies.bat # Installs all dependencies
└── README.md               # This file
```

**Key Points:**
- `server/` = **Example project** (the app being debugged) - separate project
- `client/` = **Debugger tool** (connects to Docker + provides UI) - this is the main tool

## 🔧 Features

### Web UI Features:
- ✅ Connect/Disconnect to JDWP server
- ✅ View all threads
- ✅ View stack frames for each thread
- ✅ Inspect variables in stack frames
- ✅ Set breakpoints by class name and line number
- ✅ Remove breakpoints
- ✅ Suspend/Resume threads
- ✅ View all loaded classes

### API Endpoints:

- `POST /api/debug/connect?host=localhost&port=5005` - Connect to JDWP server
- `POST /api/debug/disconnect` - Disconnect from JDWP server
- `GET /api/debug/status` - Check connection status
- `GET /api/debug/threads` - Get all threads
- `GET /api/debug/threads/{threadName}/frames` - Get stack frames for a thread
- `POST /api/debug/threads/{threadName}/suspend` - Suspend a thread
- `POST /api/debug/threads/{threadName}/resume` - Resume a thread
- `POST /api/debug/breakpoints?className=X&lineNumber=Y` - Set a breakpoint
- `DELETE /api/debug/breakpoints/{bpId}` - Remove a breakpoint
- `GET /api/debug/breakpoints` - Get all breakpoints
- `GET /api/debug/classes` - Get all loaded classes

## 🐳 Docker Details

The server runs with JDWP enabled:
```dockerfile
CMD ["java", "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005", "-jar", "server-app.jar"]
```

- **Port**: 5005 (JDWP port)
- **Transport**: dt_socket
- **Mode**: Server mode (waits for debugger to attach)
- **Suspend**: No (application starts immediately)

## 🔍 Debugging Example

1. Start the Docker container
2. Start the client and UI using `start-all.bat`
3. Open `http://localhost:3000`
4. Connect to `localhost:5005`
5. Set a breakpoint:
   - Class: `com.jdwp.server.DebugServer`
   - Line: `35` (inside `calculateSquare` method)
6. The application will hit the breakpoint when that line executes
7. View the stack frames and variables in the UI

## 🛠️ Manual Commands

### Build Server:
```bash
cd server
mvn clean package
```

### Build Client:
```bash
cd client
mvn clean package
```

### Run Client:
```bash
cd client
java -jar target/debug-client-1.0.0.jar
```

### Run UI:
```bash
cd client/ui
npm install
npm run start
```

### Build Docker Image:
```bash
cd server
docker build -t jdwp-server .
docker run -p 5005:5005 jdwp-server
```

## 📝 Notes

- The server application runs continuously, generating random numbers and calculating squares
- JDWP port 5005 must be accessible from the host machine
- The Spring Boot client uses JDI (Java Debug Interface) which is part of the JDK
- All components use the latest stable versions (Java 21, Spring Boot 3.2.0, React 18, Vite 5)

## 🔒 Security Note

JDWP is not encrypted. In production, use SSH tunneling or VPN to secure the connection:
```bash
ssh -L 5005:localhost:5005 user@remote-host
```

## 📚 Technologies Used

- **Java 21** - Latest LTS version
- **Spring Boot 3.2.0** - Latest stable version
- **JDI (Java Debug Interface)** - Native JDWP client
- **React 18.2.0** - Latest stable version
- **Vite 5.0.8** - Latest build tool
- **Docker** - Containerization
- **Maven** - Java build tool
- **npm** - Node.js package manager

## 🧪 Automated Testing

The project includes comprehensive automated tests that simulate all frontend debugging operations:

### Run Automated Tests

```bash
run-automated-tests.bat
```

This script will:
1. ✅ Start Docker container with JDWP server
2. ✅ Start Spring Boot client
3. ✅ Automatically test all debugging operations:
   - Connect to JDWP server
   - Get all threads
   - Get all classes
   - Set breakpoints automatically
   - Inspect variables at breakpoint
   - Get stack frames with variables
   - Suspend/resume threads
   - Remove breakpoints
   - Disconnect

### Test Files

- `client/src/test/java/com/jdwp/client/AutomatedDebuggingTest.java` - Main automated test
- `client/src/test/java/com/jdwp/client/StandaloneDebuggingTest.java` - Standalone test (no Spring context)
- `client/src/test/java/com/jdwp/client/DebuggingTestSuite.java` - Comprehensive test suite

### Manual Test Execution

```bash
# Run all tests
cd client
mvn test

# Run specific test
mvn test -Dtest=AutomatedDebuggingTest
```

## 🐛 Troubleshooting

1. **Connection failed**: Make sure Docker container is running and port 5005 is exposed
2. **Build errors**: Ensure Java 21 and Maven are installed and in PATH
3. **UI not loading**: Check if Node.js 18+ is installed
4. **Port conflicts**: Change ports in `application.properties` (client) and `vite.config.js` (UI)
5. **Tests fail**: Ensure Docker container is running before running tests

## 📄 License

This project is for educational and development purposes.

