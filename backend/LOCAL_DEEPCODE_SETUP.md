# Local DeepCode Setup Guide

## Problem
DeepCode running in Railway container gets blocked by "agent is running remotely" error. The deepcode-hku package has sandbox restrictions on containerized/remote execution.

## Solution
Run DeepCode locally where it can write to disk, then test the full build pipeline locally.

## Prerequisites
- DeepCode CLI installed locally: `deepcode` command available on PATH
- OpenRouter API key configured
- Python 3.12+ with venv
- Backend dependencies installed

## Step 1: Configure Local DeepCode

```bash
# Initialize DeepCode (interactive)
deepcode init

# Register the OpenRouter connection
deepcode provider set openrouter \
  --template openrouter \
  --api-key-env OPENROUTER_API_KEY
```

## Step 2: Create `.env` for Local Backend

Create `/backend/.env.local`:

```env
# Enable real DeepCode instead of Prototype Scaffold
DEEPCODE_ENABLED=true
DEEPCODE_BINARY_PATH=deepcode
DEEPCODE_CONNECTION=openrouter
DEEPCODE_PROVIDER_TEMPLATE=openrouter
DEEPCODE_API_KEY_ENV=OPENROUTER_API_KEY

# OpenRouter API Key (replace with your actual key)
OPENROUTER_API_KEY=<your-openrouter-key>

# Build storage (local drafts folder)
BUILD_STORAGE_ROOT=./drafts

# Supabase settings (use Railway values or local test)
SUPABASE_URL=<your-supabase-url>
SUPABASE_SERVICE_ROLE_KEY=<your-service-role-key>

# LocalHost binding for local testing
ENVIRONMENT=development
PORT=8000
CORS_ORIGINS=["http://localhost:3000","http://localhost:8080","http://127.0.0.1:*"]
```

## Step 3: Start Local Backend

```bash
cd backend

# Activate venv if needed
python -m venv venv
source venv/bin/activate  # or venv\Scripts\activate on Windows

# Install dependencies
pip install -e .

# Run the backend
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

Backend should log:
```
INFO:     Uvicorn running on http://127.0.0.1:8000
INFO:     Application startup complete
```

## Step 4: Configure Mobile App to Use Local Backend

In `mobile/lib/services/token_service.dart`, during development, change:

```dart
String get backendUrl {
  // For LOCAL TESTING: point to your machine's IP
  // return 'http://192.168.x.x:8000';  // <-- Use your machine's actual IP
  return _backend Url ?? 'https://sana-backend-production.up.railway.app';
}
```

Or better yet, use an environment variable:
```dart
String get backendUrl {
  const String? devBackend = String.fromEnvironment('BACKEND_URL');
  return devBackend ?? _backendUrl ?? 'https://sana-backend-production.up.railway.app';
}
```

Then run Flutter with:
```bash
flutter run -d chrome \
  --dart-define=BACKEND_URL=http://192.168.1.100:8000
```

## Step 5: Test Build Execution

1. Open the app → Orb tab → Create a new project
2. Fill in: Title, Components, Connections
3. Approve & Build
4. Watch the canvas update in real-time as DeepCode generates files
5. Files should appear in `./drafts/users/<user-id>/<project-id>/` on your machine

## Step 6: Monitor Logs

Watch the backend logs for:
- `DeepCodeRuntimeAdapter[...] invoking: deepcode exec --workspace ...`
- NDJSON events streaming through (tool_started, file_create, etc.)
- Final build completion with generated file count

If you see "agent is running remotely", that's the container sandbox issue—but it won't happen running locally.

## Troubleshooting

### DeepCode can't find binary
```bash
which deepcode
# Should output: /path/to/deepcode
```

### OpenRouter provider not registered
```bash
deepcode provider list
# Should show: openrouter (configured)

# If not, run setup again:
deepcode provider set openrouter --template openrouter --api-key-env OPENROUTER_API_KEY
```

### Backend not connecting to Supabase
- Verify SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are correct
- Or disable auth checks temporarily for local testing

### Mobile app can't reach backend
- Check your machine's local IP: `ipconfig` (Windows) or `ifconfig` (Mac/Linux)
- Make sure firewall allows port 8000
- Try `http://localhost:8000` if on same machine

## What to Watch For

When a build starts:
1. Canvas should show "Canvas loading" → "Canvas ready"
2. Event log should stream events in real-time:
   - "Build execution started"
   - "Tool: FileWriter — Creating files"
   - "✓ FileWriter: 5 files created"
   - "Build execution completed using deepcode"
3. Architecture should display live components
4. No delete dialog should appear (read-only mode active)
5. Files should appear in workspace after build completes

## Next Steps After Local Testing

Once local testing works:
1. Verify full build pipeline with real code generation
2. Test canvas live updates with actual component detection
3. Confirm file generation and project structure
4. Then redeploy to Railway with fixes (or find deepcode-hku alternative)
