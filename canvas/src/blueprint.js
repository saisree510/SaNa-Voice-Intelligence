export const overviewBlueprint = {
  architecture_id: "soul-overview",
  version: 1,
  status: "draft",
  components: [
    { id: "web", name: "Flutter Web", type: "frontend", technology: "Flutter" },
    { id: "api", name: "FastAPI", type: "service", technology: "FastAPI" },
    { id: "database", name: "Supabase", type: "database", technology: "PostgreSQL" },
  ],
  connections: [
    { id: "web-api", source_id: "web", target_id: "api", protocol: "HTTPS" },
    { id: "api-database", source_id: "api", target_id: "database", protocol: "SQL" },
  ],
};

export const mockOperations = [
  { type: "add_node", componentId: "web" },
  { type: "add_node", componentId: "api" },
  { type: "connect_nodes", connectionId: "web-api" },
  { type: "add_node", componentId: "database" },
  { type: "connect_nodes", connectionId: "api-database" },
];
