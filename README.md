# SaNa

Developer-focused conversational intelligence (voice-first, not voice-only).

## Status

- Phase 0: local prerequisites verified
- Phase 2 (in progress): Flutter foundation, dark design system, orb shell

See [`PRD.md`](./PRD.md) for product architecture and phased plan.

## Repository

https://github.com/saisree510/SaNa-Voice-Intelligence

## Run (Android)

```powershell
flutter emulators --launch sana_api36
flutter pub get
flutter run -d emulator-5554
```

Copy `.env.example` to `.env` for later backend/LLM configuration. Never commit `.env`.
