# API Breakpoints Reference Guide

This file lists all available API endpoints with their corresponding class names and line numbers where you can set breakpoints for debugging.

## 📋 Quick Reference Table

| API Endpoint | Method | Controller Class | Controller Line | Service Class | Service Lines | Description |
|--------------|--------|------------------|-----------------|---------------|---------------|-------------|
| GET /api/users | GET | `com.jdwp.server.controller.UserController` | 31 | `com.jdwp.server.service.UserService` | 64, 81 | Get all users |
| GET /api/users/{id} | GET | `com.jdwp.server.controller.UserController` | 50 | `com.jdwp.server.service.UserService` | 81, 95 | Get user by ID |
| POST /api/users | POST | `com.jdwp.server.controller.UserController` | 77 | `com.jdwp.server.service.UserService` | 105, 135 | Create new user |
| PUT /api/users/{id} | PUT | `com.jdwp.server.controller.UserController` | 101 | `com.jdwp.server.service.UserService` | 135, 165 | Update user |
| DELETE /api/users/{id} | DELETE | `com.jdwp.server.controller.UserController` | 124 | `com.jdwp.server.service.UserService` | 174, 190 | Delete user |

---

## 🔍 Detailed Breakpoint Locations

### 1. GET /api/users - Get All Users

**Purpose**: Retrieve all users from the database

**Breakpoint Locations**:
- **Controller Entry Point**:
  - Class: `com.jdwp.server.controller.UserController`
  - Line: **31**
  - Description: Entry point in `getAllUsers()` method, right before calling service
  
- **Service Method Start**:
  - Class: `com.jdwp.server.service.UserService`
  - Line: **64**
  - Description: Start of `getAllUsers()` service method, loading users from file
  
- **Service Method Return**:
  - Class: `com.jdwp.server.service.UserService`
  - Line: **81**
  - Description: Returning users list (if you want to inspect the result)

**Recommended Breakpoints**: Set all 3 to trace the full flow from controller → service → return

---

### 2. GET /api/users/{id} - Get User by ID

**Purpose**: Retrieve a specific user by their ID

**Breakpoint Locations**:
- **Controller Entry Point**:
  - Class: `com.jdwp.server.controller.UserController`
  - Line: **50**
  - Description: Entry point in `getUserById()` method, parameter `id` is available
  
- **Service Method Start**:
  - Class: `com.jdwp.server.service.UserService`
  - Line: **81**
  - Description: Start of `getUserById()` service method, searching for user
  
- **Service Method Return**:
  - Class: `com.jdwp.server.service.UserService`
  - Line: **95**
  - Description: Returning found user or null

**Recommended Breakpoints**: Set all 3 to debug user lookup flow

---

### 3. POST /api/users - Create New User

**Purpose**: Create a new user

**Breakpoint Locations**:
- **Controller Entry Point**:
  - Class: `com.jdwp.server.controller.UserController`
  - Line: **77**
  - Description: Entry point in `createUser()` method, request body `user` is available
  
- **Service Method Start**:
  - Class: `com.jdwp.server.service.UserService`
  - Line: **105**
  - Description: Start of `createUser()` service method, validating and assigning ID
  
- **Service Method Save**:
  - Class: `com.jdwp.server.service.UserService`
  - Line: **135**
  - Description: Saving user to file (after ID assignment)

**Recommended Breakpoints**: Set all 3 to debug user creation flow

---

### 4. PUT /api/users/{id} - Update User

**Purpose**: Update an existing user

**Breakpoint Locations**:
- **Controller Entry Point**:
  - Class: `com.jdwp.server.controller.UserController`
  - Line: **101**
  - Description: Entry point in `updateUser()` method, parameters `id` and `user` available
  
- **Service Method Find**:
  - Class: `com.jdwp.server.service.UserService`
  - Line: **135**
  - Description: Finding existing user to update
  
- **Service Method Update**:
  - Class: `com.jdwp.server.service.UserService`
  - Line: **165**
  - Description: Updating user fields and saving

**Recommended Breakpoints**: Set all 3 to debug user update flow

---

### 5. DELETE /api/users/{id} - Delete User

**Purpose**: Delete a user by ID

**Breakpoint Locations**:
- **Controller Entry Point**:
  - Class: `com.jdwp.server.controller.UserController`
  - Line: **124**
  - Description: Entry point in `deleteUser()` method, parameter `id` is available
  
- **Service Method Find**:
  - Class: `com.jdwp.server.service.UserService`
  - Line: **174**
  - Description: Finding user to delete
  
- **Service Method Remove**:
  - Class: `com.jdwp.server.service.UserService`
  - Line: **190**
  - Description: Removing user and saving updated list

**Recommended Breakpoints**: Set all 3 to debug user deletion flow

---

## 🎯 How to Use This Reference

### Option 1: Use the UI Dropdown (Recommended)
1. Connect to the debugger
2. Go to "Breakpoints" panel
3. Select an API from the dropdown (e.g., "GET /api/users")
4. Click "Set All Breakpoints" - automatically sets all breakpoints for that API

### Option 2: Manual Entry
1. Go to "Breakpoints" panel
2. Use the "Add Single Breakpoint" section
3. Enter class name and line number from this reference
4. Click "Add Breakpoint"

### Example: Debugging GET /api/users

**Quick Setup**:
- Select "GET /api/users" from dropdown
- Click "Set All Breakpoints"
- This sets 3 breakpoints:
  1. `UserController:31` (Controller entry)
  2. `UserService:64` (Service start)
  3. `UserService:81` (Service return)

**Manual Setup**:
- Breakpoint 1: Class `com.jdwp.server.controller.UserController`, Line `31`
- Breakpoint 2: Class `com.jdwp.server.service.UserService`, Line `64`
- Breakpoint 3: Class `com.jdwp.server.service.UserService`, Line `81`

---

## 📝 Notes

- **Line numbers** may vary slightly if code changes. Always verify in your IDE.
- **Multiple breakpoints** per API help you trace the full execution flow.
- **Scope variables** are automatically loaded when a breakpoint is hit.
- **Step operations** (Over/Into/Out) work at any breakpoint location.
- **Evaluate expressions** can access variables in the current scope.

---

## 🔧 Adding Your Own APIs

To add breakpoints for a new API:

1. Edit `api-breakpoints-config.json`
2. Add entry under `apiEndpoints`:
```json
{
  "GET /api/new-endpoint": {
    "description": "Your API description",
    "breakpoints": [
      {
        "className": "com.jdwp.server.controller.NewController",
        "lineNumber": 50,
        "description": "Entry point"
      }
    ]
  }
}
```

3. Update this reference file with the new API details
