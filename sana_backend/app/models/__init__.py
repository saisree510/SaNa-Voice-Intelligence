"""Import every model here so SQLAlchemy's mapper registry can resolve
the string-based relationship() references between them (e.g.
Conversation.user -> 'User'), and so `Base.metadata.create_all()`
(called from app/db/init_db.py) knows about all three tables.
"""

from .build_job import BuildJob
from .conversation import Conversation
from .message import Message
from .user import User

__all__ = ['User', 'Conversation', 'Message', 'BuildJob']
