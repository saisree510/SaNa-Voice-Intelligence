import { convertToExcalidrawElements } from "@excalidraw/excalidraw";

const positions = {
  web: { x: 120, y: 220 },
  frontend: { x: 120, y: 220 },
  api: { x: 460, y: 220 },
  database: { x: 800, y: 220 },
  agent: { x: 460, y: 380 },
};

const size = { width: 220, height: 96 };

function positionFor(component, index) {
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
  const startX = source.x + size.width;
  const startY = source.y + size.height / 2;
  const endX = target.x;
  const endY = target.y + size.height / 2;
  const length = endX - startX;

  return convertToExcalidrawElements([
    {
      id: `edge-${connection.id}`,
      type: "arrow",
      x: startX,
      y: startY,
      width: length,
      height: endY - startY,
      points: [[0, 0], [length, endY - startY]],
      strokeColor: "#66507d",
      endArrowhead: "arrow",
      customData: { blueprintId: connection.id, role: "connection" },
    },
    {
      id: `edge-label-${connection.id}`,
      type: "text",
      x: startX + length / 2 - 22,
      y: startY - 34,
      text: connection.protocol || "",
      fontSize: 16,
      strokeColor: "#66507d",
      customData: { blueprintId: connection.id, role: "connection-label" },
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
