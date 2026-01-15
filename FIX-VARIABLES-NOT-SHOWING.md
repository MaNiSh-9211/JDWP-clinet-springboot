# FIX: Variables Not Showing in Debugger

## Problem
Variables are not showing in the debugger scope panel. Logs show:
```
[JDWP CLIENT] Found 0 visible variables at line 31
```

## Root Cause
The server JAR file was NOT compiled with debug information (`-g` flag). Without debug info, JDI cannot retrieve local variable names and values.

## Solution - MUST REBUILD SERVER

### Step 1: Rebuild Server with Debug Info
Run the rebuild script which now includes server rebuild:
```bash
.\rebuild-and-start.bat
```

This script will:
1. Rebuild server JAR with `-g` flag (full debug info)
2. Rebuild Docker image with new JAR
3. Start everything

### Step 2: Verify Debug Info is Present
After rebuild, check the logs when hitting a breakpoint. You should see:
```
[JDWP CLIENT] Found X visible variables at line 31
[JDWP CLIENT]   ✓ [VARIABLE #1/X] a (type: int) = 20
```

### What Was Fixed

1. **server/pom.xml**:
   - Added explicit `-g` compiler flag
   - Added `debuglevel=lines,vars,source`
   - Added Maven properties for debug

2. **rebuild-and-start.bat**:
   - Added Step 2: Rebuild server JAR before Docker build
   - Ensures fresh JAR with debug info is used

3. **Client logging**:
   - Better error messages when debug info is missing
   - Clear instructions on what to do

## Important Notes

- **You MUST rebuild the server** - just restarting won't work
- The old JAR file doesn't have debug info
- Docker image must be rebuilt to use the new JAR
- After rebuild, variables will show correctly

## Verification

After rebuilding, when you hit a breakpoint at line 31 in UserController:
- Variable `a = 20` should be visible
- Variable `name = "manish"` should be visible in UserService line 64

If variables still don't show, check:
1. Server was actually rebuilt (check timestamps on JAR file)
2. Docker image was rebuilt (not using cached image)
3. Server container is running the new image
