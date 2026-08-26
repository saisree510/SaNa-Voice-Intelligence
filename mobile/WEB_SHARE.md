# Web Deployment

The Flutter web app is the primary Soul client. It uses the Railway backend by default:

`https://sana-voice-intelligence-production.up.railway.app`

## User flow

1. The user opens the public HTTPS URL in a modern browser.
2. The app signs them in with Supabase.
3. The app calls the Railway backend for a LiveKit token.
4. The browser connects directly to LiveKit for voice.
5. Build Projects are stored and listed on Railway under that user account.

## Production build

Run this from `mobile/`:

```powershell
flutter build web --dart-define=SANA_BACKEND_URL=https://sana-voice-intelligence-production.up.railway.app
```

The URL above is also the web client's production default. Keep the explicit
`--dart-define` in deployment automation so the target is visible and easy to
change.

The deployable output is:

`mobile/build/web`

## Free static hosting

Netlify Drop is the fastest option:

1. Open `app.netlify.com/drop`.
2. Drag the contents of `mobile/build/web` or the folder itself into the page.
3. Netlify gives you a public HTTPS URL.
4. Share that URL with any desktop or mobile browser user.

The app needs HTTPS for microphone access. Netlify, Vercel, and Cloudflare Pages all provide that.

## Files added for static hosting

- `mobile/web/_redirects`: ensures SPA routing falls back to `index.html` on Netlify.
- `mobile/web/_headers`: sets simple security and microphone-related headers for static hosting.

## Notes

- Supabase web auth settings must allow the final hosted domain in redirect or allowed URL settings if email or OAuth flows are used.
- Railway CORS is already open, so the hosted web origin can call the backend.
- If a new version is built, redeploy the fresh `mobile/build/web` output.
- The browser will ask for microphone permission when the user starts a voice session.
- Reload an already-open tab after deployment to pick up the newest web bundle.
