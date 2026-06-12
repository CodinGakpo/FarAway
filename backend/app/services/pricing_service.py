from dataclasses import dataclass, field
from typing import Any
import math

@dataclass
class PricingParams:
    base_rate_per_km: float
    rate_per_kg: float
    rate_per_m3: float
    goods_type_multipliers: dict[str, float]
    detour_surcharge_per_km: float
    utilization_surge_threshold: float
    utilization_surge_multiplier: float
    min_driver_rate_per_km: float
    platform_fee_pct: float
    declared_value_pct: float

@dataclass
class PriceBreakdown:
    base_fare: float
    weight_charge: float
    volume_charge: float
    detour_surcharge: float
    declared_value_insurance: float
    goods_type_multiplier: float
    utilization_surge: float
    platform_fee: float
    total: float
    profitability_floor: float
    is_floor_applied: bool

@dataclass
class PricingResult:
    final_price: float
    breakdown: PriceBreakdown
    is_profitable: bool


class PricingService:
    def __init__(self, db):
        self.db = db

    async def load_params(self, city: str | None = None) -> PricingParams:
        async with self.db.acquire() as conn:
            row = await conn.fetchrow("""
                SELECT * FROM pricing_parameters
                WHERE is_active = TRUE
                  AND (city = $1 OR city IS NULL)
                  AND (effective_until IS NULL OR effective_until > NOW())
                ORDER BY (city IS NOT NULL) DESC, effective_from DESC
                LIMIT 1
            """, city)
        if not row:
            raise ValueError("No active pricing parameters found")
        import json
        return PricingParams(
            base_rate_per_km=float(row['base_rate_per_km']),
            rate_per_kg=float(row['rate_per_kg']),
            rate_per_m3=float(row['rate_per_m3']),
            goods_type_multipliers=json.loads(row['goods_type_multipliers']),
            detour_surcharge_per_km=float(row['detour_surcharge_per_km']),
            utilization_surge_threshold=float(row['utilization_surge_threshold']),
            utilization_surge_multiplier=float(row['utilization_surge_multiplier']),
            min_driver_rate_per_km=float(row['min_driver_rate_per_km']),
            platform_fee_pct=float(row['platform_fee_pct']),
            declared_value_pct=float(row['declared_value_pct']),
        )

    def calculate(
        self,
        params: PricingParams,
        shipment_distance_km: float,
        weight_kg: float,
        volume_m3: float,
        goods_type: str,
        declared_value: float,
        detour_km: float,
        utilization_pct: float,
    ) -> PricingResult:
        """Pure function — no DB calls, fully testable."""

        goods_mult = params.goods_type_multipliers.get(goods_type, 1.0)

        base_fare            = shipment_distance_km * params.base_rate_per_km
        weight_charge        = weight_kg * params.rate_per_kg
        volume_charge        = volume_m3 * params.rate_per_m3
        detour_surcharge     = detour_km * params.detour_surcharge_per_km
        declared_value_ins   = declared_value * params.declared_value_pct

        subtotal = (base_fare + weight_charge + volume_charge
                    + detour_surcharge + declared_value_ins) * goods_mult

        utilization_surge = 0.0
        if utilization_pct > params.utilization_surge_threshold:
            utilization_surge = subtotal * (params.utilization_surge_multiplier - 1.0)

        subtotal_with_surge = subtotal + utilization_surge
        platform_fee = subtotal_with_surge * params.platform_fee_pct
        computed_price = subtotal_with_surge + platform_fee

        # Profitability floor: driver must earn min_rate for every km driven on this shipment's behalf
        total_km_for_shipment = shipment_distance_km + detour_km
        floor = total_km_for_shipment * params.min_driver_rate_per_km

        is_floor_applied = computed_price < floor
        final_price = max(computed_price, floor)

        breakdown = PriceBreakdown(
            base_fare=round(base_fare, 2),
            weight_charge=round(weight_charge, 2),
            volume_charge=round(volume_charge, 2),
            detour_surcharge=round(detour_surcharge, 2),
            declared_value_insurance=round(declared_value_ins, 2),
            goods_type_multiplier=goods_mult,
            utilization_surge=round(utilization_surge, 2),
            platform_fee=round(platform_fee, 2),
            total=round(final_price, 2),
            profitability_floor=round(floor, 2),
            is_floor_applied=is_floor_applied,
        )

        return PricingResult(
            final_price=round(final_price, 2),
            breakdown=breakdown,
            is_profitable=final_price >= floor,
        )
