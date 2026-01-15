# Variables Not Showing - Fix Required

## Problem
Variables like `a=20` and `name="manish"` are not showing up in the debugger.

## Root Cause Analysis

1. **Server Rebuild**: Server was rebuilt with debug info (`-g` flag)
2. **Docker Rebuild**: Docker container was rebuilt with new JAR
3. **Variable Retrieval**: Code uses `frame.visibleVariables()` which should work

## Expected Variables

### At UserController:31
- `a` = 20 (int, declared at line 28, assigned at line 29)

### At UserService:64  
- `name` = "manish" (String, declared and assigned at line 63)

## Fix Required

The issue is likely that:
1. Variables are not in scope at the exact breakpoint line
2. The breakpoint needs to be at a line AFTER the variable is assigned
3. The server needs to be restarted after rebuild

## Solution

1. Move breakpoint to line 32 (after `a=20` is assigned)
2. For UserService, breakpoint at line 64 is correct (after `name="manish"`)
3. Ensure server is restarted with new JAR
4. Test and verify variables show up
