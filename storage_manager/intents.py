# storage_manager/intents.py
import time
from dataclasses import dataclass, field as dc_field
from typing import Dict, List, Optional, Protocol, runtime_checkable

INTENT_TTL_SECONDS: float = 3600.0
DIFF_PREVIEW_CAP: int = 100


@dataclass
class SyncIntentDocument:
    intent_id: str
    resource_type: str
    status: str  # PENDING | EXECUTING | EXECUTED | EXPIRED
    created_at: float
    expires_at: float
    gcs_snapshot_sha: str
    index_snapshot_sha: str
    diff: dict  # full diff stored in-memory
    diff_preview: dict  # response-safe preview (capped)
    applied_at: Optional[float] = None
    duration_ms: Optional[float] = None
    backup_path: Optional[str] = None
    error: Optional[str] = None


@runtime_checkable
class IntentStore(Protocol):
    def put(self, intent: SyncIntentDocument) -> None: ...
    def get(self, intent_id: str) -> Optional[SyncIntentDocument]: ...
    def list_recent(self, resource_type: str, limit: int = 20) -> List[SyncIntentDocument]: ...
    def cleanup_expired(self) -> int: ...


class MemoryIntentStore:
    """Single-instance in-memory intent store. Swap for Redis by implementing IntentStore."""

    def __init__(self, ttl: float = INTENT_TTL_SECONDS) -> None:
        self._store: Dict[str, SyncIntentDocument] = {}
        self._ttl = ttl

    def put(self, intent: SyncIntentDocument) -> None:
        self._store[intent.intent_id] = intent

    def get(self, intent_id: str) -> Optional[SyncIntentDocument]:
        intent = self._store.get(intent_id)
        if intent is None:
            return None
        # Lazy expiry for PENDING intents — persist the status change
        if intent.status == "PENDING" and time.time() > intent.expires_at:
            intent.status = "EXPIRED"
            self._store[intent_id] = intent
        return intent

    def list_recent(self, resource_type: str, limit: int = 20) -> List[SyncIntentDocument]:
        all_intents = [i for i in self._store.values() if i.resource_type == resource_type]
        all_intents.sort(key=lambda x: x.created_at, reverse=True)
        return all_intents[:limit]

    def cleanup_expired(self) -> int:
        now = time.time()
        to_remove = [
            iid for iid, intent in self._store.items()
            if (intent.status in ("PENDING", "EXPIRED") and now > intent.expires_at)
            or (intent.status == "EXECUTED" and now - intent.created_at > 7 * 24 * 3600)
        ]
        for iid in to_remove:
            del self._store[iid]
        return len(to_remove)


intent_store: MemoryIntentStore = MemoryIntentStore()
INTENT_STORE: MemoryIntentStore = intent_store
