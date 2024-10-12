from datetime import datetime
from enum import Enum
from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel
from quivr_core.config import BrainConfig
from sqlalchemy.dialects.postgresql import ENUM as PGEnum
from sqlalchemy.ext.asyncio import AsyncAttrs
from sqlmodel import TIMESTAMP, Column, Field, Relationship, SQLModel, text
from sqlmodel import UUID as PGUUID

from quivr_api.modules.brain.entity.integration_brain import (
    IntegrationDescriptionEntity,
    IntegrationEntity,
)
from quivr_api.modules.knowledge.entity.knowledge import KnowledgeDB
from quivr_api.modules.knowledge.entity.knowledge_brain import KnowledgeBrain

# from sqlmodel import Enum as PGEnum
from quivr_api.modules.prompt.entity.prompt import Prompt


class BrainType(str, Enum):
    doc = "doc"
    api = "api"
    composite = "composite"
    integration = "integration"
    model = "model"


class Brain(AsyncAttrs, SQLModel, table=True):
    __tablename__ = "brains"  # type: ignore

    brain_id: UUID | None = Field(
        default=None,
        sa_column=Column(
            PGUUID,
            server_default=text("uuid_generate_v4()"),
            primary_key=True,
        ),
    )
    name: str
    description: str
    status: str | None = None
    model: str | None = None
    max_tokens: int | None = None
    temperature: float | None = None
    last_update: datetime | None = Field(
        default=None,
        sa_column=Column(
            TIMESTAMP(timezone=False),
            server_default=text("CURRENT_TIMESTAMP"),
        ),
    )
    brain_type: BrainType | None = Field(
        sa_column=Column(
            PGEnum(BrainType, name="brain_type_enum", create_type=False),
            default=BrainType.integration,
        ),
    )
    brain_chat_history: List["ChatHistory"] = Relationship(  # type: ignore # noqa: F821
        back_populates="brain", sa_relationship_kwargs={"lazy": "select"}
    )
    prompt_id: UUID | None = Field(default=None, foreign_key="prompts.id")
    prompt: Prompt | None = Relationship(  # noqa: F821
        back_populates="brain", sa_relationship_kwargs={"lazy": "joined"}
    )
    knowledges: List[KnowledgeDB] = Relationship(
        back_populates="brains", link_model=KnowledgeBrain
    )

    # TODO : add
    # "meaning" "public"."vector",
    # "tags" "public"."tags"[]


class BrainEntity(BrainConfig):
    last_update: datetime | None = None
    brain_type: BrainType | None = None
    description: Optional[str] = None
    temperature: Optional[float] = None
    meaning: Optional[str] = None
    openai_api_key: Optional[str] = None
    tags: Optional[List[str]] = None
    model: Optional[str] = None
    max_tokens: Optional[int] = None
    status: Optional[str] = None
    prompt_id: Optional[UUID] = None
    integration: Optional[IntegrationEntity] = None
    integration_description: Optional[IntegrationDescriptionEntity] = None
    snippet_emoji: Optional[str] = None
    snippet_color: Optional[str] = None

    def dict(self, **kwargs):
        data = super().dict(
            **kwargs,
        )
        data["id"] = self.id
        return data


class RoleEnum(str, Enum):
    Viewer = "Viewer"
    Editor = "Editor"
    Owner = "Owner"


class BrainUser(BaseModel):
    id: UUID
    user_id: UUID
    rights: RoleEnum
    default_brain: bool = False


class MinimalUserBrainEntity(BaseModel):
    id: UUID
    name: str
    brain_model: Optional[str] = None
    rights: RoleEnum
    status: str
    brain_type: BrainType
    description: str
    integration_logo_url: str
    max_files: int
    price: Optional[int] = None
    max_input: Optional[int] = None
    max_output: Optional[int] = None
    display_name: Optional[str] = None
    image_url: Optional[str] = None
    model: bool = False
    snippet_color: Optional[str] = None
    snippet_emoji: Optional[str] = None