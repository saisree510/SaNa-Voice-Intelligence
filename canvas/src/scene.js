import { convertToExcalidrawElements } from "@excalidraw/excalidraw";

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

const size = { width: 220, height: 96 };

function positionFor(component, index) {
  if (component.metadata?.position && typeof component.metadata.position.x === "number" && typeof component.metadata.position.y === "number") {
    return component.metadata.position;
  }
  return positions[component.id] ?? {
    x: 120 + (index % 4) * 340,
    y: 220 + Math.floor(index / 4) * 160,
  };
}

function componentElements(component, position) {
  const subtitle = component.technology || component.type || "";
  return convertToExcalidrawElements([
    {
      id: `node-${component.id}`,
      type: "rectangle",
      x: position.x,
      y: position.y,
      width: size.width,
      height: size.height,
      roundness: { type: 3 },
      strokeColor: "#9f80d8",
      backgroundColor: "#f0e8ff",
      fillStyle: "solid",
      customData: { blueprintId: component.id, role: "component" },
    },
    {
      id: `label-${component.id}`,
      type: "text",
      x: position.x + 22,
      y: position.y + 24,
      text: subtitle ? `${component.name}\n${subtitle}` : component.name,
      fontSize: 20,
      strokeColor: "#281d3d",
      customData: { blueprintId: component.id, role: "component-label" },
    },
  ]);
}

function connectionElements(connection, componentPositions) {
  const source = componentPositions.get(connection.source_id);
  const target = componentPositions.get(connection.target_id);
  if (!source || !target) return [];
  const horizontal = Math.abs(target.x - source.x) >= Math.abs(target.y - source.y);
  const flowsRight = target.x >= source.x;
  const flowsDown = target.y >= source.y;
  const startX = horizontal ? (flowsRight ? source.x + size.width : source.x) : source.x + size.width / 2;
  const startY = horizontal ? source.y + size.height / 2 : (flowsDown ? source.y + size.height : source.y);
  const endX = horizontal ? (flowsRight ? target.x : target.x + size.width) : target.x + size.width / 2;
  const endY = horizontal ? target.y + size.height / 2 : (flowsDown ? target.y : target.y + size.height);
  const length = endX - startX;
  const height = endY - startY;
  // Each relationship leaves its source through a short private lane before
  // turning toward its target, keeping arrows outside component bodies.
  const elbow = 40 * Math.sign(length || 1);
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
    components.map((component, index) => [component.id, positionFor(component, index)]),
  );

  for (const operation of operations) {
    if (operation.type === "add_node") {
      const component = components.find(({ id }) => id === operation.componentId);
      const position = component ? componentPositions.get(component.id) : null;
      if (component && position) elements.push(...componentElements(component, position));
    }
    if (operation.type === "connect_nodes") {
      const connection = connections.find(({ id }) => id === operation.connectionId);
      if (connection) elements.push(...connectionElements(connection, componentPositions));
    }
  }
  return elements;
}
