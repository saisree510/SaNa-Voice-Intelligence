# Real-Time Build Streaming via Server-Sent Events (SSE)

## Overview

The `/v1/build/projects/{project_id}/stream` endpoint executes a build and streams progress events in real-time using Server-Sent Events (SSE).

## Endpoint

```
POST /v1/build/projects/{project_id}/stream
```

**Authentication:** Required (Bearer token)

**Response Content-Type:** `text/event-stream`

## Events

Each event is a JSON object sent as an SSE `data:` line:

```json
{
  "event_type": "start|tool_start|tool_complete|file_create|file_edit|file_delete|command|test_result|log|agent_message|usage|complete|error",
  "message": "Human-readable message",
  "details": { "key": "value" },
  "timestamp": "2026-08-23T10:30:00Z",
  "provider": "deepcode|prototype_scaffold"
}
```

### Event Types

- **start** — Build execution started
- **tool_start** — An agent tool invocation started (e.g., file write, command execution)
- **tool_complete** — Tool invocation finished successfully
- **file_create** — A new file was created
- **file_edit** — An existing file was modified
- **file_delete** — A file was deleted
- **command** — A shell/CLI command was executed
- **test_result** — A test suite ran with pass/fail results
- **log** — Generic log message from the build process
- **agent_message** — A message directly from the coding agent
- **usage** — Token/resource usage summary
- **complete** — Build finished successfully; includes `generated_files: [...]`
- **error** — Build failed; includes error message in `message` field

## Flutter Example

```dart
import 'package:http/http.dart' as http;

Future<void> streamBuildExecution(String projectId, String token) async {
  final uri = Uri.parse('https://your-backend.up.railway.app/v1/build/projects/$projectId/stream');
  
  final request = http.Request('POST', uri)
    ..headers['Authorization'] = 'Bearer $token'
    ..headers['Accept'] = 'text/event-stream';

  try {
    final response = await request.send();
    
    if (response.statusCode != 200) {
      print('Stream failed: ${response.statusCode}');
      return;
    }

    // Listen to SSE events
    response.stream
      .transform(utf8.decoder)
      .transform(LineSplitter())
      .listen((line) {
        if (line.startsWith('data: ')) {
          final jsonStr = line.substring(6); // Remove 'data: ' prefix
          final event = jsonDecode(jsonStr);
          
          // Handle event
          print('Event: ${event['event_type']} - ${event['message']}');
          
          if (event['event_type'] == 'complete') {
            print('Build complete! Generated files: ${event['generated_files']}');
          } else if (event['event_type'] == 'error') {
            print('Build failed: ${event['message']}');
          }
        }
      });
  } catch (e) {
    print('Stream error: $e');
  }
}
```

## JavaScript/Web Example

```javascript
async function streamBuild(projectId, token) {
  const response = await fetch(
    `/v1/build/projects/${projectId}/stream`,
    {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${token}` },
    }
  );

  if (!response.ok) throw new Error(`Stream failed: ${response.status}`);

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  
  let buffer = '';
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';
    
    for (const line of lines) {
      if (line.startsWith('data: ')) {
        const event = JSON.parse(line.substring(6));
        console.log(`${event.event_type}: ${event.message}`);
        
        if (event.event_type === 'complete') {
          console.log('✅ Build complete');
        } else if (event.event_type === 'error') {
          console.error('❌ Build failed');
        }
      }
    }
  }
}
```

## Backend Implementation Details

The stream endpoint:
1. **Validates** the project exists and user has access
2. **Checks** project status is `plan_generated` (pending approval)
3. **Creates** a new run with a unique `run_id`
4. **Streams** each event from the coding adapter (DeepCode or Scaffold) in real-time
5. **Updates** project status to `building` during execution, then `completed` or `failed` on finish
6. **Stores** the run history and artifact archive on completion

If the build fails mid-stream, the last event will be `error` type with the exception message.

## Benefits Over Polling

- **Real-time:** No delay waiting for polls
- **Bandwidth efficient:** Only sends events when something happens
- **Connection-aware:** Server can detect client disconnect
- **Mobile-friendly:** Works over HTTP with less battery drain than polling loops
