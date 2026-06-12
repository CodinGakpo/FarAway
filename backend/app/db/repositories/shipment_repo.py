from dataclasses import dataclass
from uuid import UUID
from typing import Optional, List
import asyncpg
from datetime import datetime

class ShipmentRepository:
    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn

    async def get_by_id(self, shipment_id: UUID):
        row = await self.conn.fetchrow(
            "SELECT * FROM shipments WHERE id = $1", shipment_id
        )
        return dict(row) if row else None
