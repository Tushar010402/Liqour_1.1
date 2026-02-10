# Collaboration Module - Detailed Specification

## Module Overview

| Property | Value |
|----------|-------|
| **Module ID** | `MOD-COLLAB` |
| **Priority** | P1 (High) |
| **Complexity** | Very High |
| **Dependencies** | Core, Auth, Tenant |

This module implements Google Docs-style real-time collaborative editing with authentication, commenting, and presence features.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      Frontend (React)                            │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ Auth Guard  │  │  Editor     │  │  Comments Panel         │  │
│  │             │  │  (Yjs +     │  │  - Threads              │  │
│  │ - Login     │  │   Quill/    │  │  - Replies              │  │
│  │ - Permissions│ │   TipTap)   │  │  - Mentions             │  │
│  │ - Session   │  │             │  │  - Resolve/Reopen       │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
│                           │                                      │
│                    WebSocket Connection                          │
└───────────────────────────┼─────────────────────────────────────┘
                            │
┌───────────────────────────┼─────────────────────────────────────┐
│                      Backend (FastAPI)                           │
├───────────────────────────┼─────────────────────────────────────┤
│  ┌─────────────┐  ┌───────┴───────┐  ┌───────────────────────┐  │
│  │ Auth        │  │ WebSocket     │  │ Comments Service      │  │
│  │ Middleware  │  │ Server        │  │                       │  │
│  │             │  │ (y-websocket) │  │ - CRUD                │  │
│  │ - JWT       │  │               │  │ - Notifications       │  │
│  │ - Permissions│ │ - Sync        │  │ - Mentions            │  │
│  └─────────────┘  │ - Presence    │  └───────────────────────┘  │
│                   │ - Awareness   │                              │
│                   └───────────────┘                              │
│                           │                                      │
│              ┌────────────┴────────────┐                        │
│              │                         │                        │
│         ┌────┴────┐              ┌─────┴─────┐                  │
│         │ Redis   │              │ PostgreSQL │                  │
│         │ (Pub/Sub│              │ (Persist)  │                  │
│         │ Presence)│             │            │                  │
│         └─────────┘              └────────────┘                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Sub-modules

### 1. Collaborative Authentication (SUB-COLLAB-AUTH)

#### Micro-modules

##### 1.1 Document Access Control (MICRO-COLLAB-ACCESS)

**Purpose**: Control who can view, edit, and comment on documents

**Database Models**:

```python
# backend/app/modules/collaboration/models/access.py
from sqlalchemy import Column, String, Enum, ForeignKey, UniqueConstraint, Boolean
from sqlalchemy.orm import relationship
from app.core.database import TenantBaseModel
import enum

class DocumentPermission(str, enum.Enum):
    VIEW = "view"           # Can only view
    COMMENT = "comment"     # Can view and comment
    EDIT = "edit"           # Can view, comment, and edit
    ADMIN = "admin"         # Full control including sharing

class ShareType(str, enum.Enum):
    PRIVATE = "private"     # Only explicitly shared users
    TEAM = "team"           # All team members
    ORGANIZATION = "organization"  # All org members
    PUBLIC_VIEW = "public_view"    # Anyone with link can view
    PUBLIC_EDIT = "public_edit"    # Anyone with link can edit

class Document(TenantBaseModel):
    """Collaborative document model."""

    __tablename__ = "documents"

    title = Column(String(500), nullable=False)
    content_type = Column(String(50), default="richtext")  # richtext, markdown, spreadsheet

    # Sharing settings
    share_type = Column(Enum(ShareType), default=ShareType.PRIVATE)
    share_link_id = Column(String(32), unique=True, nullable=True)  # For public links

    # Owner
    owner_id = Column(String(36), ForeignKey("users.id"), nullable=False)

    # Version tracking
    version = Column(Integer, default=1)
    last_edited_by = Column(String(36), ForeignKey("users.id"), nullable=True)

    # Status
    is_archived = Column(Boolean, default=False)
    is_locked = Column(Boolean, default=False)  # Prevent editing

    # Relationships
    owner = relationship("User", foreign_keys=[owner_id])
    last_editor = relationship("User", foreign_keys=[last_edited_by])
    shares = relationship("DocumentShare", back_populates="document", cascade="all, delete-orphan")
    comments = relationship("Comment", back_populates="document", cascade="all, delete-orphan")

class DocumentShare(TenantBaseModel):
    """Document sharing permissions."""

    __tablename__ = "document_shares"

    document_id = Column(String(36), ForeignKey("documents.id"), nullable=False)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=True)
    email = Column(String(255), nullable=True)  # For pending invites
    permission = Column(Enum(DocumentPermission), default=DocumentPermission.VIEW)

    # Invite tracking
    invited_by = Column(String(36), ForeignKey("users.id"), nullable=False)
    accepted_at = Column(DateTime, nullable=True)

    # Relationships
    document = relationship("Document", back_populates="shares")
    user = relationship("User", foreign_keys=[user_id])
    inviter = relationship("User", foreign_keys=[invited_by])

    __table_args__ = (
        UniqueConstraint('document_id', 'user_id', name='uq_document_user'),
        UniqueConstraint('document_id', 'email', name='uq_document_email'),
    )
```

**Access Control Service**:

```python
# backend/app/modules/collaboration/services/access_control.py
from typing import Optional, List
from sqlalchemy import select, and_, or_
from sqlalchemy.ext.asyncio import AsyncSession
from ..models.access import Document, DocumentShare, DocumentPermission, ShareType
from app.core.exceptions import AuthorizationError, NotFoundError
from app.core.logging import get_logger

logger = get_logger(__name__)

class DocumentAccessControl:
    """Handle document access control."""

    def __init__(self, session: AsyncSession, tenant_id: str):
        self.session = session
        self.tenant_id = tenant_id

    async def check_permission(
        self,
        document_id: str,
        user_id: str,
        required_permission: DocumentPermission
    ) -> bool:
        """Check if user has required permission on document."""

        document = await self._get_document(document_id)

        # Owner has full access
        if document.owner_id == user_id:
            return True

        # Check share type
        if document.share_type == ShareType.PUBLIC_EDIT:
            return True
        if document.share_type == ShareType.PUBLIC_VIEW:
            return required_permission == DocumentPermission.VIEW

        if document.share_type == ShareType.ORGANIZATION:
            # Check if user is in same tenant
            user_permission = await self._get_org_permission(document)
            return self._permission_includes(user_permission, required_permission)

        # Check explicit share
        share = await self._get_user_share(document_id, user_id)
        if share:
            return self._permission_includes(share.permission, required_permission)

        return False

    async def require_permission(
        self,
        document_id: str,
        user_id: str,
        required_permission: DocumentPermission
    ) -> Document:
        """Require permission or raise error."""

        has_permission = await self.check_permission(
            document_id, user_id, required_permission
        )

        if not has_permission:
            raise AuthorizationError(
                f"You don't have {required_permission.value} permission on this document"
            )

        return await self._get_document(document_id)

    async def get_user_permission(
        self,
        document_id: str,
        user_id: str
    ) -> Optional[DocumentPermission]:
        """Get user's permission level on document."""

        document = await self._get_document(document_id)

        # Owner has admin
        if document.owner_id == user_id:
            return DocumentPermission.ADMIN

        # Check share type
        if document.share_type == ShareType.PUBLIC_EDIT:
            return DocumentPermission.EDIT
        if document.share_type == ShareType.PUBLIC_VIEW:
            return DocumentPermission.VIEW

        # Check explicit share
        share = await self._get_user_share(document_id, user_id)
        if share:
            return share.permission

        # Organization share
        if document.share_type == ShareType.ORGANIZATION:
            return DocumentPermission.VIEW

        return None

    async def share_document(
        self,
        document_id: str,
        owner_id: str,
        user_id: Optional[str] = None,
        email: Optional[str] = None,
        permission: DocumentPermission = DocumentPermission.VIEW
    ) -> DocumentShare:
        """Share document with user."""

        # Verify owner has admin permission
        await self.require_permission(document_id, owner_id, DocumentPermission.ADMIN)

        # Check if share already exists
        existing = await self._get_user_share(document_id, user_id, email)
        if existing:
            existing.permission = permission
            await self.session.flush()
            return existing

        # Create new share
        share = DocumentShare(
            tenant_id=self.tenant_id,
            document_id=document_id,
            user_id=user_id,
            email=email,
            permission=permission,
            invited_by=owner_id
        )
        self.session.add(share)
        await self.session.flush()

        logger.info(
            "Document shared",
            document_id=document_id,
            user_id=user_id,
            email=email,
            permission=permission.value
        )

        return share

    async def revoke_access(
        self,
        document_id: str,
        owner_id: str,
        user_id: str
    ) -> bool:
        """Revoke user's access to document."""

        await self.require_permission(document_id, owner_id, DocumentPermission.ADMIN)

        share = await self._get_user_share(document_id, user_id)
        if share:
            await self.session.delete(share)
            return True
        return False

    async def get_document_collaborators(
        self,
        document_id: str
    ) -> List[dict]:
        """Get all users with access to document."""

        query = select(DocumentShare).where(
            DocumentShare.document_id == document_id
        )
        result = await self.session.execute(query)
        shares = result.scalars().all()

        collaborators = []
        for share in shares:
            collaborators.append({
                "user_id": share.user_id,
                "email": share.email or (share.user.email if share.user else None),
                "name": share.user.full_name if share.user else None,
                "permission": share.permission.value,
                "accepted": share.accepted_at is not None
            })

        return collaborators

    def _permission_includes(
        self,
        user_permission: DocumentPermission,
        required: DocumentPermission
    ) -> bool:
        """Check if user permission includes required permission."""
        hierarchy = {
            DocumentPermission.VIEW: 1,
            DocumentPermission.COMMENT: 2,
            DocumentPermission.EDIT: 3,
            DocumentPermission.ADMIN: 4
        }
        return hierarchy.get(user_permission, 0) >= hierarchy.get(required, 0)

    async def _get_document(self, document_id: str) -> Document:
        """Get document or raise NotFoundError."""
        query = select(Document).where(
            and_(
                Document.id == document_id,
                Document.tenant_id == self.tenant_id,
                Document.is_deleted == False
            )
        )
        result = await self.session.execute(query)
        document = result.scalar_one_or_none()

        if not document:
            raise NotFoundError("Document", document_id)
        return document

    async def _get_user_share(
        self,
        document_id: str,
        user_id: Optional[str] = None,
        email: Optional[str] = None
    ) -> Optional[DocumentShare]:
        """Get user's share record."""
        conditions = [DocumentShare.document_id == document_id]

        if user_id:
            conditions.append(DocumentShare.user_id == user_id)
        if email:
            conditions.append(DocumentShare.email == email)

        query = select(DocumentShare).where(and_(*conditions))
        result = await self.session.execute(query)
        return result.scalar_one_or_none()
```

---

##### 1.2 Session-Based Authentication for WebSocket (MICRO-COLLAB-WSAUTH)

**Purpose**: Authenticate WebSocket connections securely

**Implementation**:

```python
# backend/app/modules/collaboration/auth/websocket_auth.py
from typing import Optional, Dict, Any
from fastapi import WebSocket, HTTPException, status
from jose import jwt, JWTError
from datetime import datetime
from app.core.config import get_settings
from app.core.cache import RedisCache
from app.modules.auth.models import User
from app.core.logging import get_logger

logger = get_logger(__name__)
settings = get_settings()

class WebSocketAuthenticator:
    """Handle WebSocket authentication."""

    def __init__(self, cache: RedisCache, user_repo):
        self.cache = cache
        self.user_repo = user_repo

    async def authenticate(
        self,
        websocket: WebSocket,
        token: Optional[str] = None
    ) -> Optional[User]:
        """Authenticate WebSocket connection."""

        # Get token from query params or first message
        if not token:
            token = websocket.query_params.get("token")

        if not token:
            # Try to get from subprotocol (for browsers that don't support query params)
            protocols = websocket.headers.get("sec-websocket-protocol", "").split(",")
            for protocol in protocols:
                if protocol.strip().startswith("access_token|"):
                    token = protocol.strip().split("|")[1]
                    break

        if not token:
            logger.warning("WebSocket connection without token")
            return None

        try:
            # Decode JWT
            payload = jwt.decode(
                token,
                settings.JWT_SECRET_KEY,
                algorithms=[settings.JWT_ALGORITHM]
            )

            user_id = payload.get("sub")
            tenant_id = payload.get("tenant_id")
            exp = payload.get("exp")

            # Check expiration
            if datetime.utcnow().timestamp() > exp:
                logger.warning("Expired token in WebSocket connection")
                return None

            # Check if token is blacklisted (logged out)
            if await self._is_token_blacklisted(token):
                logger.warning("Blacklisted token in WebSocket connection")
                return None

            # Get user
            user = await self.user_repo.get_by_id(user_id, tenant_id)
            if not user or not user.is_active:
                return None

            return user

        except JWTError as e:
            logger.warning(f"Invalid JWT in WebSocket: {str(e)}")
            return None

    async def _is_token_blacklisted(self, token: str) -> bool:
        """Check if token has been invalidated."""
        return await self.cache.exists(f"blacklist:{token}")

    async def create_session(
        self,
        user: User,
        document_id: str,
        websocket: WebSocket
    ) -> str:
        """Create collaboration session."""
        import uuid

        session_id = str(uuid.uuid4())

        session_data = {
            "user_id": user.id,
            "user_name": user.full_name,
            "user_email": user.email,
            "tenant_id": user.tenant_id,
            "document_id": document_id,
            "connected_at": datetime.utcnow().isoformat(),
            "client_ip": websocket.client.host
        }

        # Store session (expires in 24 hours)
        await self.cache.set(
            f"collab_session:{session_id}",
            session_data,
            expire=86400
        )

        # Add to document's active sessions
        await self.cache.sadd(
            f"document_sessions:{document_id}",
            session_id
        )

        logger.info(
            "Collaboration session created",
            session_id=session_id,
            user_id=user.id,
            document_id=document_id
        )

        return session_id

    async def end_session(self, session_id: str, document_id: str) -> None:
        """End collaboration session."""
        await self.cache.delete(f"collab_session:{session_id}")
        await self.cache.srem(f"document_sessions:{document_id}", session_id)

        logger.info("Collaboration session ended", session_id=session_id)
```

---

### 2. Real-Time Editing (SUB-COLLAB-REALTIME)

#### Micro-modules

##### 2.1 CRDT Document Sync (MICRO-COLLAB-SYNC)

**Purpose**: Real-time document synchronization using CRDTs (Yjs)

**WebSocket Server**:

```python
# backend/app/modules/collaboration/realtime/websocket_server.py
from typing import Dict, Set, Optional
from fastapi import WebSocket, WebSocketDisconnect
from dataclasses import dataclass, field
from datetime import datetime
import asyncio
import json
from y_py import YDoc, encode_state_as_update, apply_update
from app.core.logging import get_logger

logger = get_logger(__name__)

@dataclass
class ClientConnection:
    """Represents a connected client."""
    websocket: WebSocket
    user_id: str
    user_name: str
    session_id: str
    document_id: str
    permission: str
    connected_at: datetime = field(default_factory=datetime.utcnow)
    cursor_position: Optional[Dict] = None
    selection: Optional[Dict] = None

class CollaborationRoom:
    """Manages a single document's collaboration session."""

    def __init__(self, document_id: str, persistence_service):
        self.document_id = document_id
        self.persistence = persistence_service
        self.clients: Dict[str, ClientConnection] = {}
        self.doc: YDoc = YDoc()
        self._lock = asyncio.Lock()
        self._initialized = False

    async def initialize(self) -> None:
        """Load document state from persistence."""
        if self._initialized:
            return

        async with self._lock:
            stored_state = await self.persistence.load_document(self.document_id)
            if stored_state:
                apply_update(self.doc, stored_state)
            self._initialized = True

    async def add_client(self, client: ClientConnection) -> None:
        """Add client to room."""
        await self.initialize()

        self.clients[client.session_id] = client

        # Send current document state to new client
        state = encode_state_as_update(self.doc)
        await self._send_to_client(client, {
            "type": "sync",
            "state": state.hex()
        })

        # Broadcast presence to all clients
        await self._broadcast_presence()

        logger.info(
            f"Client joined room",
            document_id=self.document_id,
            user_id=client.user_id,
            total_clients=len(self.clients)
        )

    async def remove_client(self, session_id: str) -> None:
        """Remove client from room."""
        if session_id in self.clients:
            del self.clients[session_id]
            await self._broadcast_presence()

            logger.info(
                f"Client left room",
                document_id=self.document_id,
                remaining_clients=len(self.clients)
            )

    async def handle_update(
        self,
        session_id: str,
        update_data: bytes
    ) -> None:
        """Handle document update from client."""
        client = self.clients.get(session_id)
        if not client or client.permission == "view":
            return

        async with self._lock:
            # Apply update to local doc
            apply_update(self.doc, update_data)

            # Persist periodically (debounced in production)
            await self.persistence.save_document(
                self.document_id,
                encode_state_as_update(self.doc)
            )

        # Broadcast to other clients
        await self._broadcast_update(session_id, update_data)

    async def handle_awareness(
        self,
        session_id: str,
        awareness_data: Dict
    ) -> None:
        """Handle awareness update (cursor, selection, etc.)."""
        client = self.clients.get(session_id)
        if not client:
            return

        client.cursor_position = awareness_data.get("cursor")
        client.selection = awareness_data.get("selection")

        await self._broadcast_awareness(session_id, awareness_data)

    async def _send_to_client(
        self,
        client: ClientConnection,
        message: Dict
    ) -> None:
        """Send message to single client."""
        try:
            await client.websocket.send_json(message)
        except Exception as e:
            logger.error(f"Failed to send to client: {e}")

    async def _broadcast_update(
        self,
        sender_session: str,
        update_data: bytes
    ) -> None:
        """Broadcast update to all other clients."""
        message = {
            "type": "update",
            "data": update_data.hex(),
            "sender": sender_session
        }

        await self._broadcast(message, exclude=sender_session)

    async def _broadcast_awareness(
        self,
        sender_session: str,
        awareness_data: Dict
    ) -> None:
        """Broadcast awareness to all other clients."""
        client = self.clients.get(sender_session)
        if not client:
            return

        message = {
            "type": "awareness",
            "user": {
                "id": client.user_id,
                "name": client.user_name,
                "session_id": sender_session
            },
            "data": awareness_data
        }

        await self._broadcast(message, exclude=sender_session)

    async def _broadcast_presence(self) -> None:
        """Broadcast presence list to all clients."""
        users = [
            {
                "id": c.user_id,
                "name": c.user_name,
                "session_id": c.session_id,
                "cursor": c.cursor_position,
                "selection": c.selection
            }
            for c in self.clients.values()
        ]

        message = {
            "type": "presence",
            "users": users
        }

        await self._broadcast(message)

    async def _broadcast(
        self,
        message: Dict,
        exclude: Optional[str] = None
    ) -> None:
        """Broadcast message to all clients."""
        for session_id, client in self.clients.items():
            if session_id != exclude:
                await self._send_to_client(client, message)

    @property
    def is_empty(self) -> bool:
        return len(self.clients) == 0


class CollaborationManager:
    """Manages all collaboration rooms."""

    def __init__(self, persistence_service, access_control):
        self.rooms: Dict[str, CollaborationRoom] = {}
        self.persistence = persistence_service
        self.access_control = access_control
        self._lock = asyncio.Lock()

    async def get_or_create_room(self, document_id: str) -> CollaborationRoom:
        """Get existing room or create new one."""
        async with self._lock:
            if document_id not in self.rooms:
                self.rooms[document_id] = CollaborationRoom(
                    document_id,
                    self.persistence
                )
            return self.rooms[document_id]

    async def cleanup_room(self, document_id: str) -> None:
        """Remove empty room."""
        async with self._lock:
            room = self.rooms.get(document_id)
            if room and room.is_empty:
                del self.rooms[document_id]

    async def handle_connection(
        self,
        websocket: WebSocket,
        document_id: str,
        user: 'User',
        session_id: str
    ) -> None:
        """Handle new WebSocket connection."""

        # Check permission
        permission = await self.access_control.get_user_permission(
            document_id,
            user.id
        )

        if not permission:
            await websocket.close(code=4003, reason="Access denied")
            return

        room = await self.get_or_create_room(document_id)

        client = ClientConnection(
            websocket=websocket,
            user_id=user.id,
            user_name=user.full_name,
            session_id=session_id,
            document_id=document_id,
            permission=permission.value
        )

        await room.add_client(client)

        try:
            while True:
                data = await websocket.receive_json()
                await self._handle_message(room, session_id, data)

        except WebSocketDisconnect:
            await room.remove_client(session_id)
            await self.cleanup_room(document_id)

    async def _handle_message(
        self,
        room: CollaborationRoom,
        session_id: str,
        data: Dict
    ) -> None:
        """Handle incoming WebSocket message."""
        msg_type = data.get("type")

        if msg_type == "update":
            update_bytes = bytes.fromhex(data["data"])
            await room.handle_update(session_id, update_bytes)

        elif msg_type == "awareness":
            await room.handle_awareness(session_id, data.get("data", {}))

        elif msg_type == "ping":
            client = room.clients.get(session_id)
            if client:
                await client.websocket.send_json({"type": "pong"})
```

---

##### 2.2 Document Persistence (MICRO-COLLAB-PERSIST)

**Purpose**: Persist document changes and version history

**Implementation**:

```python
# backend/app/modules/collaboration/realtime/persistence.py
from typing import Optional, List
from datetime import datetime
from sqlalchemy import Column, String, LargeBinary, Integer, DateTime, ForeignKey
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import TenantBaseModel
from app.core.cache import RedisCache

class DocumentContent(TenantBaseModel):
    """Stores current document content."""

    __tablename__ = "document_contents"

    document_id = Column(String(36), ForeignKey("documents.id"), unique=True)
    content = Column(LargeBinary, nullable=False)  # Yjs encoded state
    version = Column(Integer, default=1)
    last_modified_at = Column(DateTime, default=datetime.utcnow)
    last_modified_by = Column(String(36), ForeignKey("users.id"))

class DocumentVersion(TenantBaseModel):
    """Stores document version history."""

    __tablename__ = "document_versions"

    document_id = Column(String(36), ForeignKey("documents.id"), index=True)
    version = Column(Integer, nullable=False)
    content = Column(LargeBinary, nullable=False)
    created_by = Column(String(36), ForeignKey("users.id"))
    created_at = Column(DateTime, default=datetime.utcnow)
    name = Column(String(255), nullable=True)  # Optional version name

class DocumentPersistence:
    """Handle document persistence and versioning."""

    def __init__(
        self,
        session: AsyncSession,
        cache: RedisCache,
        tenant_id: str
    ):
        self.session = session
        self.cache = cache
        self.tenant_id = tenant_id
        self._save_debounce: Dict[str, asyncio.Task] = {}

    async def load_document(self, document_id: str) -> Optional[bytes]:
        """Load document content."""
        # Try cache first
        cache_key = f"doc_content:{document_id}"
        cached = await self.cache.get(cache_key)
        if cached:
            return bytes.fromhex(cached)

        # Load from database
        query = select(DocumentContent).where(
            DocumentContent.document_id == document_id
        )
        result = await self.session.execute(query)
        content = result.scalar_one_or_none()

        if content:
            # Cache for 1 hour
            await self.cache.set(
                cache_key,
                content.content.hex(),
                expire=3600
            )
            return content.content

        return None

    async def save_document(
        self,
        document_id: str,
        content: bytes,
        user_id: Optional[str] = None,
        create_version: bool = False
    ) -> None:
        """Save document content with debouncing."""

        # Debounce saves (wait 2 seconds for more updates)
        if document_id in self._save_debounce:
            self._save_debounce[document_id].cancel()

        self._save_debounce[document_id] = asyncio.create_task(
            self._debounced_save(document_id, content, user_id, create_version)
        )

    async def _debounced_save(
        self,
        document_id: str,
        content: bytes,
        user_id: Optional[str],
        create_version: bool
    ) -> None:
        """Actually save after debounce delay."""
        await asyncio.sleep(2)

        try:
            # Get or create content record
            query = select(DocumentContent).where(
                DocumentContent.document_id == document_id
            )
            result = await self.session.execute(query)
            doc_content = result.scalar_one_or_none()

            if doc_content:
                # Create version before updating if requested
                if create_version:
                    await self._create_version(doc_content)

                doc_content.content = content
                doc_content.version += 1
                doc_content.last_modified_at = datetime.utcnow()
                doc_content.last_modified_by = user_id
            else:
                doc_content = DocumentContent(
                    tenant_id=self.tenant_id,
                    document_id=document_id,
                    content=content,
                    version=1,
                    last_modified_by=user_id
                )
                self.session.add(doc_content)

            await self.session.commit()

            # Update cache
            cache_key = f"doc_content:{document_id}"
            await self.cache.set(cache_key, content.hex(), expire=3600)

        except Exception as e:
            logger.error(f"Failed to save document: {e}")
        finally:
            del self._save_debounce[document_id]

    async def _create_version(self, doc_content: DocumentContent) -> None:
        """Create a version snapshot."""
        version = DocumentVersion(
            tenant_id=self.tenant_id,
            document_id=doc_content.document_id,
            version=doc_content.version,
            content=doc_content.content,
            created_by=doc_content.last_modified_by
        )
        self.session.add(version)

    async def get_versions(
        self,
        document_id: str,
        limit: int = 50
    ) -> List[Dict]:
        """Get version history."""
        query = select(DocumentVersion).where(
            DocumentVersion.document_id == document_id
        ).order_by(
            DocumentVersion.version.desc()
        ).limit(limit)

        result = await self.session.execute(query)
        versions = result.scalars().all()

        return [
            {
                "id": v.id,
                "version": v.version,
                "name": v.name,
                "created_at": v.created_at.isoformat(),
                "created_by": v.created_by
            }
            for v in versions
        ]

    async def restore_version(
        self,
        document_id: str,
        version_id: str,
        user_id: str
    ) -> bytes:
        """Restore document to specific version."""
        # Get version
        query = select(DocumentVersion).where(
            DocumentVersion.id == version_id,
            DocumentVersion.document_id == document_id
        )
        result = await self.session.execute(query)
        version = result.scalar_one_or_none()

        if not version:
            raise NotFoundError("Version", version_id)

        # Save current as version first
        current = await self.load_document(document_id)
        if current:
            await self.save_document(
                document_id,
                current,
                user_id,
                create_version=True
            )

        # Restore version
        await self.save_document(document_id, version.content, user_id)

        return version.content
```

---

### 3. Comments System (SUB-COLLAB-COMMENTS)

#### Micro-modules

##### 3.1 Comment Models (MICRO-COLLAB-COMMENT-MODELS)

**Purpose**: Data models for threaded comments

**Implementation**:

```python
# backend/app/modules/collaboration/models/comments.py
from sqlalchemy import Column, String, Text, Boolean, DateTime, ForeignKey, JSON, Integer
from sqlalchemy.orm import relationship
from app.core.database import TenantBaseModel
from datetime import datetime

class Comment(TenantBaseModel):
    """Comment on a document."""

    __tablename__ = "comments"

    document_id = Column(String(36), ForeignKey("documents.id"), nullable=False, index=True)
    author_id = Column(String(36), ForeignKey("users.id"), nullable=False)

    # Content
    content = Column(Text, nullable=False)

    # Threading
    parent_id = Column(String(36), ForeignKey("comments.id"), nullable=True)
    thread_id = Column(String(36), nullable=True, index=True)  # Root comment ID for thread

    # Position in document (for inline comments)
    anchor = Column(JSON, nullable=True)
    # {
    #   "type": "text",
    #   "start": {"path": [0, 1], "offset": 10},
    #   "end": {"path": [0, 1], "offset": 25},
    #   "quote": "selected text"
    # }

    # Status
    is_resolved = Column(Boolean, default=False)
    resolved_at = Column(DateTime, nullable=True)
    resolved_by = Column(String(36), ForeignKey("users.id"), nullable=True)

    # Edit tracking
    is_edited = Column(Boolean, default=False)
    edited_at = Column(DateTime, nullable=True)

    # Relationships
    document = relationship("Document", back_populates="comments")
    author = relationship("User", foreign_keys=[author_id])
    resolver = relationship("User", foreign_keys=[resolved_by])
    replies = relationship(
        "Comment",
        backref="parent",
        remote_side="Comment.id",
        cascade="all, delete-orphan"
    )
    reactions = relationship("CommentReaction", back_populates="comment", cascade="all, delete-orphan")
    mentions = relationship("CommentMention", back_populates="comment", cascade="all, delete-orphan")

class CommentReaction(TenantBaseModel):
    """Reaction to a comment (like, etc.)."""

    __tablename__ = "comment_reactions"

    comment_id = Column(String(36), ForeignKey("comments.id"), nullable=False)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False)
    reaction_type = Column(String(20), nullable=False)  # like, heart, thumbs_up, etc.

    comment = relationship("Comment", back_populates="reactions")
    user = relationship("User")

class CommentMention(TenantBaseModel):
    """User mention in a comment."""

    __tablename__ = "comment_mentions"

    comment_id = Column(String(36), ForeignKey("comments.id"), nullable=False)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False)
    notified_at = Column(DateTime, nullable=True)

    comment = relationship("Comment", back_populates="mentions")
    user = relationship("User")
```

---

##### 3.2 Comment Service (MICRO-COLLAB-COMMENT-SVC)

**Purpose**: Business logic for comments

**Implementation**:

```python
# backend/app/modules/collaboration/services/comments.py
from typing import List, Optional, Dict, Any
from datetime import datetime
from sqlalchemy import select, and_, or_
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession
from ..models.comments import Comment, CommentReaction, CommentMention
from ..models.access import DocumentPermission
from .access_control import DocumentAccessControl
from app.core.exceptions import NotFoundError, AuthorizationError
from app.core.logging import get_logger
import re

logger = get_logger(__name__)

class CommentService:
    """Handle comment operations."""

    def __init__(
        self,
        session: AsyncSession,
        access_control: DocumentAccessControl,
        notification_service,
        tenant_id: str
    ):
        self.session = session
        self.access_control = access_control
        self.notifications = notification_service
        self.tenant_id = tenant_id

    async def create_comment(
        self,
        document_id: str,
        user_id: str,
        content: str,
        parent_id: Optional[str] = None,
        anchor: Optional[Dict] = None
    ) -> Comment:
        """Create a new comment."""

        # Check permission
        await self.access_control.require_permission(
            document_id, user_id, DocumentPermission.COMMENT
        )

        # Determine thread_id
        thread_id = None
        if parent_id:
            parent = await self._get_comment(parent_id)
            thread_id = parent.thread_id or parent.id

        # Create comment
        comment = Comment(
            tenant_id=self.tenant_id,
            document_id=document_id,
            author_id=user_id,
            content=content,
            parent_id=parent_id,
            thread_id=thread_id,
            anchor=anchor
        )
        self.session.add(comment)
        await self.session.flush()

        # Set thread_id if this is root comment
        if not parent_id:
            comment.thread_id = comment.id

        # Process mentions
        await self._process_mentions(comment)

        await self.session.commit()

        logger.info(
            "Comment created",
            comment_id=comment.id,
            document_id=document_id,
            is_reply=parent_id is not None
        )

        return comment

    async def update_comment(
        self,
        comment_id: str,
        user_id: str,
        content: str
    ) -> Comment:
        """Update comment content."""

        comment = await self._get_comment(comment_id)

        # Only author can edit
        if comment.author_id != user_id:
            raise AuthorizationError("Only the author can edit this comment")

        comment.content = content
        comment.is_edited = True
        comment.edited_at = datetime.utcnow()

        # Reprocess mentions
        await self._clear_mentions(comment_id)
        await self._process_mentions(comment)

        await self.session.commit()

        return comment

    async def delete_comment(
        self,
        comment_id: str,
        user_id: str
    ) -> bool:
        """Delete a comment."""

        comment = await self._get_comment(comment_id)

        # Author or document admin can delete
        is_author = comment.author_id == user_id
        is_admin = await self.access_control.check_permission(
            comment.document_id, user_id, DocumentPermission.ADMIN
        )

        if not is_author and not is_admin:
            raise AuthorizationError("Permission denied to delete this comment")

        await self.session.delete(comment)
        await self.session.commit()

        return True

    async def resolve_comment(
        self,
        comment_id: str,
        user_id: str
    ) -> Comment:
        """Mark comment thread as resolved."""

        comment = await self._get_comment(comment_id)

        # Must have edit permission to resolve
        await self.access_control.require_permission(
            comment.document_id, user_id, DocumentPermission.EDIT
        )

        # Only resolve root comments
        if comment.parent_id:
            raise ValidationError("Can only resolve root comments")

        comment.is_resolved = True
        comment.resolved_at = datetime.utcnow()
        comment.resolved_by = user_id

        await self.session.commit()

        # Notify author
        if comment.author_id != user_id:
            await self.notifications.send_notification(
                user_id=comment.author_id,
                type="comment_resolved",
                data={
                    "comment_id": comment_id,
                    "document_id": comment.document_id,
                    "resolved_by": user_id
                }
            )

        return comment

    async def reopen_comment(
        self,
        comment_id: str,
        user_id: str
    ) -> Comment:
        """Reopen a resolved comment thread."""

        comment = await self._get_comment(comment_id)

        await self.access_control.require_permission(
            comment.document_id, user_id, DocumentPermission.EDIT
        )

        comment.is_resolved = False
        comment.resolved_at = None
        comment.resolved_by = None

        await self.session.commit()

        return comment

    async def add_reaction(
        self,
        comment_id: str,
        user_id: str,
        reaction_type: str
    ) -> CommentReaction:
        """Add reaction to comment."""

        comment = await self._get_comment(comment_id)

        # Check view permission
        await self.access_control.require_permission(
            comment.document_id, user_id, DocumentPermission.VIEW
        )

        # Check if already reacted with same type
        existing = await self._get_reaction(comment_id, user_id, reaction_type)
        if existing:
            return existing

        reaction = CommentReaction(
            tenant_id=self.tenant_id,
            comment_id=comment_id,
            user_id=user_id,
            reaction_type=reaction_type
        )
        self.session.add(reaction)
        await self.session.commit()

        return reaction

    async def remove_reaction(
        self,
        comment_id: str,
        user_id: str,
        reaction_type: str
    ) -> bool:
        """Remove reaction from comment."""

        reaction = await self._get_reaction(comment_id, user_id, reaction_type)
        if reaction:
            await self.session.delete(reaction)
            await self.session.commit()
            return True
        return False

    async def get_document_comments(
        self,
        document_id: str,
        user_id: str,
        include_resolved: bool = False
    ) -> List[Dict]:
        """Get all comments for a document."""

        # Check permission
        await self.access_control.require_permission(
            document_id, user_id, DocumentPermission.VIEW
        )

        query = select(Comment).where(
            and_(
                Comment.document_id == document_id,
                Comment.parent_id.is_(None),  # Only root comments
                Comment.is_deleted == False
            )
        ).options(
            selectinload(Comment.author),
            selectinload(Comment.replies).selectinload(Comment.author),
            selectinload(Comment.reactions)
        ).order_by(Comment.created_at.desc())

        if not include_resolved:
            query = query.where(Comment.is_resolved == False)

        result = await self.session.execute(query)
        comments = result.scalars().all()

        return [self._format_comment(c) for c in comments]

    async def get_thread(
        self,
        thread_id: str,
        user_id: str
    ) -> Dict:
        """Get comment thread."""

        root = await self._get_comment(thread_id)

        await self.access_control.require_permission(
            root.document_id, user_id, DocumentPermission.VIEW
        )

        query = select(Comment).where(
            and_(
                Comment.thread_id == thread_id,
                Comment.is_deleted == False
            )
        ).options(
            selectinload(Comment.author),
            selectinload(Comment.reactions)
        ).order_by(Comment.created_at.asc())

        result = await self.session.execute(query)
        comments = result.scalars().all()

        return {
            "root": self._format_comment(root),
            "replies": [self._format_comment(c) for c in comments if c.id != thread_id]
        }

    async def _get_comment(self, comment_id: str) -> Comment:
        """Get comment by ID."""
        query = select(Comment).where(
            and_(
                Comment.id == comment_id,
                Comment.tenant_id == self.tenant_id,
                Comment.is_deleted == False
            )
        )
        result = await self.session.execute(query)
        comment = result.scalar_one_or_none()

        if not comment:
            raise NotFoundError("Comment", comment_id)
        return comment

    async def _get_reaction(
        self,
        comment_id: str,
        user_id: str,
        reaction_type: str
    ) -> Optional[CommentReaction]:
        """Get existing reaction."""
        query = select(CommentReaction).where(
            and_(
                CommentReaction.comment_id == comment_id,
                CommentReaction.user_id == user_id,
                CommentReaction.reaction_type == reaction_type
            )
        )
        result = await self.session.execute(query)
        return result.scalar_one_or_none()

    async def _process_mentions(self, comment: Comment) -> None:
        """Extract and process @mentions."""
        # Find @mentions in content
        mentions = re.findall(r'@\[([^\]]+)\]\(([^)]+)\)', comment.content)

        for name, user_id in mentions:
            mention = CommentMention(
                tenant_id=self.tenant_id,
                comment_id=comment.id,
                user_id=user_id
            )
            self.session.add(mention)

            # Send notification
            await self.notifications.send_notification(
                user_id=user_id,
                type="mention",
                data={
                    "comment_id": comment.id,
                    "document_id": comment.document_id,
                    "mentioned_by": comment.author_id,
                    "content_preview": comment.content[:100]
                }
            )
            mention.notified_at = datetime.utcnow()

    async def _clear_mentions(self, comment_id: str) -> None:
        """Clear existing mentions."""
        query = select(CommentMention).where(
            CommentMention.comment_id == comment_id
        )
        result = await self.session.execute(query)
        for mention in result.scalars():
            await self.session.delete(mention)

    def _format_comment(self, comment: Comment) -> Dict:
        """Format comment for API response."""
        return {
            "id": comment.id,
            "content": comment.content,
            "author": {
                "id": comment.author.id,
                "name": comment.author.full_name,
                "avatar": comment.author.avatar_url
            },
            "anchor": comment.anchor,
            "is_resolved": comment.is_resolved,
            "resolved_at": comment.resolved_at.isoformat() if comment.resolved_at else None,
            "is_edited": comment.is_edited,
            "created_at": comment.created_at.isoformat(),
            "updated_at": comment.updated_at.isoformat(),
            "reactions": self._aggregate_reactions(comment.reactions),
            "reply_count": len(comment.replies) if hasattr(comment, 'replies') else 0
        }

    def _aggregate_reactions(self, reactions: List[CommentReaction]) -> Dict:
        """Aggregate reactions by type."""
        result = {}
        for r in reactions:
            if r.reaction_type not in result:
                result[r.reaction_type] = {"count": 0, "users": []}
            result[r.reaction_type]["count"] += 1
            result[r.reaction_type]["users"].append(r.user_id)
        return result
```

---

### 4. Presence & Awareness (SUB-COLLAB-PRESENCE)

#### Micro-modules

##### 4.1 Presence Tracking (MICRO-COLLAB-PRESENCE)

**Purpose**: Track who's viewing/editing documents

**Implementation**:

```python
# backend/app/modules/collaboration/presence/tracker.py
from typing import Dict, List, Optional, Set
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from app.core.cache import RedisCache
import json

@dataclass
class UserPresence:
    """User presence information."""
    user_id: str
    user_name: str
    avatar_url: Optional[str]
    document_id: str
    session_id: str
    cursor_position: Optional[Dict] = None
    selection: Optional[Dict] = None
    last_active: datetime = None
    color: str = None  # Assigned color for cursor

    def to_dict(self) -> Dict:
        data = asdict(self)
        if self.last_active:
            data["last_active"] = self.last_active.isoformat()
        return data

class PresenceTracker:
    """Track user presence across documents."""

    # Colors for user cursors
    CURSOR_COLORS = [
        "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4",
        "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F",
        "#BB8FCE", "#85C1E9", "#F8B500", "#00CED1"
    ]

    def __init__(self, cache: RedisCache):
        self.cache = cache
        self.presence_ttl = 300  # 5 minutes

    async def join_document(
        self,
        document_id: str,
        user_id: str,
        user_name: str,
        session_id: str,
        avatar_url: Optional[str] = None
    ) -> UserPresence:
        """Register user presence on document."""

        # Get assigned color
        color = await self._assign_color(document_id, user_id)

        presence = UserPresence(
            user_id=user_id,
            user_name=user_name,
            avatar_url=avatar_url,
            document_id=document_id,
            session_id=session_id,
            last_active=datetime.utcnow(),
            color=color
        )

        # Store in Redis
        key = f"presence:{document_id}:{session_id}"
        await self.cache.set(key, presence.to_dict(), expire=self.presence_ttl)

        # Add to document's active users set
        await self.cache.sadd(f"doc_users:{document_id}", session_id)

        return presence

    async def leave_document(
        self,
        document_id: str,
        session_id: str
    ) -> None:
        """Remove user presence from document."""
        key = f"presence:{document_id}:{session_id}"
        await self.cache.delete(key)
        await self.cache.srem(f"doc_users:{document_id}", session_id)

    async def update_cursor(
        self,
        document_id: str,
        session_id: str,
        cursor_position: Optional[Dict] = None,
        selection: Optional[Dict] = None
    ) -> None:
        """Update user's cursor/selection position."""
        key = f"presence:{document_id}:{session_id}"
        data = await self.cache.get(key)

        if data:
            data["cursor_position"] = cursor_position
            data["selection"] = selection
            data["last_active"] = datetime.utcnow().isoformat()
            await self.cache.set(key, data, expire=self.presence_ttl)

    async def heartbeat(
        self,
        document_id: str,
        session_id: str
    ) -> None:
        """Update last active time."""
        key = f"presence:{document_id}:{session_id}"
        data = await self.cache.get(key)

        if data:
            data["last_active"] = datetime.utcnow().isoformat()
            await self.cache.set(key, data, expire=self.presence_ttl)

    async def get_document_presence(
        self,
        document_id: str
    ) -> List[UserPresence]:
        """Get all users present on document."""
        session_ids = await self.cache.smembers(f"doc_users:{document_id}")

        presences = []
        for session_id in session_ids:
            key = f"presence:{document_id}:{session_id}"
            data = await self.cache.get(key)

            if data:
                # Check if still active (within TTL)
                last_active = datetime.fromisoformat(data["last_active"])
                if datetime.utcnow() - last_active < timedelta(seconds=self.presence_ttl):
                    presences.append(UserPresence(**{
                        **data,
                        "last_active": last_active
                    }))
                else:
                    # Cleanup stale presence
                    await self.leave_document(document_id, session_id)

        return presences

    async def get_user_documents(self, user_id: str) -> List[str]:
        """Get all documents a user is currently viewing."""
        # This would require an additional index
        # For now, scan presence keys
        pattern = f"presence:*"
        keys = await self.cache.keys(pattern)

        documents = []
        for key in keys:
            data = await self.cache.get(key)
            if data and data.get("user_id") == user_id:
                documents.append(data["document_id"])

        return documents

    async def _assign_color(
        self,
        document_id: str,
        user_id: str
    ) -> str:
        """Assign a consistent color to user for document."""
        # Use hash for consistent color assignment
        color_index = hash(f"{document_id}:{user_id}") % len(self.CURSOR_COLORS)
        return self.CURSOR_COLORS[color_index]

    async def cleanup_stale_presence(self) -> int:
        """Cleanup stale presence records (run periodically)."""
        cleaned = 0
        pattern = f"doc_users:*"
        doc_keys = await self.cache.keys(pattern)

        for doc_key in doc_keys:
            document_id = doc_key.split(":")[1]
            session_ids = await self.cache.smembers(doc_key)

            for session_id in session_ids:
                presence_key = f"presence:{document_id}:{session_id}"
                data = await self.cache.get(presence_key)

                if not data:
                    await self.cache.srem(doc_key, session_id)
                    cleaned += 1

        return cleaned
```

---

## Frontend Implementation

### React Components

```typescript
// frontend/src/modules/collaboration/components/CollaborativeEditor.tsx
import React, { useEffect, useState, useCallback } from 'react';
import { useEditor, EditorContent } from '@tiptap/react';
import StarterKit from '@tiptap/starter-kit';
import Collaboration from '@tiptap/extension-collaboration';
import CollaborationCursor from '@tiptap/extension-collaboration-cursor';
import * as Y from 'yjs';
import { WebsocketProvider } from 'y-websocket';
import { useAuth } from '@/hooks/useAuth';
import { CommentsPanel } from './CommentsPanel';
import { PresenceAvatars } from './PresenceAvatars';
import { DocumentToolbar } from './DocumentToolbar';

interface CollaborativeEditorProps {
  documentId: string;
  permission: 'view' | 'comment' | 'edit' | 'admin';
}

export const CollaborativeEditor: React.FC<CollaborativeEditorProps> = ({
  documentId,
  permission
}) => {
  const { user, token } = useAuth();
  const [ydoc] = useState(() => new Y.Doc());
  const [provider, setProvider] = useState<WebsocketProvider | null>(null);
  const [connected, setConnected] = useState(false);
  const [collaborators, setCollaborators] = useState<any[]>([]);

  // Initialize WebSocket connection
  useEffect(() => {
    const wsProvider = new WebsocketProvider(
      `${process.env.REACT_APP_WS_URL}/collaborate`,
      documentId,
      ydoc,
      {
        params: { token }
      }
    );

    wsProvider.on('status', ({ status }: { status: string }) => {
      setConnected(status === 'connected');
    });

    wsProvider.awareness.on('change', () => {
      const states = Array.from(wsProvider.awareness.getStates().values());
      setCollaborators(states.filter(s => s.user));
    });

    // Set local user info
    wsProvider.awareness.setLocalStateField('user', {
      id: user.id,
      name: user.name,
      color: getRandomColor(),
      avatar: user.avatarUrl
    });

    setProvider(wsProvider);

    return () => {
      wsProvider.destroy();
    };
  }, [documentId, token, user, ydoc]);

  // Initialize TipTap editor
  const editor = useEditor({
    extensions: [
      StarterKit,
      Collaboration.configure({
        document: ydoc
      }),
      CollaborationCursor.configure({
        provider,
        user: {
          name: user.name,
          color: getRandomColor()
        }
      })
    ],
    editable: permission === 'edit' || permission === 'admin'
  });

  // Handle cursor position updates
  const handleCursorUpdate = useCallback(() => {
    if (!provider || !editor) return;

    const selection = editor.state.selection;
    provider.awareness.setLocalStateField('cursor', {
      anchor: selection.anchor,
      head: selection.head
    });
  }, [provider, editor]);

  useEffect(() => {
    if (editor) {
      editor.on('selectionUpdate', handleCursorUpdate);
      return () => {
        editor.off('selectionUpdate', handleCursorUpdate);
      };
    }
  }, [editor, handleCursorUpdate]);

  return (
    <div className="collaborative-editor">
      <div className="editor-header">
        <PresenceAvatars collaborators={collaborators} />
        <ConnectionStatus connected={connected} />
      </div>

      <DocumentToolbar
        editor={editor}
        documentId={documentId}
        permission={permission}
      />

      <div className="editor-container">
        <div className="editor-content">
          <EditorContent editor={editor} />
        </div>

        {(permission !== 'view') && (
          <CommentsPanel
            documentId={documentId}
            editor={editor}
            permission={permission}
          />
        )}
      </div>
    </div>
  );
};

// Presence avatars component
const PresenceAvatars: React.FC<{ collaborators: any[] }> = ({ collaborators }) => {
  return (
    <div className="presence-avatars">
      {collaborators.map((collab, index) => (
        <div
          key={collab.user.id}
          className="avatar"
          style={{
            borderColor: collab.user.color,
            zIndex: collaborators.length - index
          }}
          title={collab.user.name}
        >
          {collab.user.avatar ? (
            <img src={collab.user.avatar} alt={collab.user.name} />
          ) : (
            <span>{collab.user.name.charAt(0)}</span>
          )}
        </div>
      ))}
      {collaborators.length > 0 && (
        <span className="collaborator-count">
          {collaborators.length} editing
        </span>
      )}
    </div>
  );
};

// Connection status indicator
const ConnectionStatus: React.FC<{ connected: boolean }> = ({ connected }) => (
  <div className={`connection-status ${connected ? 'connected' : 'disconnected'}`}>
    <span className="status-dot" />
    {connected ? 'Connected' : 'Reconnecting...'}
  </div>
);

function getRandomColor(): string {
  const colors = [
    '#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4',
    '#FFEAA7', '#DDA0DD', '#98D8C8', '#F7DC6F'
  ];
  return colors[Math.floor(Math.random() * colors.length)];
}
```

```typescript
// frontend/src/modules/collaboration/components/CommentsPanel.tsx
import React, { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { commentApi } from '@/api/comments';
import { useAuth } from '@/hooks/useAuth';
import { formatDistanceToNow } from 'date-fns';

interface CommentsPanelProps {
  documentId: string;
  editor: any;
  permission: string;
}

export const CommentsPanel: React.FC<CommentsPanelProps> = ({
  documentId,
  editor,
  permission
}) => {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [activeThread, setActiveThread] = useState<string | null>(null);
  const [newComment, setNewComment] = useState('');
  const [showResolved, setShowResolved] = useState(false);

  // Fetch comments
  const { data: comments, isLoading } = useQuery({
    queryKey: ['comments', documentId, showResolved],
    queryFn: () => commentApi.getDocumentComments(documentId, showResolved)
  });

  // Create comment mutation
  const createMutation = useMutation({
    mutationFn: (data: { content: string; parentId?: string; anchor?: any }) =>
      commentApi.createComment(documentId, data),
    onSuccess: () => {
      queryClient.invalidateQueries(['comments', documentId]);
      setNewComment('');
    }
  });

  // Resolve comment mutation
  const resolveMutation = useMutation({
    mutationFn: (commentId: string) => commentApi.resolveComment(commentId),
    onSuccess: () => {
      queryClient.invalidateQueries(['comments', documentId]);
    }
  });

  // Handle selection for inline comments
  const handleAddInlineComment = () => {
    if (!editor) return;

    const { from, to } = editor.state.selection;
    const selectedText = editor.state.doc.textBetween(from, to);

    if (selectedText) {
      const anchor = {
        type: 'text',
        start: from,
        end: to,
        quote: selectedText
      };

      // Show comment input with anchor
      setActiveThread('new');
      // Store anchor for when comment is submitted
    }
  };

  const handleSubmitComment = () => {
    if (!newComment.trim()) return;

    createMutation.mutate({
      content: newComment,
      parentId: activeThread !== 'new' ? activeThread : undefined
    });
  };

  return (
    <div className="comments-panel">
      <div className="comments-header">
        <h3>Comments</h3>
        <label className="show-resolved">
          <input
            type="checkbox"
            checked={showResolved}
            onChange={(e) => setShowResolved(e.target.checked)}
          />
          Show resolved
        </label>
      </div>

      {/* Comment list */}
      <div className="comments-list">
        {isLoading ? (
          <div className="loading">Loading comments...</div>
        ) : comments?.length === 0 ? (
          <div className="no-comments">
            No comments yet. Select text to add a comment.
          </div>
        ) : (
          comments?.map((comment: any) => (
            <CommentThread
              key={comment.id}
              comment={comment}
              isActive={activeThread === comment.id}
              onActivate={() => setActiveThread(comment.id)}
              onResolve={() => resolveMutation.mutate(comment.id)}
              canResolve={permission === 'edit' || permission === 'admin'}
            />
          ))
        )}
      </div>

      {/* New comment input */}
      {permission !== 'view' && (
        <div className="new-comment">
          <MentionInput
            value={newComment}
            onChange={setNewComment}
            placeholder="Add a comment..."
            documentId={documentId}
          />
          <button
            onClick={handleSubmitComment}
            disabled={!newComment.trim() || createMutation.isLoading}
          >
            {createMutation.isLoading ? 'Sending...' : 'Comment'}
          </button>
        </div>
      )}
    </div>
  );
};

// Comment thread component
const CommentThread: React.FC<{
  comment: any;
  isActive: boolean;
  onActivate: () => void;
  onResolve: () => void;
  canResolve: boolean;
}> = ({ comment, isActive, onActivate, onResolve, canResolve }) => {
  const [replyContent, setReplyContent] = useState('');
  const queryClient = useQueryClient();

  const replyMutation = useMutation({
    mutationFn: (content: string) =>
      commentApi.createComment(comment.document_id, {
        content,
        parentId: comment.id
      }),
    onSuccess: () => {
      queryClient.invalidateQueries(['comments']);
      setReplyContent('');
    }
  });

  return (
    <div
      className={`comment-thread ${isActive ? 'active' : ''} ${comment.is_resolved ? 'resolved' : ''}`}
      onClick={onActivate}
    >
      {/* Quote/anchor indicator */}
      {comment.anchor?.quote && (
        <div className="comment-quote">
          "{comment.anchor.quote}"
        </div>
      )}

      {/* Main comment */}
      <div className="comment-main">
        <div className="comment-header">
          <img
            src={comment.author.avatar || '/default-avatar.png'}
            alt={comment.author.name}
            className="author-avatar"
          />
          <span className="author-name">{comment.author.name}</span>
          <span className="comment-time">
            {formatDistanceToNow(new Date(comment.created_at), { addSuffix: true })}
          </span>
          {comment.is_edited && <span className="edited-tag">edited</span>}
        </div>

        <div className="comment-content">
          {comment.content}
        </div>

        {/* Reactions */}
        <CommentReactions
          commentId={comment.id}
          reactions={comment.reactions}
        />
      </div>

      {/* Replies */}
      {comment.reply_count > 0 && (
        <div className="comment-replies">
          {/* Fetch and render replies when expanded */}
        </div>
      )}

      {/* Actions */}
      <div className="comment-actions">
        {!comment.is_resolved && canResolve && (
          <button onClick={onResolve} className="resolve-btn">
            ✓ Resolve
          </button>
        )}
        {comment.is_resolved && (
          <span className="resolved-badge">Resolved</span>
        )}
      </div>

      {/* Reply input */}
      {isActive && !comment.is_resolved && (
        <div className="reply-input">
          <input
            type="text"
            value={replyContent}
            onChange={(e) => setReplyContent(e.target.value)}
            placeholder="Reply..."
            onKeyPress={(e) => {
              if (e.key === 'Enter' && replyContent.trim()) {
                replyMutation.mutate(replyContent);
              }
            }}
          />
        </div>
      )}
    </div>
  );
};

// Mention input with autocomplete
const MentionInput: React.FC<{
  value: string;
  onChange: (value: string) => void;
  placeholder: string;
  documentId: string;
}> = ({ value, onChange, placeholder, documentId }) => {
  const [showMentions, setShowMentions] = useState(false);
  const [mentionQuery, setMentionQuery] = useState('');
  const [mentionIndex, setMentionIndex] = useState(0);

  // Fetch collaborators for mention suggestions
  const { data: collaborators } = useQuery({
    queryKey: ['collaborators', documentId],
    queryFn: () => commentApi.getCollaborators(documentId)
  });

  const handleInput = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    const newValue = e.target.value;
    onChange(newValue);

    // Check for @ trigger
    const lastAt = newValue.lastIndexOf('@');
    if (lastAt !== -1 && lastAt === newValue.length - 1) {
      setShowMentions(true);
      setMentionQuery('');
    } else if (showMentions) {
      const query = newValue.slice(lastAt + 1);
      if (query.includes(' ')) {
        setShowMentions(false);
      } else {
        setMentionQuery(query);
      }
    }
  };

  const insertMention = (user: any) => {
    const lastAt = value.lastIndexOf('@');
    const beforeAt = value.slice(0, lastAt);
    const mention = `@[${user.name}](${user.id}) `;
    onChange(beforeAt + mention);
    setShowMentions(false);
  };

  const filteredUsers = collaborators?.filter((u: any) =>
    u.name.toLowerCase().includes(mentionQuery.toLowerCase())
  ) || [];

  return (
    <div className="mention-input-container">
      <textarea
        value={value}
        onChange={handleInput}
        placeholder={placeholder}
        rows={3}
      />

      {showMentions && filteredUsers.length > 0 && (
        <div className="mention-suggestions">
          {filteredUsers.map((user: any, index: number) => (
            <div
              key={user.id}
              className={`mention-item ${index === mentionIndex ? 'active' : ''}`}
              onClick={() => insertMention(user)}
            >
              <img src={user.avatar || '/default-avatar.png'} alt="" />
              <span>{user.name}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
```

---

## API Endpoints

```python
# backend/app/modules/collaboration/routes.py
from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect, Query
from typing import Optional, List

router = APIRouter(prefix="/collaboration", tags=["Collaboration"])

# Document management
@router.post("/documents", response_model=DocumentResponse)
async def create_document(
    data: DocumentCreate,
    current_user = Depends(get_current_user),
    service: DocumentService = Depends()
):
    """Create a new collaborative document."""
    return await service.create_document(data, current_user.id)

@router.get("/documents/{document_id}", response_model=DocumentResponse)
async def get_document(
    document_id: str,
    current_user = Depends(get_current_user),
    service: DocumentService = Depends()
):
    """Get document details."""
    return await service.get_document(document_id, current_user.id)

# Sharing
@router.post("/documents/{document_id}/share")
async def share_document(
    document_id: str,
    data: ShareRequest,
    current_user = Depends(get_current_user),
    access_control: DocumentAccessControl = Depends()
):
    """Share document with user."""
    return await access_control.share_document(
        document_id,
        current_user.id,
        user_id=data.user_id,
        email=data.email,
        permission=data.permission
    )

@router.get("/documents/{document_id}/collaborators")
async def get_collaborators(
    document_id: str,
    current_user = Depends(get_current_user),
    access_control: DocumentAccessControl = Depends()
):
    """Get document collaborators."""
    return await access_control.get_document_collaborators(document_id)

# Comments
@router.get("/documents/{document_id}/comments")
async def get_comments(
    document_id: str,
    include_resolved: bool = Query(False),
    current_user = Depends(get_current_user),
    service: CommentService = Depends()
):
    """Get document comments."""
    return await service.get_document_comments(
        document_id,
        current_user.id,
        include_resolved
    )

@router.post("/documents/{document_id}/comments")
async def create_comment(
    document_id: str,
    data: CommentCreate,
    current_user = Depends(get_current_user),
    service: CommentService = Depends()
):
    """Create a comment."""
    return await service.create_comment(
        document_id,
        current_user.id,
        data.content,
        data.parent_id,
        data.anchor
    )

@router.post("/comments/{comment_id}/resolve")
async def resolve_comment(
    comment_id: str,
    current_user = Depends(get_current_user),
    service: CommentService = Depends()
):
    """Resolve a comment thread."""
    return await service.resolve_comment(comment_id, current_user.id)

@router.post("/comments/{comment_id}/reactions")
async def add_reaction(
    comment_id: str,
    data: ReactionCreate,
    current_user = Depends(get_current_user),
    service: CommentService = Depends()
):
    """Add reaction to comment."""
    return await service.add_reaction(
        comment_id,
        current_user.id,
        data.reaction_type
    )

# Presence
@router.get("/documents/{document_id}/presence")
async def get_presence(
    document_id: str,
    current_user = Depends(get_current_user),
    tracker: PresenceTracker = Depends()
):
    """Get users currently viewing document."""
    return await tracker.get_document_presence(document_id)

# Version history
@router.get("/documents/{document_id}/versions")
async def get_versions(
    document_id: str,
    current_user = Depends(get_current_user),
    service: DocumentService = Depends()
):
    """Get document version history."""
    return await service.get_versions(document_id, current_user.id)

@router.post("/documents/{document_id}/versions/{version_id}/restore")
async def restore_version(
    document_id: str,
    version_id: str,
    current_user = Depends(get_current_user),
    service: DocumentService = Depends()
):
    """Restore document to specific version."""
    return await service.restore_version(
        document_id,
        version_id,
        current_user.id
    )

# WebSocket endpoint
@router.websocket("/ws/{document_id}")
async def websocket_endpoint(
    websocket: WebSocket,
    document_id: str,
    token: str = Query(...),
    authenticator: WebSocketAuthenticator = Depends(),
    manager: CollaborationManager = Depends()
):
    """WebSocket endpoint for real-time collaboration."""
    await websocket.accept()

    # Authenticate
    user = await authenticator.authenticate(websocket, token)
    if not user:
        await websocket.close(code=4001, reason="Authentication failed")
        return

    # Create session
    session_id = await authenticator.create_session(user, document_id, websocket)

    try:
        await manager.handle_connection(websocket, document_id, user, session_id)
    except WebSocketDisconnect:
        await authenticator.end_session(session_id, document_id)
```

---

## Styles

```css
/* frontend/src/modules/collaboration/styles/editor.css */

.collaborative-editor {
  display: flex;
  flex-direction: column;
  height: 100vh;
  background: #fff;
}

.editor-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 12px 20px;
  border-bottom: 1px solid #e0e0e0;
  background: #fafafa;
}

.presence-avatars {
  display: flex;
  align-items: center;
  gap: -8px;
}

.presence-avatars .avatar {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  border: 2px solid;
  overflow: hidden;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #e0e0e0;
  font-weight: 600;
  font-size: 14px;
  color: #333;
  margin-left: -8px;
}

.presence-avatars .avatar:first-child {
  margin-left: 0;
}

.presence-avatars .avatar img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.collaborator-count {
  margin-left: 12px;
  font-size: 13px;
  color: #666;
}

.connection-status {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
}

.connection-status .status-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
}

.connection-status.connected .status-dot {
  background: #4caf50;
}

.connection-status.disconnected .status-dot {
  background: #ff9800;
  animation: pulse 1.5s infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}

.editor-container {
  display: flex;
  flex: 1;
  overflow: hidden;
}

.editor-content {
  flex: 1;
  padding: 40px 60px;
  overflow-y: auto;
}

/* TipTap editor styles */
.ProseMirror {
  outline: none;
  min-height: 500px;
}

.ProseMirror p {
  margin: 0 0 1em;
}

/* Collaboration cursor styles */
.collaboration-cursor__caret {
  position: relative;
  margin-left: -1px;
  margin-right: -1px;
  border-left: 1px solid;
  border-right: 1px solid;
  word-break: normal;
  pointer-events: none;
}

.collaboration-cursor__label {
  position: absolute;
  top: -1.4em;
  left: -1px;
  font-size: 12px;
  font-weight: 600;
  line-height: 1;
  padding: 2px 6px;
  border-radius: 3px 3px 3px 0;
  white-space: nowrap;
  color: white;
}

/* Comments panel */
.comments-panel {
  width: 320px;
  border-left: 1px solid #e0e0e0;
  display: flex;
  flex-direction: column;
  background: #fafafa;
}

.comments-header {
  padding: 16px;
  border-bottom: 1px solid #e0e0e0;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.comments-header h3 {
  margin: 0;
  font-size: 16px;
  font-weight: 600;
}

.show-resolved {
  font-size: 13px;
  color: #666;
  display: flex;
  align-items: center;
  gap: 6px;
}

.comments-list {
  flex: 1;
  overflow-y: auto;
  padding: 16px;
}

.comment-thread {
  background: white;
  border-radius: 8px;
  padding: 12px;
  margin-bottom: 12px;
  box-shadow: 0 1px 3px rgba(0,0,0,0.1);
  cursor: pointer;
  transition: box-shadow 0.2s;
}

.comment-thread:hover {
  box-shadow: 0 2px 8px rgba(0,0,0,0.15);
}

.comment-thread.active {
  border: 2px solid #1976d2;
}

.comment-thread.resolved {
  opacity: 0.6;
}

.comment-quote {
  font-size: 13px;
  color: #666;
  padding: 8px 12px;
  background: #f5f5f5;
  border-left: 3px solid #1976d2;
  margin-bottom: 12px;
  font-style: italic;
}

.comment-header {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 8px;
}

.author-avatar {
  width: 24px;
  height: 24px;
  border-radius: 50%;
}

.author-name {
  font-weight: 600;
  font-size: 14px;
}

.comment-time {
  font-size: 12px;
  color: #999;
}

.edited-tag {
  font-size: 11px;
  color: #999;
  font-style: italic;
}

.comment-content {
  font-size: 14px;
  line-height: 1.5;
  color: #333;
}

.comment-actions {
  margin-top: 12px;
  display: flex;
  gap: 12px;
}

.resolve-btn {
  font-size: 13px;
  color: #4caf50;
  background: none;
  border: none;
  cursor: pointer;
  padding: 4px 8px;
  border-radius: 4px;
}

.resolve-btn:hover {
  background: #e8f5e9;
}

.resolved-badge {
  font-size: 12px;
  color: #4caf50;
  background: #e8f5e9;
  padding: 2px 8px;
  border-radius: 10px;
}

.reply-input {
  margin-top: 12px;
  padding-top: 12px;
  border-top: 1px solid #eee;
}

.reply-input input {
  width: 100%;
  padding: 8px 12px;
  border: 1px solid #ddd;
  border-radius: 20px;
  font-size: 14px;
}

.new-comment {
  padding: 16px;
  border-top: 1px solid #e0e0e0;
  background: white;
}

.new-comment textarea {
  width: 100%;
  padding: 12px;
  border: 1px solid #ddd;
  border-radius: 8px;
  font-size: 14px;
  resize: none;
  margin-bottom: 8px;
}

.new-comment button {
  width: 100%;
  padding: 10px;
  background: #1976d2;
  color: white;
  border: none;
  border-radius: 8px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
}

.new-comment button:disabled {
  background: #bdbdbd;
  cursor: not-allowed;
}

/* Mention suggestions */
.mention-suggestions {
  position: absolute;
  bottom: 100%;
  left: 0;
  right: 0;
  background: white;
  border: 1px solid #ddd;
  border-radius: 8px;
  box-shadow: 0 -4px 12px rgba(0,0,0,0.1);
  max-height: 200px;
  overflow-y: auto;
}

.mention-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  cursor: pointer;
}

.mention-item:hover,
.mention-item.active {
  background: #f5f5f5;
}

.mention-item img {
  width: 24px;
  height: 24px;
  border-radius: 50%;
}
```

---

## Implementation Order

1. **MICRO-COLLAB-ACCESS** - Document access control models and service
2. **MICRO-COLLAB-WSAUTH** - WebSocket authentication
3. **MICRO-COLLAB-SYNC** - CRDT document synchronization
4. **MICRO-COLLAB-PERSIST** - Document persistence and versioning
5. **MICRO-COLLAB-COMMENT-MODELS** - Comment data models
6. **MICRO-COLLAB-COMMENT-SVC** - Comment service
7. **MICRO-COLLAB-PRESENCE** - Presence tracking
8. **Frontend Components** - React components and styles

---

## Best Practices Checklist

- [ ] WebSocket connections authenticated via JWT
- [ ] Document access verified before operations
- [ ] CRDT sync prevents conflicts
- [ ] Changes persisted with debouncing
- [ ] Version history maintained
- [ ] Comments support threading and mentions
- [ ] Presence shows real-time collaborators
- [ ] Cursor positions shared between users
- [ ] Offline changes queued and synced
- [ ] Connection status clearly indicated
- [ ] Mobile-responsive design
- [ ] Keyboard shortcuts for common actions
