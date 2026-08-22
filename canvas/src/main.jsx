import { useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { Excalidraw } from "@excalidraw/excalidraw";
import { mockOperations, overviewBlueprint } from "./blueprint";
import { sceneForOperations } from "./scene";
import "./styles.css";

window.EXCALIDRAW_ASSET_PATH = "/excalidraw-assets/";

function CanvasProof() {
  const [step, setStep] = useState(0);
  const [playing, setPlaying] = useState(true);
  const [speed, setSpeed] = useState(1);
  const [reducedMotion, setReducedMotion] = useState(false);
  const apiRef = useRef(null);

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

  const reset = () => {
    setStep(0);
    setPlaying(!reducedMotion);
  };

  const fitToContent = () => apiRef.current?.scrollToContent(elements, { fitToContent: true, animate: !reducedMotion });

  return (
    <main className="canvas-proof">
      <header className="canvas-header">
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
      </header>
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
      <section className="accessible-summary" aria-label="Architecture Blueprint text summary">
        <h2>Blueprint summary</h2>
        <p>Flutter Web connects to FastAPI over HTTPS. FastAPI connects to Supabase over SQL.</p>
        {reducedMotion && <p>Reduced motion is enabled, so the full diagram is shown without animation.</p>}
      </section>
    </main>
  );
}

createRoot(document.getElementById("root")).render(<CanvasProof />);
