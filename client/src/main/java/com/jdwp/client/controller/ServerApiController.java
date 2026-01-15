package com.jdwp.client.controller;

import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;

import jakarta.servlet.http.HttpServletRequest;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/server")
@CrossOrigin(origins = "*")
public class ServerApiController {
    
    private static final String DEBUG_SERVER_URL = "http://localhost:8081";
    private final RestTemplate restTemplate = new RestTemplate();
    
    @GetMapping("/users")
    public ResponseEntity<Object> getAllUsers() {
        return callServerApi("GET", "/api/users", null);
    }
    
    @GetMapping("/users/{id}")
    public ResponseEntity<Object> getUserById(@PathVariable Long id) {
        return callServerApi("GET", "/api/users/" + id, null);
    }
    
    @PostMapping("/users")
    public ResponseEntity<Object> createUser(@RequestBody Map<String, Object> user) {
        return callServerApi("POST", "/api/users", user);
    }
    
    @PutMapping("/users/{id}")
    public ResponseEntity<Object> updateUser(@PathVariable Long id, @RequestBody Map<String, Object> user) {
        return callServerApi("PUT", "/api/users/" + id, user);
    }
    
    @DeleteMapping("/users/{id}")
    public ResponseEntity<Object> deleteUser(@PathVariable Long id) {
        return callServerApi("DELETE", "/api/users/" + id, null);
    }
    
    @GetMapping("/health")
    public ResponseEntity<Object> health() {
        return callServerApi("GET", "/health", null);
    }
    
    @GetMapping("/endpoints")
    public ResponseEntity<Map<String, Object>> getAvailableEndpoints() {
        Map<String, Object> endpoints = new HashMap<>();
        endpoints.put("baseUrl", DEBUG_SERVER_URL);
        Map<String, String> endpointMap = new HashMap<>();
        endpointMap.put("GET /api/users", "Get all users");
        endpointMap.put("GET /api/users/{id}", "Get user by ID");
        endpointMap.put("POST /api/users", "Create new user");
        endpointMap.put("PUT /api/users/{id}", "Update user");
        endpointMap.put("DELETE /api/users/{id}", "Delete user");
        endpointMap.put("GET /health", "Health check");
        endpoints.put("endpoints", endpointMap);
        return ResponseEntity.ok(endpoints);
    }
    
    // Catch-all proxy endpoint for any path
    @RequestMapping(value = "/**", method = {RequestMethod.GET, RequestMethod.POST, RequestMethod.PUT, RequestMethod.DELETE})
    public ResponseEntity<Object> proxyRequest(
            HttpMethod method,
            @RequestBody(required = false) Map<String, Object> body,
            HttpServletRequest request) {
        String path = request.getRequestURI().substring("/api/server".length());
        if (path.isEmpty()) {
            path = "/";
        }
        return callServerApi(method.name(), path, body);
    }
    
    private ResponseEntity<Object> callServerApi(String method, String path, Object body) {
        try {
            String url = DEBUG_SERVER_URL + path;
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Object> entity = new HttpEntity<>(body, headers);
            
            ResponseEntity<Object> response;
            switch (method.toUpperCase()) {
                case "GET":
                    response = restTemplate.exchange(url, HttpMethod.GET, entity, Object.class);
                    break;
                case "POST":
                    response = restTemplate.exchange(url, HttpMethod.POST, entity, Object.class);
                    break;
                case "PUT":
                    response = restTemplate.exchange(url, HttpMethod.PUT, entity, Object.class);
                    break;
                case "DELETE":
                    response = restTemplate.exchange(url, HttpMethod.DELETE, entity, Object.class);
                    break;
                default:
                    throw new IllegalArgumentException("Unsupported HTTP method: " + method);
            }
            
            return response;
        } catch (Exception e) {
            Map<String, Object> error = new HashMap<>();
            error.put("error", e.getMessage());
            error.put("message", "Failed to call server API: " + path);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(error);
        }
    }
}

