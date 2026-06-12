from dataclasses import dataclass
from uuid import UUID
from datetime import datetime, timedelta
import asyncpg
from app.db.client import Database, CapacityConflictError
import json

HOLD_DURATION_MINUTES = 10  # Customer has 10 min to complete payment

@dataclass
class CapacityCheckResult:
    available: bool
    remaining_weight_kg: float
    remaining_volume_m3: float
    utilization_pct: float       # 0.0–1.0, used by pricing service
    rejection_reason: str | None = None

@dataclass
class CapacityHoldResult:
    success: bool
    booking_id: UUID | None
    hold_expires_at: datetime | None
    rejection_reason: str | None = None


class CapacityService:
    def __init__(self, db: Database):
        self.db = db

    async def check(
        self, trip_id: UUID, weight_kg: float, volume_m3: float
    ) -> CapacityCheckResult:
        async with self.db.acquire() as conn:
            row = await conn.fetchrow("""
                SELECT
                    t.max_weight_capacity as max_weight_kg,
                    t.max_volume_capacity as max_volume_m3,
                    (t.max_weight_capacity - t.remaining_weight_capacity) as used_weight_kg,
                    (t.max_volume_capacity - t.remaining_volume_capacity) as used_volume_m3
                FROM legacy_trips t
                WHERE t.id = $1::int
            """, int(trip_id))

        if not row:
            return CapacityCheckResult(
                available=False, remaining_weight_kg=0, remaining_volume_m3=0,
                utilization_pct=0, rejection_reason="Trip not found"
            )

        rem_w = row['max_weight_kg'] - row['used_weight_kg']
        rem_v = row['max_volume_m3'] - row['used_volume_m3']
        util = (row['used_weight_kg'] / row['max_weight_kg'] +
                row['used_volume_m3'] / row['max_volume_m3']) / 2.0

        if weight_kg > rem_w:
            return CapacityCheckResult(
                available=False, remaining_weight_kg=rem_w, remaining_volume_m3=rem_v,
                utilization_pct=util,
                rejection_reason=f"Insufficient weight capacity: need {weight_kg}kg, have {rem_w:.1f}kg"
            )
        if volume_m3 > rem_v:
            return CapacityCheckResult(
                available=False, remaining_weight_kg=rem_w, remaining_volume_m3=rem_v,
                utilization_pct=util,
                rejection_reason=f"Insufficient volume: need {volume_m3}m³, have {rem_v:.2f}m³"
            )
        return CapacityCheckResult(
            available=True, remaining_weight_kg=rem_w, remaining_volume_m3=rem_v,
            utilization_pct=util
        )

    async def hold(
        self,
        trip_id: UUID,
        shipment_id: UUID,
        weight_kg: float,
        volume_m3: float,
        price_amount: float,
        price_breakdown: dict,
        detour_km: float,
        detour_min: float,
    ) -> CapacityHoldResult:
        """
        Atomically:
        1. Lock trip_capacity row (SELECT FOR UPDATE)
        2. Re-validate capacity (inside the transaction)
        3. Increment used capacity
        4. Create booking record with status='capacity_held'
        5. Insert audit log entry
        All within a single SERIALIZABLE transaction.
        """
        hold_expires = datetime.utcnow() + timedelta(minutes=HOLD_DURATION_MINUTES)

        async with self.db.acquire() as conn:
            async with conn.transaction(isolation='serializable'):
                # Step 1+2: Lock and re-validate inside transaction
                cap_row = await conn.fetchrow("""
                    SELECT 
                        t.max_weight_capacity as max_weight_kg, 
                        t.max_volume_capacity as max_volume_m3,
                        (t.max_weight_capacity - t.remaining_weight_capacity) as used_weight_kg,
                        (t.max_volume_capacity - t.remaining_volume_capacity) as used_volume_m3,
                        1 as version
                    FROM legacy_trips t
                    WHERE t.id = $1::int
                    FOR UPDATE
                """, int(trip_id))

                if not cap_row:
                    return CapacityHoldResult(success=False, booking_id=None,
                                              hold_expires_at=None,
                                              rejection_reason="Trip not found")

                rem_w = cap_row['max_weight_kg'] - cap_row['used_weight_kg']
                rem_v = cap_row['max_volume_m3'] - cap_row['used_volume_m3']
                if weight_kg > rem_w or volume_m3 > rem_v:
                    return CapacityHoldResult(success=False, booking_id=None,
                                              hold_expires_at=None,
                                              rejection_reason="Capacity no longer available")

                # Step 3: Update capacity
                updated = await conn.execute("""
                    UPDATE legacy_trips
                    SET remaining_weight_capacity = remaining_weight_capacity - $2,
                        remaining_volume_capacity = remaining_volume_capacity - $3
                    WHERE id = $1::int
                """, int(trip_id), weight_kg, volume_m3)

                if updated == "UPDATE 0":
                    raise CapacityConflictError("Concurrent capacity update detected")

                # Step 4: Create booking
                booking_id = await conn.fetchval("""
                    INSERT INTO bookings (
                        trip_id, shipment_id, price_amount, price_breakdown,
                        detour_distance_km, detour_duration_min,
                        status, hold_expires_at, version
                    ) VALUES ($1, $2, $3, $4, $5, $6, 'capacity_held', $7, 0)
                    RETURNING id
                """, trip_id, shipment_id, price_amount,
                    json.dumps(price_breakdown), detour_km, detour_min, hold_expires)

                # Step 5: Audit
                await conn.execute("""
                    INSERT INTO audit_log (entity_type, entity_id, action, payload)
                    VALUES ('booking', $1, 'capacity_held', $2)
                """, booking_id, json.dumps({
                    "trip_id": str(trip_id),
                    "weight_kg": weight_kg,
                    "volume_m3": volume_m3,
                }))

        return CapacityHoldResult(
            success=True, booking_id=booking_id, hold_expires_at=hold_expires
        )

    async def confirm(self, booking_id: UUID) -> bool:
        async with self.db.acquire() as conn:
            async with conn.transaction():
                row = await conn.fetchrow("""
                    SELECT status, hold_expires_at
                    FROM bookings WHERE id = $1 FOR UPDATE
                """, booking_id)
                if not row or row['status'] != 'capacity_held':
                    return False
                if row['hold_expires_at'] < datetime.utcnow():
                    return False  # expired; Celery job should clean this up
                await conn.execute("""
                    UPDATE bookings
                    SET status = 'confirmed', hold_expires_at = NULL, updated_at = NOW()
                    WHERE id = $1
                """, booking_id)
                await conn.execute("""
                    INSERT INTO audit_log (entity_type, entity_id, action)
                    VALUES ('booking', $1, 'confirmed')
                """, booking_id)
        return True

    async def release_hold(self, booking_id: UUID, reason: str = "cancelled") -> bool:
        """Release a held booking and return capacity to the trip."""
        async with self.db.acquire() as conn:
            async with conn.transaction(isolation='serializable'):
                row = await conn.fetchrow("""
                    SELECT b.trip_id, s.weight_kg, s.volume_m3
                    FROM bookings b
                    JOIN shipments s ON s.id = b.shipment_id
                    WHERE b.id = $1 AND b.status IN ('capacity_held', 'confirmed')
                    FOR UPDATE OF b
                """, booking_id)
                if not row:
                    return False
                await conn.execute("""
                    UPDATE bookings SET status = $2, updated_at = NOW() WHERE id = $1
                """, booking_id, reason)
                await conn.execute("""
                    UPDATE legacy_trips
                    SET remaining_weight_capacity = LEAST(max_weight_capacity, remaining_weight_capacity + $2),
                        remaining_volume_capacity  = LEAST(max_volume_capacity, remaining_volume_capacity + $3)
                    WHERE id = $1::int
                """, int(row['trip_id']), row['weight_kg'], row['volume_m3'])
        return True
