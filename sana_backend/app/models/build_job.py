import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from ..db.session import Base

# Deliberately no relationship()/back_populates to User or Conversation
# here -- keeps this table decoupled (a build job can exist without a
# conversation_id, e.g. one created directly via POST /api/build/jobs
# rather than from a chat turn) and avoids touching those two models'
# existing, working definitions at all. Queried directly by
# user_id/conversation_id instead (see build_job_service.py).
#
# id doubles as the BuildAgent/DeepCodeService "project_id" -- the
# generated workspace lives at sana-builds/<this id>/, and it's also
# what artifact ZIPs are named after. One id, not two parallel ones.
class BuildJob(Base):
    __tablename__ = 'build_jobs'

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey('users.id'), nullable=False, index=True)
    # Set when a build was triggered from a Build-mode chat turn (the
    # normal path); null for a build created directly through the API
    # with no associated conversation.
    conversation_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey('conversations.id'), nullable=True, index=True
    )
    project_name: Mapped[str] = mapped_column(String(100), nullable=False)
    # 'chrome_extension' | 'web_app' -- see build_agent.py's ProjectType.
    project_type: Mapped[str] = mapped_column(String(30), nullable=False)
    request: Mapped[str] = mapped_column(Text, nullable=False)
    # PENDING | PLANNING | CREATING_WORKSPACE | GENERATING_FILES |
    # VALIDATING | FIXING | PACKAGING | COMPLETED | FAILED
    status: Mapped[str] = mapped_column(String(30), nullable=False, default='PENDING')
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Absolute path to the packaged ZIP once COMPLETED, else null.
    artifact_path: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )
