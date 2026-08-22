import { useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { Excalidraw } from "@excalidraw/excalidraw";
import { mockOperations, overviewBlueprint } from "./blueprint";
import { sceneForOperations } from "./scene";
import "./styles.css";

window.EXCALIDRAW_ASSET_PATH = "/excalidraw-assets/";

const PROTOCOL_VERSION = 1;
const CANVAS_SOURCE = "soul-canvas";
const FLUTTER_SOURCE = "soul-flutter";

function postToParent(type, payload = {}) {
  if (window.parent === window) return;
  window.parent.postMessage(
    JSON.stringify({ protocolVersion: PROTOCOL_VERSION, source: CANVAS_SOURCE, type, payload }),
    window.location.origin,
  );
}

function CanvasProof() {
  const [step, setStep] = useState(0);
  const [playing, setPlaying] = useState(true);
  const [speed, setSpeed] = useState(1);
  const [reducedMotion, setReducedMotion] = useState(false);
  const apiRef = useRef(null);
  const isEmbedded = new URLSearchParams(window.location.search).get("embed") === "1";

  useEffect(() => {
    if (!isEmbedded) return undefined;
    postToParent("soul.canvas.ready", {
      blueprintId: overviewBlueprint.id,
      operationCount: mockOperations.length,
    });

    const handleMessage = (event) => {
      if (typeof event.data !== "string") return;
      let message;
      try {
        message = JSON.parse(event.data);
      } catch {
        return;
      }
      if (event.origin !== window.location.origin || message?.source !== FLUTTER_SOURCE) return;
      if (message.protocolVersion !== PROTOCOL_VERSION) return;

      switch (message.type) {
        case "soul.canvas.parent_ready":
          postToParent("soul.canvas.ack", { received: message.type });
          break;
        case "soul.canvas.command":
          if (message.payload?.command === "fit") fitToContent();
          if (message.payload?.command === "replay") reset();
          if (message.payload?.command === "pause") setPlaying(false);
          if (message.payload?.command === "play" && !reducedMotion && step < mockOperations.length) {
            setPlaying(true);
          }
          postToParent("soul.canvas.ack", { received: message.payload?.command ?? "unknown" });
          break;
        default:
          postToParent("soul.canvas.rejected", { reason: "unsupported_type", type: message.type });
      }
    };

    window.addEventListener("message", handleMessage);
    return () => window.removeEventListener("message", handleMessage);
  }, [isEmbedded, reducedMotion, step]);

  useEffect(() => {
    const mediaQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    const updatePreference = () => setReducedMotion(mediaQuery.matches);
    updatePreference();
    mediaQuery.addEventListener("change", updatePreference);
    return () => mediaQuery.removeEventListener("change", updatePreference);
  }, []);

  useEffect(() => {
    if (reducedMotion) {
      setPlaying(false);
      setStep(mockOperations.length);
    }
  }, [reducedMotion]);

  useEffect(() => {
    if (!playing || step >= mockOperations.length || reducedMotion) return undefined;
    const timer = window.setTimeout(() => setStep((current) => current + 1), 1100 / speed);
    return () => window.clearTimeout(timer);
  }, [playing, reducedMotion, speed, step]);

  const elements = sceneForOperations(overviewBlueprint, mockOperations.slice(0, step));

  useEffect(() => {
    apiRef.current?.updateScene({ elements });
  }, [elements]);

  useEffect(() => {
    if (!isEmbedded) return;
    postToParent("soul.canvas.state", {
      status: step < mockOperations.length ? "drawing" : "complete",
      appliedOperations: step,
      totalOperations: mockOperations.length,
    });
  }, [isEmbedded, step]);

  const reset = () => {
    setStep(0);
    setPlaying(!reducedMotion);
  };

  const fitToContent = () => apiRef.current?.scrollToContent(elements, { fitToContent: true, animate: !reducedMotion });

  return (
    <main className={`canvas-proof${isEmbedded ? " is-embedded" : ""}`}>
      {!isEmbedded && <header className="canvas-header">
        <div>
          <p className="eyebrow">Soul / Overview Architecture</p>
          <h1>Architecture Blueprint</h1>
          <p className="status" aria-live="polite">{step < mockOperations.length ? "Drawing validated operations" : "Blueprint preview complete"}</p>
        </div>
        <div className="controls" aria-label="Canvas proof controls">
          <button type="button" onClick={() => setPlaying((current) => !current)} disabled={reducedMotion || step >= mockOperations.length}>
            {playing ? "Pause" : "Play"}
          </button>
          <button type="button" onClick={reset}>Replay</button>
          <button type="button" onClick={fitToContent} disabled={!elements.length}>Fit diagram</button>
          <label>
            Speed
            <select value={speed} onChange={(event) => setSpeed(Number(event.target.value))} disabled={reducedMotion}>
              <option value={1}>1x</option>
              <option value={2}>2x</option>
            </select>
          </label>
        </div>
      </header>}
      <section className="canvas-stage" aria-label="Interactive Overview Architecture canvas">
        <Excalidraw
          excalidrawAPI={(api) => { apiRef.current = api; }}
          initialData={{
            elements,
            appState: {
              gridSize: null,
              viewBackgroundColor: "#fdfcff",
            },
          }}
          UIOptions={{ canvasActions: { loadScene: false, saveToActiveFile: false, export: false } }}
        />
      </section>
      {!isEmbedded && <section className="accessible-summary" aria-label="Architecture Blueprint text summary">
        <h2>Blueprint summary</h2>
        <p>Flutter Web connects to FastAPI over HTTPS. FastAPI connects to Supabase over SQL.</p>
        {reducedMotion && <p>Reduced motion is enabled, so the full diagram is shown without animation.</p>}
      </section>}
    </main>
  );
}

createRoot(document.getElementById("root")).render(<CanvasProof />);
