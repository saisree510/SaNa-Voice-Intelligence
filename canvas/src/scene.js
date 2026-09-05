import { convertToExcalidrawElements } from "@excalidraw/excalidraw";
import { iconFileId } from "./icons";

const positions = {
  web: { x: 80, y: 300 },
  frontend: { x: 80, y: 300 },
  api: { x: 400, y: 300 },
  logic: { x: 400, y: 300 },
  database: { x: 720, y: 300 },
  data: { x: 720, y: 300 },
  // Cross-cutting services live in a separate lane so their connections do
  // not pass through the primary UI → API → data path.
  agent: { x: 720, y: 80 },
  ai: { x: 720, y: 80 },
  auth: { x: 400, y: 80 },
  storage: { x: 1040, y: 80 },
  payments: { x: 1040, y: 220 },
  notifications: { x: 1040, y: 360 },
  analytics: { x: 1040, y: 520 },
  booking: { x: 400, y: 520 },
  checkin: { x: 720, y: 520 },
  realtime: { x: 720, y: 680 },
};

// Large blueprints use a layered, top-to-bottom architecture flow. It is much
// easier to scan than a wide bus once a project has several integrations.
const layeredPositions = {
  web: { x: 620, y: 80 },
  frontend: { x: 620, y: 80 },
  auth: { x: 320, y: 240 },
  api: { x: 620, y: 240 },
  logic: { x: 620, y: 240 },
  agent: { x: 920, y: 240 },
  ai: { x: 920, y: 240 },
  database: { x: 620, y: 400 },
  data: { x: 620, y: 400 },
  analytics: { x: 920, y: 400 },
  booking: { x: 620, y: 560 },
  payments: { x: 140, y: 720 },
  checkin: { x: 380, y: 720 },
  storage: { x: 620, y: 720 },
  notifications: { x: 860, y: 720 },
  realtime: { x: 1100, y: 720 },
};

const size = { width: 220, height: 96 };

// Semantic visual language adapted from the Excalidraw Diagram skill palette.
// Colors communicate responsibility, instead of making every node the same card.
function componentStyle(component) {
  if (component.type === "frontend") return { fill: "#fed7aa", stroke: "#c2410c" };
  if (component.type === "agent") return { fill: "#ddd6fe", stroke: "#6d28d9" };
  if (component.type === "analytics") return { fill: "#a7f3d0", stroke: "#047857" };
  if (component.type === "database" || component.type === "storage") return { fill: "#93c5fd", stroke: "#1e3a5f" };
  if (component.type === "identity") return { fill: "#fef3c7", stroke: "#b45309" };
  if (component.type === "external_service") return { fill: "#60a5fa", stroke: "#1e3a5f" };
  return { fill: "#3b82f6", stroke: "#1e3a5f" };
}

function positionFor(component, index, componentCount) {
  if (component.metadata?.position && typeof component.metadata.position.x === "number" && typeof component.metadata.position.y === "number") {
    return component.metadata.position;
  }
  const layout = componentCount > 6 ? layeredPositions : positions;
  return layout[component.id] ?? {
    x: 120 + (index % 4) * 340,
    y: 220 + Math.floor(index / 4) * 160,
  };
}

function componentElements(component, position) {
  const candidateSubtitle = component.technology || component.type || "";
  const subtitle = candidateSubtitle === component.name ? "" : candidateSubtitle;
  const style = componentStyle(component);
  return convertToExcalidrawElements([
    {
      id: `node-${component.id}`,
      type: "rectangle",
      x: position.x,
      y: position.y,
      width: size.width,
      height: size.height,
      roundness: { type: 3 },
      strokeColor: style.stroke,
      backgroundColor: style.fill,
      fillStyle: "solid",
      roughness: 0,
      strokeWidth: 2,
      customData: { blueprintId: component.id, role: "component" },
    },
    {
      id: `icon-${component.id}`,
      type: "image",
      x: position.x + 18,
      y: position.y + 29,
      width: 32,
      height: 32,
      fileId: iconFileId(component),
      status: "saved",
      customData: { blueprintId: component.id, role: "component-icon" },
    },
    {
      id: `label-${component.id}`,
      type: "text",
      x: position.x + 62,
      y: position.y + 24,
      text: subtitle ? `${component.name}\n${subtitle}` : component.name,
      fontSize: 20,
      strokeColor: "#374151",
      roughness: 0,
      customData: { blueprintId: component.id, role: "component-label" },
    },
  ]);
}

function connectionElements(connection, componentPositions, allConnections) {
  const source = componentPositions.get(connection.source_id);
  const target = componentPositions.get(connection.target_id);
  if (!source || !target) return [];
  const outgoing = allConnections
    .filter((item) => item.source_id === connection.source_id)
    .sort((a, b) => {
      const aTarget = componentPositions.get(a.target_id);
      const bTarget = componentPositions.get(b.target_id);
      return (aTarget?.y ?? 0) - (bTarget?.y ?? 0) || (aTarget?.x ?? 0) - (bTarget?.x ?? 0);
    });
  const incoming = allConnections
    .filter((item) => item.target_id === connection.target_id)
    .sort((a, b) => {
      const aSource = componentPositions.get(a.source_id);
      const bSource = componentPositions.get(b.source_id);
      return (aSource?.y ?? 0) - (bSource?.y ?? 0) || (aSource?.x ?? 0) - (bSource?.x ?? 0);
    });
  const outgoingIndex = Math.max(0, outgoing.findIndex((item) => item.id === connection.id));
  const incomingIndex = Math.max(0, incoming.findIndex((item) => item.id === connection.id));
  const edgeOffset = (index, count) => 18 + ((index + 1) * (size.height - 36)) / (count + 1);
  const horizontal = Math.abs(target.x - source.x) >= Math.abs(target.y - source.y);
  const flowsRight = target.x >= source.x;
  const flowsDown = target.y >= source.y;
  const startX = horizontal
    ? (flowsRight ? source.x + size.width : source.x)
    : source.x + edgeOffset(outgoingIndex, outgoing.length);
  const startY = horizontal
    ? source.y + edgeOffset(outgoingIndex, outgoing.length)
    : (flowsDown ? source.y + size.height : source.y);
  const endX = horizontal
    ? (flowsRight ? target.x : target.x + size.width)
    : target.x + edgeOffset(incomingIndex, incoming.length);
  const endY = horizontal
    ? target.y + edgeOffset(incomingIndex, incoming.length)
    : (flowsDown ? target.y : target.y + size.height);
  const length = endX - startX;
  const height = endY - startY;
  // Each relationship leaves its source through a short private lane before
  // turning toward its target, keeping arrows outside component bodies.
  const elbow = (30 + outgoingIndex * 18) * Math.sign(length || 1);
  const points = horizontal && Math.abs(height) > 8
    ? [[0, 0], [elbow, 0], [elbow, height], [length, height]]
    : [[0, 0], [length, height]];

  return convertToExcalidrawElements([
    {
      id: `edge-${connection.id}`,
      type: "arrow",
      x: startX,
      y: startY,
      width: length,
      height,
      points,
      strokeColor: "#66507d",
      roughness: 0,
      strokeWidth: 2,
      endArrowhead: "arrow",
      customData: { blueprintId: connection.id, role: "connection" },
    },
  ]);
}

export function sceneForOperations(blueprint, operations) {
  const elements = [];
  const components = Array.isArray(blueprint.components) ? blueprint.components : [];
  const connections = Array.isArray(blueprint.connections) ? blueprint.connections : [];
  const componentPositions = new Map(
    components.map((component, index) => [component.id, positionFor(component, index, components.length)]),
  );

  if (components.length > 6) {
    elements.push(...convertToExcalidrawElements([
      {
        id: "architecture-flow-title",
        type: "text",
        x: 140,
        y: 20,
        text: "Architecture flow",
        fontSize: 28,
        strokeColor: "#1e40af",
        roughness: 0,
        customData: { role: "diagram-title" },
      },
      {
        id: "architecture-flow-subtitle",
        type: "text",
        x: 142,
        y: 58,
        text: "Primary path and supporting integrations",
        fontSize: 16,
        strokeColor: "#64748b",
        roughness: 0,
        customData: { role: "diagram-subtitle" },
      },
    ]));
  }

  for (const operation of operations) {
    if (operation.type === "add_node") {
      const component = components.find(({ id }) => id === operation.componentId);
      const position = component ? componentPositions.get(component.id) : null;
      if (component && position) elements.push(...componentElements(component, position));
    }
    if (operation.type === "connect_nodes") {
      const connection = connections.find(({ id }) => id === operation.connectionId);
      if (connection) elements.push(...connectionElements(connection, componentPositions, connections));
    }
  }
  return elements;
}
