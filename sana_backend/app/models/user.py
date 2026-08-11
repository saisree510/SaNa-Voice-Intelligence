import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..db.session import Base


class User(Base):
    __tablename__ = 'users'

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    # Set once, right after onboarding (see PATCH /auth/me) -- null for
    # any account that hasn't finished onboarding yet. This is what lets
    # SANA actually know who it's talking to; before this field existed,
    # the name only ever lived in the Flutter app's local, on-device
    # storage and never reached the backend/AI at all.
    name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    conversations: Mapped[list['Conversation']] = relationship(
        back_populates='user', cascade='all, delete-orphan'
    )
