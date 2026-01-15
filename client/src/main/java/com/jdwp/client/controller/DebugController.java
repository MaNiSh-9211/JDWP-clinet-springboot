package com.jdwp.client.controller;

import com.jdwp.client.service.JdwpService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/debug")
@CrossOrigin(origins = "*")
public class DebugController {
    
    @Autowired
    private JdwpService jdwpService;
    
    @PostMapping("/connect")
    public ResponseEntity<Map<String, Object>> connect(
            @RequestParam(defaultValue = "localhost") String host,
            @RequestParam(defaultValue = "5005") int port) {
        try {
            boolean connected = jdwpService.connect(host, port);
            Map<String, Object> response = new HashMap<>();
            response.put("success", connected);
            response.put("message", connected ? "Connected successfully" : "Connection failed");
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @PostMapping("/disconnect")
    public ResponseEntity<Map<String, Object>> disconnect() {
        try {
            jdwpService.disconnect();
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Disconnected successfully");
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @GetMapping("/status")
    public ResponseEntity<Map<String, Object>> getStatus() {
        Map<String, Object> response = new HashMap<>();
        response.put("connected", jdwpService.isConnected());
        return ResponseEntity.ok(response);
    }
    
    @GetMapping("/threads")
    public ResponseEntity<Map<String, Object>> getAllThreads() {
        try {
            List<Map<String, Object>> threads = jdwpService.getAllThreads();
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("threads", threads);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @GetMapping("/threads/{threadName}/frames")
    public ResponseEntity<Map<String, Object>> getThreadFrames(@PathVariable String threadName) {
        try {
            List<Map<String, Object>> frames = jdwpService.getThreadStackFrames(threadName);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("frames", frames);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @PostMapping("/breakpoints")
    public ResponseEntity<Map<String, Object>> setBreakpoint(
            @RequestParam String className,
            @RequestParam int lineNumber) {
        try {
            String bpId = jdwpService.setBreakpoint(className, lineNumber);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("breakpointId", bpId);
            response.put("message", "Breakpoint set successfully");
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @DeleteMapping("/breakpoints/{bpId}")
    public ResponseEntity<Map<String, Object>> removeBreakpoint(@PathVariable String bpId) {
        try {
            jdwpService.removeBreakpoint(bpId);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Breakpoint removed successfully");
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @DeleteMapping("/breakpoints")
    public ResponseEntity<Map<String, Object>> removeAllBreakpoints() {
        try {
            int count = jdwpService.removeAllBreakpoints();
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "All breakpoints removed successfully");
            response.put("count", count);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @PostMapping("/breakpoints/batch")
    public ResponseEntity<Map<String, Object>> setBreakpointsBatch(@RequestBody List<Map<String, Object>> breakpoints) {
        try {
            List<Map<String, Object>> results = new ArrayList<>();
            int successCount = 0;
            int failCount = 0;
            
            for (Map<String, Object> bp : breakpoints) {
                try {
                    String className = (String) bp.get("className");
                    Integer lineNumber = (Integer) bp.get("lineNumber");
                    if (className != null && lineNumber != null) {
                        String bpId = jdwpService.setBreakpoint(className, lineNumber);
                        Map<String, Object> result = new HashMap<>();
                        result.put("success", true);
                        result.put("breakpointId", bpId);
                        result.put("className", className);
                        result.put("lineNumber", lineNumber);
                        results.add(result);
                        successCount++;
                    }
                } catch (Exception e) {
                    Map<String, Object> result = new HashMap<>();
                    result.put("success", false);
                    result.put("className", bp.get("className"));
                    result.put("lineNumber", bp.get("lineNumber"));
                    result.put("message", e.getMessage());
                    results.add(result);
                    failCount++;
                }
            }
            
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("results", results);
            response.put("successCount", successCount);
            response.put("failCount", failCount);
            response.put("message", String.format("Set %d breakpoints successfully, %d failed", successCount, failCount));
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @GetMapping("/api-breakpoints-config")
    public ResponseEntity<Map<String, Object>> getApiBreakpointsConfig() {
        try {
            // Read the config file
            java.io.InputStream is = getClass().getClassLoader().getResourceAsStream("api-breakpoints-config.json");
            if (is == null) {
                // Try reading from file system
                java.io.File file = new java.io.File("api-breakpoints-config.json");
                if (file.exists()) {
                    is = new java.io.FileInputStream(file);
                } else {
                    throw new RuntimeException("api-breakpoints-config.json not found");
                }
            }
            
            String content = new String(is.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
            com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
            Map<String, Object> config = mapper.readValue(content, Map.class);
            
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("config", config);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @GetMapping("/breakpoints")
    public ResponseEntity<Map<String, Object>> getAllBreakpoints() {
        try {
            List<Map<String, Object>> breakpoints = jdwpService.getAllBreakpoints();
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("breakpoints", breakpoints);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @PostMapping("/threads/{threadName}/resume")
    public ResponseEntity<Map<String, Object>> resumeThread(@PathVariable String threadName) {
        try {
            jdwpService.resumeThread(threadName);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Thread resumed");
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @PostMapping("/continue")
    public ResponseEntity<Map<String, Object>> continueExecution() {
        try {
            jdwpService.continueExecution();
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "VM resumed - execution continuing");
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @PostMapping("/threads/{threadName}/suspend")
    public ResponseEntity<Map<String, Object>> suspendThread(@PathVariable String threadName) {
        try {
            jdwpService.suspendThread(threadName);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Thread suspended");
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @GetMapping("/classes")
    public ResponseEntity<Map<String, Object>> getAllClasses() {
        try {
            List<Map<String, Object>> classes = jdwpService.getAllClasses();
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("classes", classes);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @PostMapping("/threads/{threadName}/step-over")
    public ResponseEntity<Map<String, Object>> stepOver(@PathVariable String threadName) {
        try {
            jdwpService.stepOver(threadName);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Step over executed");
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @PostMapping("/threads/{threadName}/step-into")
    public ResponseEntity<Map<String, Object>> stepInto(@PathVariable String threadName) {
        try {
            jdwpService.stepInto(threadName);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Step into executed");
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @PostMapping("/threads/{threadName}/step-out")
    public ResponseEntity<Map<String, Object>> stepOut(@PathVariable String threadName) {
        try {
            jdwpService.stepOut(threadName);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Step out executed");
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @GetMapping("/threads/{threadName}/variables-next-line")
    public ResponseEntity<Map<String, Object>> getVariablesAtNextLine(@PathVariable String threadName) {
        try {
            Map<String, Object> variables = jdwpService.getVariablesAtNextLine(threadName);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("variables", variables);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @PostMapping("/threads/{threadName}/evaluate")
    public ResponseEntity<Map<String, Object>> evaluateExpression(
            @PathVariable String threadName,
            @RequestParam String expression) {
        try {
            String result = jdwpService.evaluateExpression(threadName, expression);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("result", result);
            response.put("expression", expression);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
    
    @GetMapping("/threads/{threadName}/source-location")
    public ResponseEntity<Map<String, Object>> getCurrentSourceLocation(@PathVariable String threadName) {
        try {
            Map<String, Object> location = jdwpService.getCurrentSourceLocation(threadName);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("location", location);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
}

