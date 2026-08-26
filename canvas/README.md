# Soul Architecture Canvas proof

This bounded React/Vite module is the Phase C2 standalone proof for Soul's Overview Architecture canvas. It uses the MIT-licensed `@excalidraw/excalidraw` package and renders a local, provider-neutral Blueprint through mock validated operations.

It does not contain Soul authentication, persistence, WebSockets or Flutter embedding. Those responsibilities start in later Phase C checkpoints.

## Run locally

```powershell
cd canvas
npm.cmd install
npm.cmd run dev
```

## Verify

```powershell
npm.cmd run build
```

The proof includes Excalidraw zoom, pan, selection and fullscreen controls; progressive local node/edge creation; replay controls; an accessible text summary; and reduced-motion handling.
