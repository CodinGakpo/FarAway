-- 004_pricing_seed.sql
INSERT INTO pricing_parameters (
    scope,
    base_rate_per_km,
    rate_per_kg,
    rate_per_m3,
    goods_type_multipliers,
    detour_surcharge_per_km,
    utilization_surge_threshold,
    utilization_surge_multiplier,
    min_driver_rate_per_km,
    platform_fee_pct,
    declared_value_pct,
    is_active
) VALUES (
    'global',
    20.0,
    5.0,
    200.0,
    '{"general": 1.0, "fragile": 1.4, "perishable": 1.6, "hazardous": 2.0}'::jsonb,
    12.0,
    0.75,
    1.25,
    15.0,
    0.10,
    0.005,
    TRUE
);
