from collections import defaultdict
from typing import Any

from fastapi import WebSocket


class CanvasConnectionManager:
    def __init__(self):
        self._connections: dict[str, set[WebSocket]] = defaultdict(set)

    async def connect(self, architecture_id: str, websocket: WebSocket) -> None:
        await websocket.accept()
        self._connections[architecture_id].add(websocket)

    def disconnect(self, architecture_id: str, websocket: WebSocket) -> None:
        connections = self._connections.get(architecture_id)
        if not connections:
            return
        connections.discard(websocket)
        if not connections:
            self._connections.pop(architecture_id, None)

    async def broadcast(self, architecture_id: str, message: dict[str, Any], *, exclude: WebSocket | None = None) -> None:
        connections = list(self._connections.get(architecture_id, set()))
        for websocket in connections:
            if websocket is exclude:
                continue
            try:
                await websocket.send_json(message)
            except RuntimeError:
                self.disconnect(architecture_id, websocket)
