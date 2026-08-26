# Architecture Blueprint contract v1.0

`ArchitectureSpec` is Soul's canonical Architecture Blueprint. It is provider-neutral and intentionally excludes Excalidraw scene data, visual styles, element coordinates and viewport state. A renderer may derive a scene from the Blueprint, but it cannot become the source of architectural truth.

## Version lifecycle

- `draft`: the only mutable version.
- `approved`: immutable and requires `approved_at`.
- `superseded`: immutable and requires `superseded_at`.

Creating an execution-relevant change must create a new draft version. A later phase will persist these versions and bind approved versions to build runs.

## Example Blueprint

```json
{
  "architecture_id": "triangle-maker",
  "project_id": "triangle-project",
  "version": 1,
  "status": "draft",
  "components": [
    {"id": "web", "name": "Flutter Web", "type": "frontend"},
    {"id": "api", "name": "FastAPI", "type": "service"}
  ],
  "connections": [
    {"id": "web-api", "source_id": "web", "target_id": "api", "protocol": "HTTPS"}
  ]
}
```

## Canvas operations

Only these operations are permitted: `add_node`, `update_node`, `move_node`, `delete_node`, `connect_nodes`, `disconnect_nodes`, `create_group`, `add_annotation`, `highlight_risk`, and `focus_viewport`.

Every operation includes a stable `operation_id`, `architecture_id`, `base_version`, actor and strictly validated payload. `move_node` and `focus_viewport` are visual operations and deliberately do not change Blueprint meaning. The validation helper returns structured errors for version conflicts, unknown references, duplicate IDs and attempts to change immutable versions.
