FROM eclipse-temurin:21-jdk

WORKDIR /app

# Copy the JAR file
COPY target/debug-server-1.0.0.jar /app/server-app.jar

# Copy data directory (file-based database)
COPY data /app/data

# Expose API port and JDWP port
EXPOSE 8081 5005

# Run with JDWP agent enabled
CMD ["java", "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005", "-jar", "server-app.jar"]
