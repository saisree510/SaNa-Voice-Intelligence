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
  const [blueprint, setBlueprint] = useState(overviewBlueprint);
  const [operations, setOperations] = useState(mockOperations);
  const [step, setStep] = useState(0);
  const [playing, setPlaying] = useState(true);
  const [speed, setSpeed] = useState(1);
  const [reducedMotion, setReducedMotion] = useState(false);
  const apiRef = useRef(null);
  const elementsRef = useRef([]);
  const operationsRef = useRef(mockOperations);
  const reducedMotionRef = useRef(false);
  const stepRef = useRef(0);
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
          if (
            message.payload?.command === "play" &&
            !reducedMotionRef.current &&
            stepRef.current < operationsRef.current.length
          ) {
            setPlaying(true);
          }
          postToParent("soul.canvas.ack", { received: message.payload?.command ?? "unknown" });
          break;
        case "soul.canvas.load_blueprint":
          loadBlueprint(message.payload);
          postToParent("soul.canvas.ack", { received: message.type });
          break;
        default:
          postToParent("soul.canvas.rejected", { reason: "unsupported_type", type: message.type });
      }
    };

    window.addEventListener("message", handleMessage);
    return () => window.removeEventListener("message", handleMessage);
  }, [isEmbedded]);

  useEffect(() => {
    operationsRef.current = operations;
  }, [operations]);

  useEffect(() => {
    reducedMotionRef.current = reducedMotion;
  }, [reducedMotion]);

  useEffect(() => {
    stepRef.current = step;
  }, [step]);

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
      setStep(operations.length);
    }
  }, [operations.length, reducedMotion]);

  useEffect(() => {
    if (!playing || step >= operations.length || reducedMotion) return undefined;
    const timer = window.setTimeout(() => setStep((current) => current + 1), 1100 / speed);
    return () => window.clearTimeout(timer);
  }, [operations.length, playing, reducedMotion, speed, step]);

  const elements = sceneForOperations(blueprint, operations.slice(0, step));

  useEffect(() => {
    elementsRef.current = elements;
    apiRef.current?.updateScene({ elements });
  }, [elements]);

  useEffect(() => {
    if (!isEmbedded) return;
    postToParent("soul.canvas.state", {
      status: step < operations.length ? "drawing" : "complete",
      appliedOperations: step,
      totalOperations: operations.length,
    });
  }, [isEmbedded, operations.length, step]);

  const reset = () => {
    setStep(0);
    setPlaying(!reducedMotion);
  };

  const loadBlueprint = (payload) => {
    if (!payload || typeof payload !== "object") {
      postToParent("soul.canvas.rejected", { reason: "invalid_blueprint_payload" });
      return;
    }
    const nextBlueprint = payload.blueprint;
    const nextOperations = Array.isArray(payload.operations) ? payload.operations : [];
    if (!nextBlueprint || typeof nextBlueprint !== "object") {
      postToParent("soul.canvas.rejected", { reason: "missing_blueprint" });
      return;
    }

    const nextId = nextBlueprint.id || payload.architectureId || nextBlueprint.architecture_id || "architecture";
    const isSameArch = blueprint && blueprint.id === nextId;

    setBlueprint({
      ...nextBlueprint,
      id: nextId,
      components: Array.isArray(nextBlueprint.components) ? nextBlueprint.components : [],
      connections: Array.isArray(nextBlueprint.connections) ? nextBlueprint.connections : [],
    });

    if (isSameArch) {
      const oldLength = operations.length;
      setOperations(nextOperations);
      if (nextOperations.length > oldLength) {
        if (stepRef.current === oldLength) {
          // Continue playing new operations progressively
          setPlaying(!reducedMotionRef.current);
        }
      }
    } else {
      setOperations(nextOperations);
      setStep(reducedMotionRef.current ? nextOperations.length : 0);
      setPlaying(!reducedMotionRef.current && nextOperations.length > 0);
    }
  };


  const fitToContent = () =>
    apiRef.current?.scrollToContent(elementsRef.current, { fitToContent: true, animate: !reducedMotionRef.current });

  return (
    <main className={`canvas-proof${isEmbedded ? " is-embedded" : ""}`}>
      {!isEmbedded && <header className="canvas-header">
        <div>
          <p className="eyebrow">Soul / Overview Architecture</p>
          <h1>Architecture Blueprint</h1>
          <p className="status" aria-live="polite">{step < operations.length ? "Drawing validated operations" : "Blueprint preview complete"}</p>
        </div>
        <div className="controls" aria-label="Canvas proof controls">
          <button type="button" onClick={() => setPlaying((current) => !current)} disabled={reducedMotion || step >= operations.length}>
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
