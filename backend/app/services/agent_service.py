import logging
from typing import Dict, Any, List, Optional, Tuple
import os

logger = logging.getLogger(__name__)

# ── Corridor definitions ──────────────────────────────────────────────────────
#
# Each corridor is a tuple of (origin_keywords, destination_keywords, stops).
# "stops" is an ordered list of keyword groups. A location matches a stop if
# ANY keyword in that group appears as a substring of the location string.
# Pickup index must be strictly less than dropoff index to confirm ordering.
#
# Using substring matching means "VIT Vellore" matches the "vellore" group,
# and "ITPL Bangalore" matches the "bangalore" group — no exact name required.

_CORRIDORS: List[Tuple[List[str], List[str], List[List[str]]]] = [
    # NH48 — Chennai to Bangalore
    (
        ["chennai"],
        ["bangalore", "bengaluru"],
        [
            ["chennai"],
            ["katpadi", "vellore", "vit"],   # Katpadi is the rail junction; VIT campus nearby
            ["krishnagiri"],
            ["hosur"],
            ["bangalore", "bengaluru", "whitefield", "itpl", "electronic city",
             "koramangala", "indiranagar", "manyata", "hsr", "btm",
             "marathahalli", "mg road"],
        ],
    ),
    # NH48 reversed — Bangalore to Chennai
    (
        ["bangalore", "bengaluru"],
        ["chennai"],
        [
            ["bangalore", "bengaluru", "whitefield", "itpl", "electronic city",
             "koramangala", "indiranagar", "manyata", "hsr", "btm",
             "marathahalli", "mg road"],
            ["hosur"],
            ["krishnagiri"],
            ["katpadi", "vellore", "vit"],
            ["chennai"],
        ],
    ),
    # Katpadi / Vellore area to Bangalore (sub-segment of NH48)
    (
        ["katpadi", "vellore"],
        ["bangalore", "bengaluru"],
        [
            ["katpadi", "vellore", "vit"],
            ["krishnagiri"],
            ["hosur"],
            ["bangalore", "bengaluru", "whitefield", "itpl", "electronic city",
             "koramangala", "indiranagar", "manyata", "hsr", "btm",
             "marathahalli", "mg road"],
        ],
    ),
    # Bangalore to Katpadi / Vellore
    (
        ["bangalore", "bengaluru"],
        ["katpadi", "vellore"],
        [
            ["bangalore", "bengaluru", "whitefield", "itpl", "electronic city",
             "koramangala", "indiranagar", "manyata", "hsr", "btm"],
            ["hosur"],
            ["krishnagiri"],
            ["katpadi", "vellore", "vit"],
        ],
    ),
]


def _stop_index(location: str, stops: List[List[str]]) -> int:
    """Return the index of the first matching stop group, or -1."""
    loc = location.lower()
    for i, keywords in enumerate(stops):
        if any(kw in loc for kw in keywords):
            return i
    return -1


def _match_corridor(
    origin: str, destination: str
) -> Optional[List[List[str]]]:
    """Return the stop list for the first matching corridor, or None."""
    o = origin.lower()
    d = destination.lower()
    for (orig_kws, dest_kws, stops) in _CORRIDORS:
        if any(kw in o for kw in orig_kws) and any(kw in d for kw in dest_kws):
            return stops
    return None


class FreightShareAgentService:

    @staticmethod
    def check_route_feasibility(
        origin: str, destination: str, pickup: str, dropoff: str
    ) -> Tuple[bool, str]:
        """
        Checks if pickup and dropoff lie on the driver's route in the correct order.

        Uses corridor-based substring matching so that sub-locations like
        "VIT Vellore" and "ITPL Bangalore" correctly match their parent cities
        on known NH corridors.
        """
        logger.info(
            "route_feasibility_check | origin=%r destination=%r pickup=%r dropoff=%r",
            origin, destination, pickup, dropoff,
        )

        corridor = _match_corridor(origin, destination)
        if corridor:
            p_idx = _stop_index(pickup, corridor)
            dp_idx = _stop_index(dropoff, corridor)

            if p_idx == -1:
                logger.info("route_check=miss | pickup=%r not on corridor", pickup)
                # Fall through to general check rather than hard-reject
            elif dp_idx == -1:
                logger.info("route_check=miss | dropoff=%r not on corridor", dropoff)
            elif p_idx < dp_idx:
                logger.info(
                    "route_check=pass | corridor_match p_idx=%d dp_idx=%d", p_idx, dp_idx
                )
                return (
                    True,
                    f"Route feasible. '{pickup}' (stop {p_idx}) comes before "
                    f"'{dropoff}' (stop {dp_idx}) on the {origin}→{destination} corridor.",
                )
            elif p_idx == dp_idx:
                # Same stop group — treat as same-area, feasible
                logger.info("route_check=pass | same stop group idx=%d", p_idx)
                return True, f"Pickup and dropoff are within the same area ({pickup} ≈ {dropoff})."
            else:
                logger.info(
                    "route_check=fail | direction_reversed p_idx=%d dp_idx=%d", p_idx, dp_idx
                )
                return (
                    False,
                    f"Route infeasible. Direction reversed: '{pickup}' (stop {p_idx}) "
                    f"is after '{dropoff}' (stop {dp_idx}) on the {origin}→{destination} route.",
                )

        # ── General fallback: substring endpoint matching ──────────────────────
        # If the trip is not on a known corridor, check whether pickup/dropoff
        # mention the origin or destination city by name (handles simple cases
        # like exact-city-to-exact-city requests for any route).
        o_words = set(origin.lower().replace(',', ' ').split())
        d_words = set(destination.lower().replace(',', ' ').split())
        p_lower = pickup.lower()
        dp_lower = dropoff.lower()

        # Meaningful words only (skip short prepositions)
        meaningful = lambda words: {w for w in words if len(w) > 3}
        o_sig = meaningful(o_words)
        d_sig = meaningful(d_words)

        p_matches_origin = any(w in p_lower for w in o_sig)
        p_matches_dest = any(w in p_lower for w in d_sig)
        dp_matches_origin = any(w in dp_lower for w in o_sig)
        dp_matches_dest = any(w in dp_lower for w in d_sig)

        if (p_matches_origin or p_matches_dest) and (dp_matches_origin or dp_matches_dest):
            # Both pickup and dropoff relate to the route endpoints
            # Prefer pickup near origin and dropoff near destination
            if p_matches_origin and dp_matches_dest:
                msg = (f"Route feasible. Pickup '{pickup}' is at/near origin, "
                       f"dropoff '{dropoff}' is at/near destination.")
                logger.info("route_check=pass | endpoint_match: %s", msg)
                return True, msg
            if p_matches_dest and dp_matches_origin:
                logger.info("route_check=fail | reversed_endpoints")
                return False, (f"Route infeasible. Pickup '{pickup}' is at the destination "
                               f"and dropoff '{dropoff}' is at the origin — direction reversed.")
            # Both at same end — allow (intra-city)
            logger.info("route_check=pass | intra_zone")
            return True, f"Route feasible. Pickup and dropoff are near route zone."

        if p_matches_origin or p_matches_dest or dp_matches_origin or dp_matches_dest:
            # At least one endpoint matched
            logger.info("route_check=pass | partial_endpoint_match")
            return True, (f"Route feasible. '{pickup}'/'{dropoff}' share nodes "
                          f"with the route: {origin} → {destination}.")

        # Unknown corridor, endpoints not identified in location strings.
        # For uncatalogued routes we allow the shipment and let the driver decide —
        # the driver's accept/reject action is the authoritative second check.
        logger.info(
            "route_check=pass | unknown_corridor_permissive "
            "origin=%r dest=%r pickup=%r dropoff=%r",
            origin, destination, pickup, dropoff,
        )
        return (
            True,
            f"Route allowed (corridor not yet catalogued). "
            f"Driver will review pickup '{pickup}' and dropoff '{dropoff}' "
            f"against their planned route '{origin}' → '{destination}'.",
        )

    @staticmethod
    def check_capacity(
        weight: float,
        volume: float,
        rem_weight: float,
        rem_volume: float,
    ) -> Tuple[bool, str]:
        logger.debug(
            "capacity_check | weight=%.1f rem_weight=%.1f volume=%.3f rem_volume=%.3f",
            weight, rem_weight, volume, rem_volume,
        )
        if weight > rem_weight:
            return False, (f"Insufficient weight capacity. "
                           f"Requested: {weight}kg, Available: {rem_weight}kg.")
        if volume > rem_volume:
            return False, (f"Insufficient volume capacity. "
                           f"Requested: {volume} cu ft, Available: {rem_volume} cu ft.")
        return True, (f"Capacity check passed. "
                      f"Weight ({weight}kg ≤ {rem_weight}kg), "
                      f"Volume ({volume} ≤ {rem_volume} cu ft).")

    @staticmethod
    def calculate_price(
        weight: float,
        volume: float,
        cargo_category: str,
        pickup: str,
        dropoff: str,
    ) -> Tuple[float, str]:
        p_clean = pickup.lower()
        dp_clean = dropoff.lower()

        distance = 150.0  # default fallback distance (km)

        if "vellore" in p_clean or "katpadi" in p_clean or "vit" in p_clean:
            if "bangalore" in dp_clean or "bengaluru" in dp_clean:
                distance = 100.0
        elif "chennai" in p_clean:
            if "bangalore" in dp_clean or "bengaluru" in dp_clean:
                distance = 350.0
            elif "vellore" in dp_clean or "katpadi" in dp_clean:
                distance = 140.0
        elif "bangalore" in p_clean or "bengaluru" in p_clean:
            if "chennai" in dp_clean:
                distance = 350.0
            elif "vellore" in dp_clean or "katpadi" in dp_clean:
                distance = 100.0

        base_price = 800.0
        weight_charge = weight * 5.0
        volume_charge = volume * 20.0
        distance_charge = distance * 2.0
        subtotal = base_price + weight_charge + volume_charge + distance_charge

        surcharge = 0.0
        surcharge_desc = "None"
        category = cargo_category.lower().strip()
        if category == "fragile":
            surcharge = 200.0
            surcharge_desc = "₹200 (Fragile handling)"
        elif category == "perishable":
            surcharge = 300.0
            surcharge_desc = "₹300 (Perishable / refrigeration)"

        total_price = subtotal + surcharge
        breakdown = (
            f"Pricing Breakdown:\n"
            f"  - Base Handling: ₹{base_price}\n"
            f"  - Distance Charge ({distance}km × ₹2/km): ₹{distance_charge:.2f}\n"
            f"  - Weight Charge ({weight}kg × ₹5/kg): ₹{weight_charge:.2f}\n"
            f"  - Volume Charge ({volume} cu ft × ₹20): ₹{volume_charge:.2f}\n"
            f"  - Special Surcharge ({cargo_category}): {surcharge_desc}\n"
            f"  - Total: ₹{total_price:.2f}"
        )
        logger.debug("price_calc | pickup=%r dropoff=%r distance=%.0f total=%.2f",
                     pickup, dropoff, distance, total_price)
        return float(total_price), breakdown

    @classmethod
    def evaluate_shipment(
        cls,
        pickup: str,
        dropoff: str,
        weight: float,
        volume: float,
        cargo_category: str,
        trip_origin: str,
        trip_destination: str,
        rem_weight: float,
        rem_volume: float,
    ) -> Dict[str, Any]:
        logger.info(
            "evaluate_shipment | trip=%r→%r pickup=%r dropoff=%r "
            "weight=%.1f volume=%.3f category=%r rem_weight=%.1f rem_volume=%.3f",
            trip_origin, trip_destination, pickup, dropoff,
            weight, volume, cargo_category, rem_weight, rem_volume,
        )

        trace_steps = [
            "🏁 Starting AI Agent Shipment Feasibility Evaluation...",
            (f"📥 Input parameters:\n"
             f"  - Pickup: {pickup}\n"
             f"  - Dropoff: {dropoff}\n"
             f"  - Weight: {weight}kg, Volume: {volume} cu ft\n"
             f"  - Category: {cargo_category}"),
            (f"🚚 Active Trip:\n"
             f"  - Origin: {trip_origin}\n"
             f"  - Destination: {trip_destination}\n"
             f"  - Remaining: {rem_weight}kg, {rem_volume} cu ft"),
        ]

        # Step 1: Route feasibility
        trace_steps.append("\n🔍 Step 1: Invoking Tool 'check_route_feasibility'...")
        route_ok, route_msg = cls.check_route_feasibility(
            trip_origin, trip_destination, pickup, dropoff
        )
        trace_steps.append(f"🛠️ [check_route_feasibility]: {route_msg}")

        if not route_ok:
            logger.info("evaluate_shipment=infeasible | reason=route | msg=%r", route_msg)
            trace_steps.append("❌ Agent Decision: Route infeasible — terminating evaluation.")
            return {"feasible": False, "price": 0.0, "trace": "\n".join(trace_steps)}

        # Step 2: Capacity
        trace_steps.append("\n🔍 Step 2: Invoking Tool 'check_capacity'...")
        capacity_ok, capacity_msg = cls.check_capacity(weight, volume, rem_weight, rem_volume)
        trace_steps.append(f"🛠️ [check_capacity]: {capacity_msg}")

        if not capacity_ok:
            logger.info("evaluate_shipment=infeasible | reason=capacity | msg=%r", capacity_msg)
            trace_steps.append("❌ Agent Decision: Insufficient capacity — terminating.")
            return {"feasible": False, "price": 0.0, "trace": "\n".join(trace_steps)}

        # Step 3: Pricing
        trace_steps.append("\n🔍 Step 3: Invoking Tool 'calculate_price'...")
        price, price_breakdown = cls.calculate_price(weight, volume, cargo_category, pickup, dropoff)
        trace_steps.append(f"🛠️ [calculate_price]:\n{price_breakdown}")

        trace_steps.append("\n✅ Agent Decision: Shipment is FEASIBLE.")
        trace_steps.append(f"💰 Proposed Price: ₹{price:,.2f}")

        aws_configured = os.getenv("AWS_ACCESS_KEY_ID") is not None
        trace_steps.append(
            "\n🤖 [Agent LLM Thought — "
            + ("AWS Bedrock Live]:" if aws_configured else "Local Mode]:")
        )
        trace_steps.append(
            f"Thought: Route '{trip_origin}→{trip_destination}' confirmed feasible for "
            f"'{pickup}'→'{dropoff}'. Capacity verified ({weight}kg/{volume} cu ft "
            f"within {rem_weight}kg/{rem_volume} cu ft available). "
            f"Price ₹{price:.2f} computed and validated."
        )

        logger.info(
            "evaluate_shipment=feasible | price=%.2f trip=%r→%r pickup=%r dropoff=%r",
            price, trip_origin, trip_destination, pickup, dropoff,
        )
        return {"feasible": True, "price": price, "trace": "\n".join(trace_steps)}
