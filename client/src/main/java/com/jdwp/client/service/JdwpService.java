package com.jdwp.client.service;

import com.sun.jdi.*;
import com.sun.jdi.connect.AttachingConnector;
import com.sun.jdi.connect.Connector;
import com.sun.jdi.connect.IllegalConnectorArgumentsException;
import com.sun.jdi.event.*;
import com.sun.jdi.request.BreakpointRequest;
import com.sun.jdi.request.EventRequestManager;
import com.sun.jdi.request.StepRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

@Service
public class JdwpService {
    private static final Logger logger = LoggerFactory.getLogger(JdwpService.class);
    private VirtualMachine vm;
    private final Map<String, BreakpointRequest> breakpoints = new ConcurrentHashMap<>();
    // Track which threads we've already seen as suspended to avoid spam
    private final Set<String> knownSuspendedThreads = ConcurrentHashMap.newKeySet();
    
    public boolean connect(String host, int port) {
        logger.info("========================================");
        logger.info("[JDWP CLIENT] Attempting to connect to JDWP server at {}:{}", host, port);
        logger.info("========================================");
        try {
            if (vm != null) {
                logger.info("[JDWP CLIENT] Disposing existing VM connection...");
                try {
                    vm.dispose();
                } catch (Exception e) {
                    logger.debug("[JDWP CLIENT] VM already disposed or disconnected: {}", e.getMessage());
                }
            }
            
            logger.info("[JDWP CLIENT] Getting SocketAttach connector...");
            AttachingConnector connector = Bootstrap.virtualMachineManager()
                    .attachingConnectors()
                    .stream()
                    .filter(c -> c.name().equals("com.sun.jdi.SocketAttach"))
                    .findFirst()
                    .orElseThrow(() -> new RuntimeException("SocketAttach connector not found"));
            
            Map<String, Connector.Argument> arguments = connector.defaultArguments();
            arguments.get("hostname").setValue(host);
            arguments.get("port").setValue(String.valueOf(port));
            
            logger.info("[JDWP CLIENT] Attaching to JDWP server...");
            vm = connector.attach(arguments);
            logger.info("[JDWP CLIENT] ✓✓✓ Successfully connected to JDWP server at {}:{}", host, port);
            logger.info("[JDWP CLIENT] VM Description: {}", vm.description());
            logger.info("========================================");
            return true;
        } catch (Exception e) {
            logger.error("[JDWP CLIENT] ✗✗✗ Failed to connect to JDWP server: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to connect to JDWP server: " + e.getMessage(), e);
        }
    }
    
    public void disconnect() {
        logger.info("[JDWP CLIENT] Disconnecting from JDWP server...");
        if (vm != null) {
            try {
                logger.info("[JDWP CLIENT] Disposing VM connection...");
                vm.dispose();
                logger.info("[JDWP CLIENT] ✓ VM disposed successfully");
            } catch (Exception e) {
                logger.debug("[JDWP CLIENT] VM already disposed: {}", e.getMessage());
            }
            vm = null;
        }
        breakpoints.clear();
        knownSuspendedThreads.clear(); // Clear tracking
        logger.info("[JDWP CLIENT] ✓✓✓ Disconnected from JDWP server");
    }
    
    public boolean isConnected() {
        if (vm == null) {
            return false;
        }
        try {
            // Try to access VM to check if it's still connected
            vm.allThreads();
            return true;
        } catch (Exception e) {
            return false;
        }
    }
    
    public List<Map<String, Object>> getAllThreads() {
        if (!isConnected()) {
            throw new IllegalStateException("Not connected to JDWP server");
        }
        
        // Get all threads
        List<ThreadReference> allThreads = vm.allThreads();
        
        // Update our tracking of suspended threads
        Set<String> currentlySuspended = allThreads.stream()
                .filter(ThreadReference::isSuspended)
                .map(ThreadReference::name)
                .collect(Collectors.toSet());
        
        // Remove threads that are no longer suspended from our tracking
        knownSuspendedThreads.retainAll(currentlySuspended);
        
        // Return thread info
        return allThreads.stream()
                .map(thread -> {
                    Map<String, Object> threadInfo = new HashMap<>();
                    threadInfo.put("name", thread.name());
                    threadInfo.put("status", getThreadStatusString(thread.status()));
                    threadInfo.put("isSuspended", thread.isSuspended());
                    threadInfo.put("threadGroup", thread.threadGroup() != null ? thread.threadGroup().name() : "N/A");
                    
                    // CRITICAL: Check if this thread is suspended at one of OUR breakpoints
                    boolean isAtOurBreakpoint = false;
                    if (thread.isSuspended()) {
                        try {
                            List<StackFrame> frames = thread.frames();
                            if (!frames.isEmpty()) {
                                StackFrame frame = frames.get(0);
                                Location currentLocation = frame.location();
                                String currentClassName = currentLocation.declaringType().name();
                                int currentLineNumber = currentLocation.lineNumber();
                                
                                // Check if this location matches any of our breakpoints
                                // Compare by className and lineNumber (more reliable than codeIndex)
                                for (Map.Entry<String, BreakpointRequest> entry : breakpoints.entrySet()) {
                                    try {
                                        String bpId = entry.getKey();
                                        BreakpointRequest bpRequest = entry.getValue();
                                        
                                        // Extract className and lineNumber from breakpoint ID (format: "className:lineNumber")
                                        if (bpId.contains(":")) {
                                            String[] parts = bpId.split(":", 2);
                                            String bpClassName = parts[0];
                                            int bpLineNumber = Integer.parseInt(parts[1]);
                                            
                                            // Match by className and lineNumber
                                            if (bpClassName.equals(currentClassName) && bpLineNumber == currentLineNumber) {
                                                // Match! Thread is at our breakpoint!
                                                isAtOurBreakpoint = true;
                                                logger.info("[JDWP CLIENT] ✓ Thread {} is at breakpoint: {}:{}", 
                                                           thread.name(), currentClassName, currentLineNumber);
                                                break;
                                            }
                                        }
                                    } catch (Exception e) {
                                        logger.debug("[JDWP CLIENT] Could not check breakpoint location: {}", e.getMessage());
                                    }
                                }
                                
                                if (!isAtOurBreakpoint) {
                                    logger.debug("[JDWP CLIENT] Thread {} is suspended but NOT at our breakpoint: {}:{}", 
                                               thread.name(), currentClassName, currentLineNumber);
                                }
                            }
                        } catch (Exception e) {
                            logger.debug("[JDWP CLIENT] Could not check breakpoint location for thread {}: {}", thread.name(), e.getMessage());
                        }
                    }
                    
                    // Mark if this is a newly suspended thread (not seen before)
                    // AND it's at one of our breakpoints (not just randomly suspended)
                    boolean isNewlySuspended = thread.isSuspended() && 
                                             !knownSuspendedThreads.contains(thread.name()) &&
                                             isAtOurBreakpoint; // Only mark as new if at our breakpoint
                    
                    if (isNewlySuspended) {
                        threadInfo.put("isNewlySuspended", true);
                        knownSuspendedThreads.add(thread.name()); // Track it now
                        logger.info("[JDWP CLIENT] ✓ NEW breakpoint hit detected: thread {} at breakpoint", thread.name());
                    } else {
                        threadInfo.put("isNewlySuspended", false);
                    }
                    
                    return threadInfo;
                })
                .collect(Collectors.toList());
    }
    
    public List<Map<String, Object>> getThreadStackFrames(String threadName) {
        logger.info("[JDWP CLIENT] Getting stack frames for thread: {}", threadName);
        if (!isConnected()) {
            logger.error("[JDWP CLIENT] ✗ Not connected to JDWP server");
            throw new IllegalStateException("Not connected to JDWP server");
        }
        
        ThreadReference thread = vm.allThreads().stream()
                .filter(t -> t.name().equals(threadName))
                .findFirst()
                .orElseThrow(() -> new RuntimeException("Thread not found: " + threadName));
        
        try {
            if (!thread.isSuspended()) {
                logger.info("[JDWP CLIENT] Thread not suspended, suspending...");
                thread.suspend();
            }
            
            // Wait a bit for thread to be fully suspended
            Thread.sleep(200);
            
            List<Map<String, Object>> frames = new ArrayList<>();
            int frameIndex = 0;
            for (StackFrame frame : thread.frames()) {
                Map<String, Object> frameInfo = new HashMap<>();
                Location location = frame.location();
                String className = location.declaringType().name();
                String methodName = location.method().name();
                int lineNumber = location.lineNumber();
                
                frameInfo.put("method", methodName);
                frameInfo.put("class", className);
                frameInfo.put("lineNumber", lineNumber);
                
                Map<String, Object> variables = new HashMap<>();
                try {
                    for (LocalVariable var : frame.visibleVariables()) {
                        try {
                            Value value = frame.getValue(var);
                            String valueStr = value != null ? value.toString() : "null";
                            variables.put(var.name(), valueStr);
                            logger.info("[JDWP CLIENT]   Frame {} - Variable: {} = {}", frameIndex, var.name(), valueStr);
                        } catch (Exception e) {
                            logger.debug("[JDWP CLIENT]   Frame {} - Variable {} not accessible: {}", frameIndex, var.name(), e.getMessage());
                        }
                    }
                } catch (Exception e) {
                    logger.debug("[JDWP CLIENT]   Frame {} - Some variables not accessible: {}", frameIndex, e.getMessage());
                }
                frameInfo.put("variables", variables);
                
                logger.info("[JDWP CLIENT]   Frame #{}: {}:{}:{} ({} variables)", 
                           frameIndex, 
                           className,
                           methodName, 
                           lineNumber,
                           variables.size());
                if (!variables.isEmpty()) {
                    for (String varName : variables.keySet()) {
                        logger.info("[JDWP CLIENT]     - {} = {}", varName, variables.get(varName));
                    }
                }
                
                frames.add(frameInfo);
                frameIndex++;
            }
            
            logger.info("[JDWP CLIENT] ✓ Retrieved {} stack frames for thread {}", frames.size(), threadName);
            logger.info("[JDWP CLIENT] Stack trace (top to bottom):");
            for (int i = 0; i < Math.min(frames.size(), 10); i++) {
                Map<String, Object> f = frames.get(i);
                logger.info("[JDWP CLIENT]   [{}/{}] {}:{}:{}", 
                           i+1, frames.size(),
                           f.get("class"), f.get("method"), f.get("lineNumber"));
            }
            return frames;
        } catch (Exception e) {
            logger.error("[JDWP CLIENT] ✗ Failed to get stack frames: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to get stack frames: " + e.getMessage(), e);
        }
    }
    
    public String setBreakpoint(String className, int lineNumber) {
        logger.info("========================================");
        logger.info("[JDWP CLIENT] Setting breakpoint at {}:{}", className, lineNumber);
        logger.info("========================================");
        if (!isConnected()) {
            logger.error("[JDWP CLIENT] ✗ Not connected to JDWP server");
            throw new IllegalStateException("Not connected to JDWP server");
        }
        
        try {
            logger.info("[JDWP CLIENT] Waiting for class {} to be loaded...", className);
            // Wait for class to be loaded (with retries)
            List<ReferenceType> classes = null;
            for (int i = 0; i < 10; i++) {
                classes = vm.classesByName(className);
                if (!classes.isEmpty()) {
                    logger.info("[JDWP CLIENT] ✓ Class found (attempt {})", i + 1);
                    break;
                }
                logger.debug("[JDWP CLIENT] Class not loaded yet, waiting... (attempt {})", i + 1);
                Thread.sleep(500);
            }
            
            if (classes == null || classes.isEmpty()) {
                logger.error("[JDWP CLIENT] ✗ Class not found or not loaded yet: {}", className);
                throw new RuntimeException("Class not found or not loaded yet: " + className);
            }
            
            ReferenceType clazz = classes.get(0);
            logger.info("[JDWP CLIENT] Looking for executable code at line {}...", lineNumber);
            List<Location> locations = clazz.locationsOfLine(lineNumber);
            
            if (locations.isEmpty()) {
                logger.info("[JDWP CLIENT] No executable code at line {}, searching nearby lines...", lineNumber);
                // Try to find nearest executable line
                for (int offset = 1; offset <= 5; offset++) {
                    locations = clazz.locationsOfLine(lineNumber + offset);
                    if (!locations.isEmpty()) {
                        lineNumber = lineNumber + offset;
                        logger.info("[JDWP CLIENT] Found executable code at line {} (offset +{})", lineNumber, offset);
                        break;
                    }
                    locations = clazz.locationsOfLine(lineNumber - offset);
                    if (!locations.isEmpty()) {
                        lineNumber = lineNumber - offset;
                        logger.info("[JDWP CLIENT] Found executable code at line {} (offset -{})", lineNumber, offset);
                        break;
                    }
                }
                
                if (locations.isEmpty()) {
                    logger.error("[JDWP CLIENT] ✗ No executable code found at line {} in class {}", lineNumber, className);
                    throw new RuntimeException("No executable code found at line " + lineNumber + 
                        " in class " + className + ". The line may be a comment, blank, or not yet compiled.");
                }
            } else {
                logger.info("[JDWP CLIENT] ✓ Found executable code at line {}", lineNumber);
            }
            
            Location location = locations.get(0);
            String actualClassName = location.declaringType().name();
            String methodName = location.method().name();
            int actualLineNumber = location.lineNumber();
            
            logger.info("[JDWP CLIENT] Location details:");
            logger.info("[JDWP CLIENT]   Class: {}", actualClassName);
            logger.info("[JDWP CLIENT]   Method: {}", methodName);
            logger.info("[JDWP CLIENT]   Line: {} (requested: {})", actualLineNumber, lineNumber);
            
            EventRequestManager erm = vm.eventRequestManager();
            BreakpointRequest bpRequest = erm.createBreakpointRequest(location);
            bpRequest.enable();
            
            String bpId = className + ":" + lineNumber;
            breakpoints.put(bpId, bpRequest);
            logger.info("[JDWP CLIENT] ✓✓✓ BREAKPOINT SET SUCCESSFULLY");
            logger.info("[JDWP CLIENT]   Breakpoint ID: {}", bpId);
            logger.info("[JDWP CLIENT]   Actual Location: {}:{}:{}", actualClassName, methodName, actualLineNumber);
            logger.info("[JDWP CLIENT]   Breakpoint is ACTIVE and will suspend execution when hit");
            logger.info("========================================");
            return bpId;
        } catch (Exception e) {
            logger.error("[JDWP CLIENT] ✗✗✗ Failed to set breakpoint: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to set breakpoint: " + e.getMessage(), e);
        }
    }
    
    public int removeAllBreakpoints() {
        logger.info("========================================");
        logger.info("[JDWP CLIENT] REMOVING ALL BREAKPOINTS");
        logger.info("========================================");
        
        if (!isConnected()) {
            logger.error("[JDWP CLIENT] ✗ Not connected to JDWP server");
            throw new IllegalStateException("Not connected to JDWP server");
        }
        
        int count = breakpoints.size();
        logger.info("[JDWP CLIENT] Removing {} breakpoints...", count);
        
        try {
            EventRequestManager erm = vm.eventRequestManager();
            for (BreakpointRequest bp : breakpoints.values()) {
                try {
                    erm.deleteEventRequest(bp);
                    logger.info("[JDWP CLIENT]   Removed breakpoint: {}", bp);
                } catch (Exception e) {
                    logger.warn("[JDWP CLIENT]   Failed to remove breakpoint: {}", e.getMessage());
                }
            }
            breakpoints.clear();
            logger.info("[JDWP CLIENT] ✓ All {} breakpoints removed successfully", count);
            logger.info("========================================");
            return count;
        } catch (Exception e) {
            logger.error("[JDWP CLIENT] ✗ Failed to remove all breakpoints: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to remove all breakpoints: " + e.getMessage(), e);
        }
    }
    
    public void removeBreakpoint(String bpId) {
        logger.info("[JDWP CLIENT] Removing breakpoint: {}", bpId);
        BreakpointRequest bp = breakpoints.remove(bpId);
        if (bp != null) {
            vm.eventRequestManager().deleteEventRequest(bp);
            logger.info("[JDWP CLIENT] ✓ Breakpoint removed: {}", bpId);
        } else {
            logger.warn("[JDWP CLIENT] Breakpoint not found: {}", bpId);
        }
    }
    
    public List<Map<String, Object>> getAllBreakpoints() {
        return breakpoints.entrySet().stream()
                .map(entry -> {
                    Map<String, Object> bpInfo = new HashMap<>();
                    bpInfo.put("id", entry.getKey());
                    bpInfo.put("location", entry.getKey());
                    return bpInfo;
                })
                .collect(Collectors.toList());
    }
    
    public void resumeThread(String threadName) {
        logger.info("[JDWP CLIENT] Resuming thread: {}", threadName);
        if (!isConnected()) {
            logger.error("[JDWP CLIENT] ✗ Not connected to JDWP server");
            throw new IllegalStateException("Not connected to JDWP server");
        }
        
        ThreadReference thread = vm.allThreads().stream()
                .filter(t -> t.name().equals(threadName))
                .findFirst()
                .orElseThrow(() -> new RuntimeException("Thread not found: " + threadName));
        
        thread.resume();
        // CRITICAL: Remove from tracking since it's no longer suspended
        // This allows us to detect if it hits a breakpoint again later
        knownSuspendedThreads.remove(threadName);
        logger.info("[JDWP CLIENT] ✓✓✓ Thread resumed: {} (removed from suspended tracking)", threadName);
    }
    
    /**
     * Continue execution - resumes the entire VM (all threads)
     * This is different from resumeThread which only resumes one thread
     * CRITICAL: Clears all step requests so execution continues until breakpoint, not one line
     */
    public void continueExecution() {
        logger.info("========================================");
        logger.info("[JDWP CLIENT] CONTINUE EXECUTION (Resume VM)");
        logger.info("========================================");
        if (!isConnected()) {
            logger.error("[JDWP CLIENT] ✗ Not connected to JDWP server");
            throw new IllegalStateException("Not connected to JDWP server");
        }
        
        // CRITICAL: Delete ALL step requests before continuing
        // If step requests are active, execution will stop at next line instead of continuing to breakpoint
        EventRequestManager erm = vm.eventRequestManager();
        List<StepRequest> allStepRequests = erm.stepRequests();
        if (!allStepRequests.isEmpty()) {
            logger.info("[JDWP CLIENT] Clearing {} active step request(s) before continuing...", allStepRequests.size());
            for (StepRequest stepRequest : allStepRequests) {
                try {
                    erm.deleteEventRequest(stepRequest);
                    logger.info("[JDWP CLIENT]   Deleted step request for thread: {}", stepRequest.thread().name());
                } catch (Exception e) {
                    logger.warn("[JDWP CLIENT]   Could not delete step request: {}", e.getMessage());
                }
            }
        }
        
        // Resume the entire VM - this resumes ALL threads
        vm.resume();
        
        // Clear ALL suspended thread tracking since we're continuing execution
        int count = knownSuspendedThreads.size();
        knownSuspendedThreads.clear();
        logger.info("[JDWP CLIENT] ✓✓✓ VM resumed - all threads continuing execution");
        logger.info("[JDWP CLIENT] Cleared tracking for {} suspended threads", count);
        logger.info("[JDWP CLIENT] Execution will continue until next breakpoint is hit (NOT one line)");
        logger.info("========================================");
    }
    
    /**
     * Clear tracking for a specific thread - useful when you want to re-detect a breakpoint hit
     */
    public void clearSuspendedThreadTracking(String threadName) {
        knownSuspendedThreads.remove(threadName);
        logger.info("[JDWP CLIENT] Cleared suspended tracking for thread: {}", threadName);
    }
    
    /**
     * Clear all suspended thread tracking - useful when you want to reset
     */
    public void clearAllSuspendedThreadTracking() {
        int count = knownSuspendedThreads.size();
        knownSuspendedThreads.clear();
        logger.info("[JDWP CLIENT] Cleared all suspended thread tracking ({} threads)", count);
    }
    
    public void suspendThread(String threadName) {
        logger.info("[JDWP CLIENT] Suspending thread: {}", threadName);
        if (!isConnected()) {
            logger.error("[JDWP CLIENT] ✗ Not connected to JDWP server");
            throw new IllegalStateException("Not connected to JDWP server");
        }
        
        ThreadReference thread = vm.allThreads().stream()
                .filter(t -> t.name().equals(threadName))
                .findFirst()
                .orElseThrow(() -> new RuntimeException("Thread not found: " + threadName));
        
        thread.suspend();
        logger.info("[JDWP CLIENT] ✓✓✓ Thread suspended: {}", threadName);
    }
    
    public List<Map<String, Object>> getAllClasses() {
        if (!isConnected()) {
            throw new IllegalStateException("Not connected to JDWP server");
        }
        
        return vm.allClasses().stream()
                .map(clazz -> {
                    Map<String, Object> classInfo = new HashMap<>();
                    classInfo.put("name", clazz.name());
                    try {
                        classInfo.put("isInterface", clazz instanceof InterfaceType);
                        classInfo.put("isAbstract", clazz instanceof ClassType && ((ClassType) clazz).isAbstract());
                    } catch (Exception e) {
                        classInfo.put("isInterface", false);
                        classInfo.put("isAbstract", false);
                    }
                    return classInfo;
                })
                .collect(Collectors.toList());
    }
    
    public void stepOver(String threadName) {
        logger.info("========================================");
        logger.info("[JDWP CLIENT] EXECUTING STEP OVER");
        logger.info("[JDWP CLIENT] Thread: {}", threadName);
        logger.info("========================================");
        if (!isConnected()) {
            logger.error("[JDWP CLIENT] ✗ Not connected to JDWP server");
            throw new IllegalStateException("Not connected to JDWP server");
        }
        
        ThreadReference thread = vm.allThreads().stream()
                .filter(t -> t.name().equals(threadName))
                .findFirst()
                .orElseThrow(() -> new RuntimeException("Thread not found: " + threadName));
        
        if (!thread.isSuspended()) {
            logger.error("[JDWP CLIENT] ✗ Thread must be suspended to step");
            throw new IllegalStateException("Thread must be suspended to step");
        }
        
        try {
            StackFrame frame = thread.frame(0);
            Location currentLocation = frame.location();
            String beforeClass = currentLocation.declaringType().name();
            String beforeMethod = currentLocation.method().name();
            int beforeLine = currentLocation.lineNumber();
            
            logger.info("[JDWP CLIENT] BEFORE STEP OVER:");
            logger.info("[JDWP CLIENT]   Location: {}:{}:{}", beforeClass, beforeMethod, beforeLine);
            logger.info("[JDWP CLIENT]   Stack depth: {}", thread.frameCount());
            
            EventRequestManager erm = vm.eventRequestManager();
            
            // CRITICAL: Delete any existing step requests for this thread first
            // JDWP only allows one step request per thread at a time
            List<StepRequest> existingSteps = erm.stepRequests();
            for (StepRequest existing : existingSteps) {
                if (existing.thread().equals(thread)) {
                    logger.info("[JDWP CLIENT] Deleting existing step request for thread");
                    erm.deleteEventRequest(existing);
                }
            }
            
            StepRequest stepRequest = erm.createStepRequest(thread, StepRequest.STEP_LINE, StepRequest.STEP_OVER);
            // Don't use addCountFilter - let it step naturally
            // addCountFilter(1) can cause issues if the next line doesn't have executable code
            stepRequest.enable();
            logger.info("[JDWP CLIENT] Step request created and enabled (STEP_OVER, no count filter)");
            logger.info("[JDWP CLIENT] Resuming thread to execute step...");
            
            // CRITICAL: Clear tracking for this thread so we can detect when it suspends again after step
            knownSuspendedThreads.remove(threadName);
            
            thread.resume();
            logger.info("[JDWP CLIENT] ✓✓✓ STEP OVER EXECUTED");
            logger.info("[JDWP CLIENT] Thread will suspend at the next executable line in the same method");
            logger.info("[JDWP CLIENT] NOTE: If breakpoints exist in called methods, they will be hit first");
            logger.info("[JDWP CLIENT] Tracking cleared - will detect new suspension after step completes");
            logger.info("========================================");
            // Step will complete and thread will suspend again
            // The step request will automatically delete itself after completion
        } catch (Exception e) {
            logger.error("[JDWP CLIENT] ✗✗✗ Failed to step over: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to step over: " + e.getMessage(), e);
        }
    }
    
    public void stepInto(String threadName) {
        logger.info("========================================");
        logger.info("[JDWP CLIENT] EXECUTING STEP INTO");
        logger.info("[JDWP CLIENT] Thread: {}", threadName);
        logger.info("========================================");
        if (!isConnected()) {
            logger.error("[JDWP CLIENT] ✗ Not connected to JDWP server");
            throw new IllegalStateException("Not connected to JDWP server");
        }
        
        ThreadReference thread = vm.allThreads().stream()
                .filter(t -> t.name().equals(threadName))
                .findFirst()
                .orElseThrow(() -> new RuntimeException("Thread not found: " + threadName));
        
        if (!thread.isSuspended()) {
            logger.error("[JDWP CLIENT] ✗ Thread must be suspended to step");
            throw new IllegalStateException("Thread must be suspended to step");
        }
        
        try {
            StackFrame frame = thread.frame(0);
            Location currentLocation = frame.location();
            String beforeClass = currentLocation.declaringType().name();
            String beforeMethod = currentLocation.method().name();
            int beforeLine = currentLocation.lineNumber();
            
            logger.info("[JDWP CLIENT] BEFORE STEP INTO:");
            logger.info("[JDWP CLIENT]   Location: {}:{}:{}", beforeClass, beforeMethod, beforeLine);
            logger.info("[JDWP CLIENT]   Stack depth: {}", thread.frameCount());
            
            EventRequestManager erm = vm.eventRequestManager();
            
            // CRITICAL: Delete any existing step requests for this thread first
            // JDWP only allows one step request per thread at a time
            List<StepRequest> existingSteps = erm.stepRequests();
            for (StepRequest existing : existingSteps) {
                if (existing.thread().equals(thread)) {
                    logger.info("[JDWP CLIENT] Deleting existing step request for thread");
                    erm.deleteEventRequest(existing);
                }
            }
            
            StepRequest stepRequest = erm.createStepRequest(thread, StepRequest.STEP_LINE, StepRequest.STEP_INTO);
            // Don't use addCountFilter - let it step naturally
            stepRequest.enable();
            logger.info("[JDWP CLIENT] Step request created and enabled (STEP_INTO, no count filter)");
            logger.info("[JDWP CLIENT] Resuming thread to execute step...");
            
            // CRITICAL: Clear tracking for this thread so we can detect when it suspends again after step
            knownSuspendedThreads.remove(threadName);
            
            thread.resume();
            logger.info("[JDWP CLIENT] ✓✓✓ STEP INTO EXECUTED");
            logger.info("[JDWP CLIENT] Thread will suspend at the first line inside the called method (if any)");
            logger.info("[JDWP CLIENT] Tracking cleared - will detect new suspension after step completes");
            logger.info("========================================");
            // Step will complete and thread will suspend again
        } catch (Exception e) {
            logger.error("[JDWP CLIENT] ✗✗✗ Failed to step into: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to step into: " + e.getMessage(), e);
        }
    }
    
    public void stepOut(String threadName) {
        logger.info("========================================");
        logger.info("[JDWP CLIENT] Executing STEP OUT on thread: {}", threadName);
        logger.info("========================================");
        if (!isConnected()) {
            logger.error("[JDWP CLIENT] ✗ Not connected to JDWP server");
            throw new IllegalStateException("Not connected to JDWP server");
        }
        
        ThreadReference thread = vm.allThreads().stream()
                .filter(t -> t.name().equals(threadName))
                .findFirst()
                .orElseThrow(() -> new RuntimeException("Thread not found: " + threadName));
        
        if (!thread.isSuspended()) {
            logger.error("[JDWP CLIENT] ✗ Thread must be suspended to step");
            throw new IllegalStateException("Thread must be suspended to step");
        }
        
        try {
            StackFrame frame = thread.frame(0);
            Location currentLocation = frame.location();
            logger.info("[JDWP CLIENT] Current location before step: {}:{}:{}", 
                       currentLocation.declaringType().name(), 
                       currentLocation.method().name(), 
                       currentLocation.lineNumber());
            logger.info("[JDWP CLIENT] Stack depth: {}", thread.frameCount());
            
            EventRequestManager erm = vm.eventRequestManager();
            
            // CRITICAL: Delete any existing step requests for this thread first
            // JDWP only allows one step request per thread at a time
            List<StepRequest> existingSteps = erm.stepRequests();
            for (StepRequest existing : existingSteps) {
                if (existing.thread().equals(thread)) {
                    logger.info("[JDWP CLIENT] Deleting existing step request for thread");
                    erm.deleteEventRequest(existing);
                }
            }
            
            StepRequest stepRequest = erm.createStepRequest(thread, StepRequest.STEP_LINE, StepRequest.STEP_OUT);
            // Don't use addCountFilter - let it step naturally
            stepRequest.enable();
            logger.info("[JDWP CLIENT] Step request created and enabled (STEP_OUT, no count filter), resuming thread...");
            
            // CRITICAL: Clear tracking for this thread so we can detect when it suspends again after step
            knownSuspendedThreads.remove(threadName);
            
            thread.resume();
            logger.info("[JDWP CLIENT] ✓✓✓ STEP OUT executed, thread will suspend at caller");
            logger.info("[JDWP CLIENT] Tracking cleared - will detect new suspension after step completes");
            logger.info("========================================");
            // Step will complete and thread will suspend again
        } catch (Exception e) {
            logger.error("[JDWP CLIENT] ✗✗✗ Failed to step out: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to step out: " + e.getMessage(), e);
        }
    }
    
    /**
     * Format a JDI Value to a simple readable string representation
     * Like IntelliJ - shows primitives, strings, arrays/collections simply, objects as type name only
     */
    private String formatValue(Value value, int depth, ThreadReference thread) {
        if (value == null) return "null";
        
        try {
            if (value instanceof StringReference) {
                return "\"" + ((StringReference) value).value() + "\"";
            }
            if (value instanceof PrimitiveValue) {
                return value.toString();
            }
            
            // Handle Arrays
            if (value instanceof ArrayReference) {
                ArrayReference array = (ArrayReference) value;
                int length = array.length();
                if (depth > 0 && length > 5) return "Array[" + length + "]";
                if (length == 0) return "[]";
                
                List<String> elements = new ArrayList<>();
                int displayLen = Math.min(length, 10);
                for (int i = 0; i < displayLen; i++) {
                    elements.add(formatValue(array.getValue(i), depth + 1, thread));
                }
                if (length > 10) elements.add("...");
                return "[" + String.join(", ", elements) + "]";
            }
            
            // Handle Objects: Try to invoke toString()
            if (value instanceof ObjectReference) {
                ObjectReference objRef = (ObjectReference) value;
                ReferenceType refType = objRef.referenceType();
                
                // Avoid invoking toString on basic types we know might be boring or already handled
                if (refType.name().equals("java.lang.Object")) {
                    return "Object";
                }

                // Limit recursion for toString invocation to avoid infinite loops/stack overflow in target VM
                if (depth > 0) {
                     // For nested objects in an array, simple type name is often safer unless it's a Collection
                     if (!refType.name().startsWith("java.util.") && !refType.name().startsWith("java.lang.")) {
                         return refType.name().substring(refType.name().lastIndexOf('.') + 1);
                     }
                }

                try {
                    // Find toString() method
                    Method toStringMethod = null;
                    ReferenceType searchType = refType;
                    while (searchType != null) {
                        List<Method> methods = searchType.methodsByName("toString", "()Ljava/lang/String;");
                        if (!methods.isEmpty()) {
                            toStringMethod = methods.get(0);
                            break;
                        }
                        if (searchType instanceof ClassType) {
                            searchType = ((ClassType) searchType).superclass();
                        } else {
                            break;
                        }
                    }

                    if (toStringMethod != null) {
                        // Invoke toString()
                        Value result = objRef.invokeMethod(thread, toStringMethod, Collections.emptyList(), ObjectReference.INVOKE_SINGLE_THREADED);
                        if (result instanceof StringReference) {
                            return ((StringReference) result).value();
                        }
                    }
                } catch (Exception e) {
                    // If invocation fails (e.g. thread not suspended, exception in toString), fall back
                }
                
                String typeName = refType.name();
                return typeName.substring(typeName.lastIndexOf('.') + 1) + "@" + objRef.uniqueID();
            }
            
            return value.toString();
        } catch (Exception e) {
            return "Error";
        }
    }
    
    public Map<String, Object> getVariablesAtNextLine(String threadName) {
        logger.info("========================================");
        logger.info("[JDWP CLIENT] GETTING VARIABLES");
        logger.info("[JDWP CLIENT] Thread: {}", threadName);
        logger.info("========================================");
        if (!isConnected()) {
            logger.error("[JDWP CLIENT] ✗ Not connected to JDWP server");
            throw new IllegalStateException("Not connected to JDWP server");
        }
        
        ThreadReference thread = vm.allThreads().stream()
                .filter(t -> t.name().equals(threadName))
                .findFirst()
                .orElseThrow(() -> new RuntimeException("Thread not found: " + threadName));
        
        try {
            if (!thread.isSuspended()) {
                logger.info("[JDWP CLIENT] Thread not suspended, suspending...");
                thread.suspend();
            }
            
            List<StackFrame> frames = thread.frames();
            if (frames.isEmpty()) {
                logger.warn("[JDWP CLIENT] No stack frames available");
                return new HashMap<>();
            }
            
            // CRITICAL: ALWAYS use frame 0 if it's application code (where breakpoint actually hit)
            // This ensures we get variables from the EXACT location where execution stopped
            StackFrame frame = null;
            Location location = null;
            
            StackFrame frame0 = frames.get(0);
            Location loc0 = frame0.location();
            String className0 = loc0.declaringType().name();
            
            // Check if frame 0 is application code
            boolean isAppCode0 = !className0.startsWith("jdk.internal.") && 
                !className0.startsWith("java.") && 
                !className0.startsWith("sun.") &&
                !className0.startsWith("com.sun.") &&
                !className0.startsWith("org.apache.") &&
                !className0.startsWith("org.springframework.") &&
                !className0.startsWith("org.eclipse.") &&
                !className0.startsWith("ch.qos.logback.") &&
                !className0.startsWith("org.slf4j.") &&
                loc0.lineNumber() > 0;
            
            if (isAppCode0) {
                // PERFECT: Frame 0 is application code - use it (this is where breakpoint hit)
                frame = frame0;
                location = loc0;
                logger.info("[JDWP CLIENT] ✓ Using frame 0 (breakpoint location): {}:{}:{}", 
                           className0, loc0.method().name(), loc0.lineNumber());
            } else {
                // Frame 0 is framework code, find first application frame
                // But prioritize controller > service > other (like IntelliJ)
                logger.info("[JDWP CLIENT] Frame 0 is framework code ({}), searching for application frame...", className0);
                
                StackFrame controllerFrame = null;
                StackFrame serviceFrame = null;
                StackFrame otherAppFrame = null;
                
                for (StackFrame f : frames) {
                    Location loc = f.location();
                    String className = loc.declaringType().name();
                    
                    if (!className.startsWith("jdk.internal.") && 
                        !className.startsWith("java.") && 
                        !className.startsWith("sun.") &&
                        !className.startsWith("com.sun.") &&
                        !className.startsWith("org.apache.") &&
                        !className.startsWith("org.springframework.") &&
                        !className.startsWith("org.eclipse.") &&
                        !className.startsWith("ch.qos.logback.") &&
                        !className.startsWith("org.slf4j.") &&
                        loc.lineNumber() > 0) {
                        
                        if (className.contains(".controller.") && controllerFrame == null) {
                            controllerFrame = f;
                            logger.info("[JDWP CLIENT] Found controller frame: {}:{}:{}", 
                                      className, loc.method().name(), loc.lineNumber());
                        } else if (className.contains(".service.") && serviceFrame == null && controllerFrame == null) {
                            serviceFrame = f;
                            logger.info("[JDWP CLIENT] Found service frame: {}:{}:{}", 
                                      className, loc.method().name(), loc.lineNumber());
                        } else if (otherAppFrame == null && controllerFrame == null && serviceFrame == null) {
                            otherAppFrame = f;
                            logger.info("[JDWP CLIENT] Found application frame: {}:{}:{}", 
                                      className, loc.method().name(), loc.lineNumber());
                        }
                    }
                }
                
                // Use controller first, then service, then other app code
                if (controllerFrame != null) {
                    frame = controllerFrame;
                    location = controllerFrame.location();
                    logger.info("[JDWP CLIENT] ✓ Using controller frame: {}:{}:{}", 
                              location.declaringType().name(), location.method().name(), location.lineNumber());
                } else if (serviceFrame != null) {
                    frame = serviceFrame;
                    location = serviceFrame.location();
                    logger.info("[JDWP CLIENT] ✓ Using service frame: {}:{}:{}", 
                              location.declaringType().name(), location.method().name(), location.lineNumber());
                } else if (otherAppFrame != null) {
                    frame = otherAppFrame;
                    location = otherAppFrame.location();
                    logger.info("[JDWP CLIENT] ✓ Using other application frame: {}:{}:{}", 
                              location.declaringType().name(), location.method().name(), location.lineNumber());
                } else {
                    // Fallback to frame 0 if no application frame found
                    frame = frame0;
                    location = loc0;
                    logger.warn("[JDWP CLIENT] ✗ No application frame found, falling back to frame 0: {}:{}:{}", 
                              className0, loc0.method().name(), loc0.lineNumber());
                }
            }
            
            String className = location.declaringType().name();
            String methodName = location.method().name();
            int lineNumber = location.lineNumber();
            
            logger.info("[JDWP CLIENT] Current execution context:");
            logger.info("[JDWP CLIENT]   Class: {}", className);
            logger.info("[JDWP CLIENT]   Method: {}", methodName);
            logger.info("[JDWP CLIENT]   Line: {}", lineNumber);
            logger.info("[JDWP CLIENT]   Stack depth: {}", frames.size());
            logger.info("[JDWP CLIENT]   Using frame index: {}", frames.indexOf(frame));
            
            Map<String, Object> variables = new HashMap<>();
            int varCount = 0;
            
            // Skip 'this' reference - not needed like IntelliJ
            
            // Get method arguments/parameters
            try {
                Method method = location.method();
                List<LocalVariable> arguments = method.arguments();
                if (arguments != null && !arguments.isEmpty()) {
                    logger.info("[JDWP CLIENT] Method has {} parameters", arguments.size());
                    for (LocalVariable arg : arguments) {
                        try {
                            Value value = frame.getValue(arg);
                            String valueStr = formatValue(value, 0, thread);
                            String argType = arg.typeName();
                            variables.put(arg.name(), valueStr);
                            varCount++;
                            logger.info("[JDWP CLIENT]   [PARAMETER] {} (type: {}) = {}", arg.name(), argType, valueStr);
                        } catch (Exception e) {
                            logger.debug("[JDWP CLIENT] Could not get parameter {}: {}", arg.name(), e.getMessage());
                        }
                    }
                }
            } catch (Exception e) {
                logger.debug("[JDWP CLIENT] Could not get method arguments: {}", e.getMessage());
            }
            
            // Get all visible local variables
            try {
                logger.info("[JDWP CLIENT] Inspecting local variables in scope at line {}:", lineNumber);
                
                // Wait a bit to ensure thread is fully suspended
                Thread.sleep(100);
                
                // CRITICAL: Get variables visible at the EXACT line number where breakpoint hit
                List<LocalVariable> visibleVars = frame.visibleVariables();
                
                // Also try to get ALL local variables (not just visible at this line)
                // Some variables might be declared earlier but still in scope
                try {
                    Method method = location.method();
                    List<LocalVariable> allLocalVars = method.variables();
                    logger.info("[JDWP CLIENT] Method has {} total local variables (including those declared earlier)", allLocalVars.size());
                    
                    // Add variables that are in scope but might not be "visible" at this exact line
                    for (LocalVariable var : allLocalVars) {
                        try {
                            // Check if variable is in scope at this line
                            if (var.name().equals("this")) continue; // Skip 'this'
                            
                            // Skip if already in visibleVars (will be processed below)
                            boolean alreadyInVisible = visibleVars.stream().anyMatch(v -> v.name().equals(var.name()));
                            if (alreadyInVisible) continue;
                            
                            // Try to get the variable value directly - if it succeeds, it's accessible
                            // This will work even if the variable is not "visible" at this exact line
                            // but is still in scope (declared earlier in the method)
                            Value value = frame.getValue(var);
                            if (!variables.containsKey(var.name())) {
                                String valueStr = formatValue(value, 0, thread);
                                String varType = var.typeName();
                                variables.put(var.name(), valueStr);
                                varCount++;
                                logger.info("[JDWP CLIENT]   ✓ [ADDITIONAL VARIABLE] {} (type: {}) = {} (found via method.variables(), accessible at line {})", 
                                           var.name(), varType, valueStr, lineNumber);
                            }
                        } catch (Exception e) {
                            // Variable not in scope or not accessible - skip
                            logger.debug("[JDWP CLIENT] Variable {} not accessible at line {}: {} - {}", var.name(), lineNumber, e.getClass().getSimpleName(), e.getMessage());
                        }
                    }
                } catch (Exception e) {
                    logger.debug("[JDWP CLIENT] Could not get all method variables: {}", e.getMessage());
                }
                logger.info("[JDWP CLIENT] Found {} visible variables at line {}", visibleVars.size(), lineNumber);
                
                if (visibleVars.isEmpty()) {
                    logger.error("[JDWP CLIENT] ✗✗✗ CRITICAL: No visible variables found!");
                    logger.error("[JDWP CLIENT] This means the server code was NOT compiled with debug information.");
                    logger.error("[JDWP CLIENT] SOLUTION: Rebuild the server using rebuild-and-start.bat");
                    logger.error("[JDWP CLIENT] The server JAR must be rebuilt with -g flag to include variable debug info.");
                }
                
                for (LocalVariable var : visibleVars) {
                    try {
                        // Skip if we already have it (might be a parameter)
                        if (variables.containsKey(var.name())) {
                            logger.debug("[JDWP CLIENT] Skipping duplicate variable: {}", var.name());
                            continue;
                        }
                        
                        // Get variable value
                        Value value = frame.getValue(var);
                        String valueStr = formatValue(value, 0, thread);
                        String varType = var.typeName();
                        
                        variables.put(var.name(), valueStr);
                        varCount++;
                        logger.info("[JDWP CLIENT]   ✓ [VARIABLE #{}/{}] {} (type: {}) = {}", 
                                   varCount, visibleVars.size(), var.name(), varType, valueStr);
                    } catch (Exception e) {
                        logger.warn("[JDWP CLIENT] ✗ Could not get variable {}: {} - {}", var.name(), e.getClass().getSimpleName(), e.getMessage());
                    }
                }
            } catch (AbsentInformationException e) {
                logger.error("[JDWP CLIENT] ✗✗✗ CRITICAL: Local variable information not available!");
                logger.error("[JDWP CLIENT] Code is NOT compiled with debug information (-g flag)");
                logger.error("[JDWP CLIENT] Server must be rebuilt with: mvn clean package (with -g flag in pom.xml)");
                logger.error("[JDWP CLIENT] Error: {}", e.getMessage());
                // Return empty map but log the issue clearly
            } catch (Exception e) {
                logger.error("[JDWP CLIENT] ✗✗✗ Error getting visible variables: {} - {}", e.getClass().getSimpleName(), e.getMessage(), e);
            }
            
            logger.info("[JDWP CLIENT] ✓ Retrieved {} total variables from current scope (this + params + locals)", varCount);
            if (variables.isEmpty()) {
                logger.warn("[JDWP CLIENT] ⚠️  No variables found! This might mean:");
                logger.warn("[JDWP CLIENT]   1. Code not compiled with debug information (-g flag)");
                logger.warn("[JDWP CLIENT]   2. Variables not yet initialized at this line");
                logger.warn("[JDWP CLIENT]   3. Variables optimized away by JVM");
            }
            logger.info("========================================");
            return variables;
        } catch (Exception e) {
            logger.error("[JDWP CLIENT] ✗ Failed to get variables: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to get variables at next line: " + e.getMessage(), e);
        }
    }
    
    public String evaluateExpression(String threadName, String expression) {
        logger.info("========================================");
        logger.info("[JDWP CLIENT] EVALUATING EXPRESSION");
        logger.info("[JDWP CLIENT] Thread: {}", threadName);
        logger.info("[JDWP CLIENT] Expression: {}", expression);
        logger.info("========================================");
        
        if (!isConnected()) {
            logger.error("[JDWP CLIENT] ✗ Not connected to JDWP server");
            throw new IllegalStateException("Not connected to JDWP server");
        }
        
        ThreadReference thread = vm.allThreads().stream()
                .filter(t -> t.name().equals(threadName))
                .findFirst()
                .orElseThrow(() -> new RuntimeException("Thread not found: " + threadName));
        
        try {
            if (!thread.isSuspended()) {
                logger.info("[JDWP CLIENT] Thread not suspended, suspending...");
                thread.suspend();
            }
            
            List<StackFrame> frames = thread.frames();
            if (frames.isEmpty()) {
                throw new RuntimeException("No stack frames available");
            }
            
            // Find first frame in application code (not in jdk.internal, java.*, sun.*, org.apache.*, etc.)
            StackFrame frame = null;
            Location location = null;
            for (StackFrame f : frames) {
                Location loc = f.location();
                String className = loc.declaringType().name();
                // Skip system/internal/framework classes - only show USER application code
                if (!className.startsWith("jdk.internal.") && 
                    !className.startsWith("java.") && 
                    !className.startsWith("sun.") &&
                    !className.startsWith("com.sun.") &&
                    !className.startsWith("org.apache.") &&  // Filter out Tomcat
                    !className.startsWith("org.springframework.") &&  // Filter out Spring framework
                    !className.startsWith("org.eclipse.") &&
                    !className.startsWith("ch.qos.logback.") &&
                    !className.startsWith("org.slf4j.") &&
                    loc.lineNumber() > 0) { // Must have valid line number
                    frame = f;
                    location = loc;
                    break;
                }
            }
            
            // Fallback to first frame if no application frame found
            if (frame == null) {
                frame = frames.get(0);
                location = frame.location();
            }
            
            ReferenceType refType = location.declaringType();
            
            logger.info("[JDWP CLIENT] Evaluating in context:");
            logger.info("[JDWP CLIENT]   Class: {}", refType.name());
            logger.info("[JDWP CLIENT]   Method: {}", location.method().name());
            logger.info("[JDWP CLIENT]   Line: {}", location.lineNumber());
            
            // Use JDI's evaluation capability
            Value result = null;
            try {
                // Try to evaluate as a simple expression
                // Note: JDI doesn't have built-in expression evaluation, so we'll use a workaround
                // We can evaluate field access, method calls on objects in scope
                result = frame.getValue(frame.visibleVariableByName(expression));
                logger.info("[JDWP CLIENT] Expression matched variable: {}", expression);
            } catch (Exception e1) {
                // If not a variable, try to evaluate as a method call or field access
                try {
                    // For simple expressions like "variable.method()" or "variable.field"
                    if (expression.contains(".")) {
                        String[] parts = expression.split("\\.", 2);
                        String varName = parts[0];
                        String member = parts[1];
                        
                        LocalVariable var = frame.visibleVariableByName(varName);
                        Value varValue = frame.getValue(var);
                        
                        if (varValue instanceof ObjectReference) {
                            ObjectReference objRef = (ObjectReference) varValue;
                            ReferenceType type = objRef.referenceType();
                            
                            // Try as method call
                            if (member.endsWith("()")) {
                                String methodName = member.substring(0, member.length() - 2);
                                result = objRef.invokeMethod(thread, type.methodsByName(methodName).get(0), 
                                    Collections.emptyList(), ObjectReference.INVOKE_SINGLE_THREADED);
                            } else {
                                // Try as field access
                                Field field = type.fieldByName(member);
                                result = objRef.getValue(field);
                            }
                        }
                    } else {
                        throw new RuntimeException("Expression not supported: " + expression);
                    }
                } catch (Exception e2) {
                    logger.error("[JDWP CLIENT] Failed to evaluate expression: {}", e2.getMessage());
                    throw new RuntimeException("Failed to evaluate expression: " + e2.getMessage() + 
                        ". Supported: variable names, variable.field, variable.method()", e2);
                }
            }
            
            String resultStr = result != null ? result.toString() : "null";
            String resultType = result != null ? result.type().name() : "null";
            
            logger.info("[JDWP CLIENT] ✓ Expression evaluated successfully");
            logger.info("[JDWP CLIENT]   Result type: {}", resultType);
            logger.info("[JDWP CLIENT]   Result value: {}", resultStr);
            logger.info("========================================");
            
            return resultStr;
        } catch (Exception e) {
            logger.error("[JDWP CLIENT] ✗ Failed to evaluate expression: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to evaluate expression: " + e.getMessage(), e);
        }
    }
    
    public Map<String, Object> getCurrentSourceLocation(String threadName) {
        logger.info("========================================");
        logger.info("[JDWP CLIENT] GETTING CURRENT SOURCE LOCATION");
        logger.info("[JDWP CLIENT] Thread: {}", threadName);
        logger.info("========================================");
        
        if (!isConnected()) {
            logger.error("[JDWP CLIENT] ✗ Not connected to JDWP server");
            throw new IllegalStateException("Not connected to JDWP server");
        }
        
        ThreadReference thread = vm.allThreads().stream()
                .filter(t -> t.name().equals(threadName))
                .findFirst()
                .orElseThrow(() -> new RuntimeException("Thread not found: " + threadName));
        
        try {
            if (!thread.isSuspended()) {
                logger.info("[JDWP CLIENT] Thread not suspended, suspending...");
                thread.suspend();
            }
            
            List<StackFrame> frames = thread.frames();
            if (frames.isEmpty()) {
                throw new RuntimeException("No stack frames available");
            }
            
            // CRITICAL: Frame 0 is where the breakpoint actually hit - show that FIRST
            // This is the exact location where execution stopped
            StackFrame frame = null;
            Location location = null;
            
            // Check frame 0 first - this is the breakpoint location
            StackFrame frame0 = frames.get(0);
            Location loc0 = frame0.location();
            String className0 = loc0.declaringType().name();
            
            // If frame 0 is in application code, use it (this is where breakpoint hit)
            boolean isAppCode0 = !className0.startsWith("jdk.internal.") && 
                !className0.startsWith("java.") && 
                !className0.startsWith("sun.") &&
                !className0.startsWith("com.sun.") &&
                !className0.startsWith("org.apache.") &&
                !className0.startsWith("org.springframework.") &&
                !className0.startsWith("org.eclipse.") &&
                !className0.startsWith("ch.qos.logback.") &&
                !className0.startsWith("org.slf4j.") &&
                loc0.lineNumber() > 0;
            
            if (isAppCode0) {
                frame = frame0;
                location = loc0;
                logger.info("[JDWP CLIENT] ✓ Using frame 0 (breakpoint location): {}:{}:{}", 
                           className0, loc0.method().name(), loc0.lineNumber());
            } else {
                // Frame 0 is in framework code, find first application frame
                // PRIORITIZE: Controller frames over Service frames (like IntelliJ)
                logger.info("[JDWP CLIENT] Frame 0 is in framework code ({}), searching for application frame...", className0);
                
                StackFrame controllerFrame = null;
                StackFrame serviceFrame = null;
                StackFrame otherAppFrame = null;
                
                for (StackFrame f : frames) {
                    Location loc = f.location();
                    String className = loc.declaringType().name();
                    
                    // Check if it's application code
                    if (!className.startsWith("jdk.internal.") && 
                        !className.startsWith("java.") && 
                        !className.startsWith("sun.") &&
                        !className.startsWith("com.sun.") &&
                        !className.startsWith("org.apache.") &&
                        !className.startsWith("org.springframework.") &&
                        !className.startsWith("org.eclipse.") &&
                        !className.startsWith("ch.qos.logback.") &&
                        !className.startsWith("org.slf4j.") &&
                        loc.lineNumber() > 0) {
                        
                        // Prioritize controller over service
                        if (className.contains(".controller.") && controllerFrame == null) {
                            controllerFrame = f;
                            logger.info("[JDWP CLIENT] Found controller frame: {}:{}:{}", 
                                       className, loc.method().name(), loc.lineNumber());
                        } else if (className.contains(".service.") && serviceFrame == null && controllerFrame == null) {
                            serviceFrame = f;
                            logger.info("[JDWP CLIENT] Found service frame: {}:{}:{}", 
                                       className, loc.method().name(), loc.lineNumber());
                        } else if (otherAppFrame == null && controllerFrame == null && serviceFrame == null) {
                            otherAppFrame = f;
                            logger.info("[JDWP CLIENT] Found application frame: {}:{}:{}", 
                                       className, loc.method().name(), loc.lineNumber());
                        }
                    }
                }
                
                // Use controller first, then service, then other app code
                if (controllerFrame != null) {
                    frame = controllerFrame;
                    location = controllerFrame.location();
                } else if (serviceFrame != null) {
                    frame = serviceFrame;
                    location = serviceFrame.location();
                } else if (otherAppFrame != null) {
                    frame = otherAppFrame;
                    location = otherAppFrame.location();
                } else {
                    // Fallback to frame 0 if no application frame found
                    frame = frame0;
                    location = loc0;
                    logger.info("[JDWP CLIENT] No application frame found, using frame 0: {}:{}:{}", 
                               className0, loc0.method().name(), loc0.lineNumber());
                }
            }
            
            ReferenceType refType = location.declaringType();
            
            String className = refType.name();
            String methodName = location.method().name();
            int lineNumber = location.lineNumber();
            String sourceName = null;
            
            try {
                sourceName = location.sourceName();
            } catch (Exception e) {
                logger.debug("[JDWP CLIENT] Source name not available: {}", e.getMessage());
            }
            
            Map<String, Object> locationInfo = new HashMap<>();
            locationInfo.put("className", className);
            locationInfo.put("methodName", methodName);
            locationInfo.put("lineNumber", lineNumber);
            locationInfo.put("sourceName", sourceName);
            
            logger.info("[JDWP CLIENT] Current location:");
            logger.info("[JDWP CLIENT]   Class: {}", className);
            logger.info("[JDWP CLIENT]   Method: {}", methodName);
            logger.info("[JDWP CLIENT]   Line: {}", lineNumber);
            logger.info("[JDWP CLIENT]   Source: {}", sourceName != null ? sourceName : "N/A");
            logger.info("========================================");
            
            return locationInfo;
        } catch (Exception e) {
            logger.error("[JDWP CLIENT] ✗ Failed to get source location: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to get source location: " + e.getMessage(), e);
        }
    }
    
    private String getThreadStatusString(int status) {
        switch (status) {
            case ThreadReference.THREAD_STATUS_MONITOR:
                return "MONITOR";
            case ThreadReference.THREAD_STATUS_NOT_STARTED:
                return "NOT_STARTED";
            case ThreadReference.THREAD_STATUS_RUNNING:
                return "RUNNING";
            case ThreadReference.THREAD_STATUS_SLEEPING:
                return "SLEEPING";
            case ThreadReference.THREAD_STATUS_UNKNOWN:
                return "UNKNOWN";
            case ThreadReference.THREAD_STATUS_WAIT:
                return "WAIT";
            case ThreadReference.THREAD_STATUS_ZOMBIE:
                return "ZOMBIE";
            default:
                return "UNKNOWN(" + status + ")";
        }
    }
}

