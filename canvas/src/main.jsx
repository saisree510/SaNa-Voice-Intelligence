import { useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { Excalidraw, exportToBlob } from "@excalidraw/excalidraw";
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

  const debounceTimerRef = useRef(null);

  const syncManualChanges = (currentElements) => {
    if (!blueprint || !isEmbedded) return;
    
    // Check for deletion
    const currentElementIds = new Set(currentElements.map((el) => el.id));
    for (const component of (blueprint.components || [])) {
      if (!currentElementIds.has(`node-${component.id}`)) {
        postToParent("soul.canvas.node_deleted", {
          componentId: component.id,
          name: component.name,
        });
        return; // handle one deletion at a time
      }
    }

    // Check for movements or edits
    for (const component of (blueprint.components || [])) {
      const rect = currentElements.find((el) => el.id === `node-${component.id}`);
      if (rect) {
        const currentPos = component.metadata?.position;
        const newX = Math.round(rect.x);
        const newY = Math.round(rect.y);
        
        if (!currentPos || Math.round(currentPos.x) !== newX || Math.round(currentPos.y) !== newY) {
          postToParent("soul.canvas.node_moved", {
            componentId: component.id,
            x: newX,
            y: newY,
          });
          return; // sync one movement at a time
        }
      }

      const label = currentElements.find((el) => el.id === `label-${component.id}`);
      if (label) {
        const subtitle = component.technology || component.type || "";
        const defaultText = subtitle ? `${component.name}\n${subtitle}` : component.name;
        if (label.text && label.text !== defaultText) {
          const lines = label.text.split("\n");
          const newName = lines[0]?.trim() || component.name;
          const newTech = lines[1]?.trim() || null;
          postToParent("soul.canvas.node_edited", {
            componentId: component.id,
            name: newName,
            technology: newTech,
          });
          return; // sync one edit at a time
        }
      }
    }
  };

  const handleCanvasChange = (currentElements, appState) => {
    if (!isEmbedded) return;
    if (
      appState.draggingElement ||
      appState.editingElement ||
      appState.resizingElement ||
      appState.multiElement
    ) {
      return;
    }

    if (debounceTimerRef.current) {
      window.clearTimeout(debounceTimerRef.current);
    }
    debounceTimerRef.current = window.setTimeout(() => {
      syncManualChanges(currentElements);
    }, 800);
  };

  const exportPng = async () => {
    if (!apiRef.current || !blueprint) return;
    try {
      const elementsList = apiRef.current.getSceneElements();
      const appState = apiRef.current.getAppState();
      const blob = await exportToBlob({
        elements: elementsList,
        appState: {
          ...appState,
          exportBackground: true,
          viewBackgroundColor: "#fdfcff",
        },
        mimeType: "image/png",
      });
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `${blueprint.architecture_id || "blueprint"}.png`;
      a.click();
      window.URL.revokeObjectURL(url);
    } catch (e) {
      console.error("Failed to export PNG:", e);
    }
  };

  const downloadTextFile = (filename, text) => {
    const element = document.createElement("a");
    element.setAttribute("href", "data:text/plain;charset=utf-8," + encodeURIComponent(text));
    element.setAttribute("download", filename);
    element.style.display = "none";
    document.body.appendChild(element);
    element.click();
    document.body.removeChild(element);
  };

  const exportJson = () => {
    if (!blueprint) return;
    downloadTextFile(
      `${blueprint.architecture_id || "blueprint"}.json`,
      JSON.stringify(blueprint, null, 2),
    );
  };

  const exportMermaid = () => {
    if (!blueprint) return;
    let out = "graph TD\n";
    const components = blueprint.components || [];
    const connections = blueprint.connections || [];
    
    for (const comp of components) {
      const subtitle = comp.technology || comp.type || "";
      const label = subtitle ? `"${comp.name}\n(${subtitle})"` : `"${comp.name}"`;
      out += `  ${comp.id}[${label}]\n`;
    }
    
    for (const conn of connections) {
      const label = conn.protocol ? ` -- ${conn.protocol} --> ` : " --> ";
      out += `  ${conn.source_id}${label}${conn.target_id}\n`;
    }
    
    downloadTextFile(`${blueprint.architecture_id || "blueprint"}.mermaid`, out);
  };

  useEffect(() => {
    if (!isEmbedded || !blueprint || step < operations.length || operations.length === 0) return;
    const elementsList = apiRef.current?.getSceneElements() || [];
    postToParent("soul.canvas.snapshot_ready", {
      sequenceNumber: step,
      scene: { elements: elementsList },
    });
  }, [blueprint, isEmbedded, operations.length, step]);

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
          onChange={handleCanvasChange}
          UIOptions={{ canvasActions: { loadScene: false, saveToActiveFile: false, export: false } }}
        />
        <div className="canvas-floating-controls" aria-label="Export controls">
          <button type="button" onClick={exportPng} title="Export PNG image">PNG</button>
          <button type="button" onClick={exportJson} title="Export Blueprint JSON">JSON</button>
          <button type="button" onClick={exportMermaid} title="Export Mermaid TD flowchart">Mermaid</button>
        </div>
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
