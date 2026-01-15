# Example Project - Debug Target

## 📋 Purpose

This is the **example project** that runs inside the Docker container and gets debugged remotely. This is a separate Spring Boot application that demonstrates how to debug any Java application running in Docker.

## 🎯 What This Project Is

This is a **standalone Spring Boot application** that:
- Provides REST API endpoints (User CRUD operations)
- Runs inside a Docker container
- Has JDWP enabled for remote debugging
- Serves as an example of any Java application you want to debug

## 🏗️ Project Structure

```
server/
├── src/
│   └── main/
│       ├── java/com/jdwp/server/
│       │   ├── DebugServerApplication.java    # Main Spring Boot app
│       │   ├── controller/
│       │   │   ├── UserController.java        # REST API endpoints
│       │   │   └── HealthController.java       # Health check
│       │   ├── service/
│       │   │   └── UserService.java           # Business logic
│       │   └── model/
│       │       └── User.java                  # Data model
│       └── resources/
│           └── application.properties         # App config
├── data/
│   └── users.json                             # File-based data store
├── Dockerfile                                 # Docker image definition
└── pom.xml                                    # Maven dependencies
```

## 🚀 How It Works

1. **Build**: This project is built into a JAR file (`debug-server-1.0.0.jar`)
2. **Containerize**: The JAR is packaged into a Docker image
3. **Run with JDWP**: The container runs with JDWP agent enabled on port 5005
4. **Debug**: The debugger client (in `../client/`) connects to port 5005 to debug this application

## 🔧 Configuration

- **Port**: 8081 (API server)
- **JDWP Port**: 5005 (debugging)
- **Java Version**: 21
- **Framework**: Spring Boot 3.2.0

## 📝 API Endpoints

- `GET /api/users` - Get all users
- `GET /api/users/{id}` - Get user by ID
- `POST /api/users` - Create new user
- `PUT /api/users/{id}` - Update user
- `DELETE /api/users/{id}` - Delete user
- `GET /health` - Health check

## 🔄 Using Your Own Project

To debug your own Java application:

1. Replace this `server/` directory with your own project
2. Ensure your project:
   - Can be built into a JAR file
   - Has a `Dockerfile` that runs the JAR with JDWP enabled:
     ```dockerfile
     CMD ["java", "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005", "-jar", "your-app.jar"]
     ```
3. Update `docker-compose.yml` to point to your project
4. The debugger client will connect to your application the same way

## 📌 Note

This is just an **example project**. In a real scenario, this would be your actual application that you want to debug, and it would likely be in a completely separate repository.
