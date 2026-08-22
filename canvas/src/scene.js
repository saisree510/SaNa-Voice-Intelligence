import { convertToExcalidrawElements } from "@excalidraw/excalidraw";

const positions = {
  web: { x: 120, y: 220 },
  api: { x: 460, y: 220 },
  database: { x: 800, y: 220 },
};

const size = { width: 220, height: 96 };

function componentElements(component) {
  const position = positions[component.id];
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
      text: `${component.name}\n${component.technology}`,
      fontSize: 20,
      strokeColor: "#281d3d",
      customData: { blueprintId: component.id, role: "component-label" },
    },
  ]);
}

function connectionElements(connection) {
  const source = positions[connection.source_id];
  const target = positions[connection.target_id];
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
  for (const operation of operations) {
    if (operation.type === "add_node") {
      const component = blueprint.components.find(({ id }) => id === operation.componentId);
      elements.push(...componentElements(component));
    }
    if (operation.type === "connect_nodes") {
      const connection = blueprint.connections.find(({ id }) => id === operation.connectionId);
      elements.push(...connectionElements(connection));
    }
  }
  return elements;
}
