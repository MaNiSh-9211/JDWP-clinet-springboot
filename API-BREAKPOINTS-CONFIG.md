# API Breakpoints Configuration

This file (`api-breakpoints-config.json`) maps API endpoints to their corresponding breakpoint locations in the codebase.

## Structure

```json
{
  "apiEndpoints": {
    "API_NAME": {
      "description": "Description of the API",
      "breakpoints": [
        {
          "className": "fully.qualified.ClassName",
          "lineNumber": 31,
          "description": "What this breakpoint is for"
        }
      ]
    }
  }
}
```

## Current Configuration

The file includes breakpoints for:
- `GET /api/users` - 3 breakpoints (Controller + Service)
- `GET /api/users/{id}` - 3 breakpoints
- `POST /api/users` - 3 breakpoints
- `PUT /api/users/{id}` - 3 breakpoints
- `DELETE /api/users/{id}` - 3 breakpoints

## Usage in UI

1. Connect to the debugger
2. In the "Breakpoints" panel, select an API from the dropdown
3. Click "Set All Breakpoints" to set all breakpoints for that API at once
4. All breakpoints will be set across multiple files (Controller and Service layers)

## Adding New APIs

To add breakpoints for a new API:

1. Edit `api-breakpoints-config.json`
2. Add a new entry under `apiEndpoints`
3. Specify the API name (e.g., `"GET /api/new-endpoint"`)
4. Add breakpoint objects with:
   - `className`: Full class name (e.g., `com.jdwp.server.controller.NewController`)
   - `lineNumber`: Line number where breakpoint should be set
   - `description`: Human-readable description

## Example

```json
{
  "apiEndpoints": {
    "GET /api/new-endpoint": {
      "description": "New endpoint description",
      "breakpoints": [
        {
          "className": "com.jdwp.server.controller.NewController",
          "lineNumber": 50,
          "description": "Entry point in controller"
        },
        {
          "className": "com.jdwp.server.service.NewService",
          "lineNumber": 100,
          "description": "Service method execution"
        }
      ]
    }
  }
}
```

## Location

- Source: `api-breakpoints-config.json` (root directory)
- Resource: `client/src/main/resources/api-breakpoints-config.json` (packaged in JAR)
