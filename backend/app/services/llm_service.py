import httpx
import logging
from typing import Dict, Any
from app.config import ANTHROPIC_API_KEY, OPENAI_API_KEY

logger = logging.getLogger(__name__)

class LLMService:
    @classmethod
    def generate_match_explanation(
        cls, 
        load_details: Dict[str, Any], 
        carrier_details: Dict[str, Any], 
        is_train: bool = False
    ) -> str:
        """
        Calls Claude (Anthropic) or GPT-4o mini (OpenAI) to explain why a match was recommended.
        Falls back to a structured template explanation if no API keys are configured.
        """
        carrier_type = "Train" if is_train else "Truck"
        
        prompt = (
            f"Explain why this logistics match is recommended in a concise, professional paragraph "
            f"suitable for a logistics shipper dashboard. Do not use markdown headers, start with direct explanation.\n"
            f"Load details: Pickup: {load_details['pickup_name']}, Dropoff: {load_details['dropoff_name']}, "
            f"Weight: {load_details['weight']}kg, Volume: {load_details['volume']} cu ft.\n"
            f"{carrier_type} details: Route: {carrier_details['origin']} -> {carrier_details['destination']}, "
            f"Departure: {carrier_details['departure_time']}, Max Capacity: {carrier_details['max_weight']}kg.\n"
        )

        # 1. Try Claude (Anthropic API)
        if ANTHROPIC_API_KEY:
            try:
                headers = {
                    "x-api-key": ANTHROPIC_API_KEY,
                    "anthropic-version": "2023-06-01",
                    "content-type": "application/json"
                }
                body = {
                    "model": "claude-3-haiku-20240307",
                    "max_tokens": 150,
                    "messages": [
                        {"role": "user", "content": prompt}
                    ]
                }
                response = httpx.post("https://api.anthropic.com/v1/messages", json=body, headers=headers, timeout=5.0)
                if response.status_code == 200:
                    result = response.json()
                    return result["content"][0]["text"].strip()
            except Exception as e:
                logger.error(f"Claude API failed: {str(e)}")

        # 2. Try GPT-4o mini (OpenAI API)
        if OPENAI_API_KEY:
            try:
                headers = {
                    "Authorization": f"Bearer {OPENAI_API_KEY}",
                    "Content-Type": "application/json"
                }
                body = {
                    "model": "gpt-4o-mini",
                    "max_tokens": 150,
                    "messages": [
                        {"role": "system", "content": "You are a helpful logistics coordinator assistant."},
                        {"role": "user", "content": prompt}
                    ],
                    "temperature": 0.7
                }
                response = httpx.post("https://api.openai.com/v1/chat/completions", json=body, headers=headers, timeout=5.0)
                if response.status_code == 200:
                    result = response.json()
                    return result["choices"][0]["message"]["content"].strip()
            except Exception as e:
                logger.error(f"OpenAI API failed: {str(e)}")

        # 3. Rich template-based fallback
        savings = "35%" if is_train else "15%"
        co2_reduction = "80% (Eco-friendly Rail Transit)" if is_train else "12% (Empty Backhaul Sharing)"
        
        explanation = (
            f"Recommended Match: {carrier_type} route ({carrier_details['origin']} ➡️ {carrier_details['destination']}) "
            f"offers an excellent fit for your load from {load_details['pickup_name']} to {load_details['dropoff_name']}. "
            f"The carrier's spatial path directly aligns with your corridor, and they have sufficient remaining capacity "
            f"(requested: {load_details['weight']}kg, available: {carrier_details['max_weight']}kg). "
            f"Selecting this shared capacity will reduce transit cost by approximately {savings} and lower carbon footprint "
            f"by {co2_reduction} compared to booking an independent dedicated truck."
        )
        return explanation
