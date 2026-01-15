# Verification: Step Over vs Continue

## Expected Behavior

### Step Over (F10)
- **Should**: Step ONE line forward in the current method
- **Should NOT**: Continue until breakpoint
- **Implementation**: Uses `StepRequest.STEP_OVER` with `STEP_LINE`
- **Behavior**: Steps to next executable line in same method, steps over method calls

### Continue (F5)  
- **Should**: Resume execution until NEXT breakpoint is hit
- **Should NOT**: Step one line
- **Implementation**: Calls `vm.resume()` after clearing ALL step requests
- **Behavior**: Continues execution, only stops at breakpoints

## Test Scenario

### Setup
1. Set breakpoint at `UserController:31` (line with `logger.info("[DEBUG] About to call...")`)
2. Set breakpoint at `UserService:64` (line with `String name="manish";`)

### Test Step Over
1. Hit breakpoint at line 31
2. Click "Step Over"
3. **Expected**: Should step to line 32 (next line: `List<User> users = userService.getAllUsers();`)
4. **NOT Expected**: Should NOT continue to line 64 breakpoint

### Test Continue
1. Hit breakpoint at line 31
2. Click "Continue (F5)"
3. **Expected**: Should continue execution and hit breakpoint at line 64 (in UserService)
4. **NOT Expected**: Should NOT stop at line 32

## Implementation Details

### Step Over (`stepOver()`)
- Creates `StepRequest` with `STEP_OVER` and `STEP_LINE`
- Resumes thread
- Thread suspends at next executable line in same method
- Step request is automatically disabled after step completes

### Continue (`continueExecution()`)
- **CRITICAL**: Deletes ALL active step requests first
- Calls `vm.resume()` to resume entire VM
- Execution continues until breakpoint is hit
- No step requests active = no line-by-line stopping

## Fix Applied

Added step request cleanup in `continueExecution()`:
```java
// Delete ALL step requests before continuing
EventRequestManager erm = vm.eventRequestManager();
List<StepRequest> allStepRequests = erm.stepRequests();
for (StepRequest stepRequest : allStepRequests) {
    erm.deleteEventRequest(stepRequest);
}
vm.resume();
```

This ensures Continue doesn't have any step requests that would cause it to stop at next line.
