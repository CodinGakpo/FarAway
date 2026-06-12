import asyncpg
from app.config import DATABASE_URL

class CapacityConflictError(Exception):
    """Raised when optimistic concurrency check fails during capacity reservation."""
    pass

class RecordNotFoundError(Exception):
    pass

def map_db_error(exc: Exception) -> Exception:
    if isinstance(exc, asyncpg.UniqueViolationError):
        return ValueError(f"Duplicate record: {exc.detail}")
    if isinstance(exc, asyncpg.ForeignKeyViolationError):
        return ValueError(f"Referenced record not found: {exc.detail}")
    return exc

class Database:
    pool: asyncpg.Pool | None = None

    async def connect(self):
        self.pool = await asyncpg.create_pool(
            dsn=DATABASE_URL,
            min_size=2,
            max_size=10,
            command_timeout=30,
            server_settings={"application_name": "freight-backend"},
        )

    async def disconnect(self):
        if self.pool:
            await self.pool.close()

    def acquire(self):
        """Context manager for getting a connection from the pool."""
        if not self.pool:
            raise RuntimeError("Database pool not initialized.")
        return self.pool.acquire()

    def transaction(self):
        """Context manager for a transaction block."""
        if not self.pool:
            raise RuntimeError("Database pool not initialized.")
        return self.pool.acquire()  # used with conn.transaction()
