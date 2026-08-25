"""
Cliente para a API da AIhubmix (gateway OpenAI-compatible para +500 modelos:
OpenAI, Claude, Gemini, DeepSeek, Qwen, etc.).

Usado para gerar uma explicação mais rica, em PT-PT, de um alerta já
enriquecido (ver _enrich_alert em main.py) — complementa, não substitui, a
recomendação estática do event_catalog.py.

Docs: https://docs.aihubmix.com
"""

import httpx

AIHUBMIX_BASE_URL = "https://api.aihubmix.com/v1"


class AIHubMixClient:
    def __init__(self, api_key: str, model: str = "auto"):
        self.api_key = api_key
        self.model = model

    async def explain_alert(self, alert: dict) -> str:
        """Pede ao modelo uma explicação em PT-PT para um alerta já enriquecido."""
        prompt = _build_prompt(alert)

        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{AIHUBMIX_BASE_URL}/chat/completions",
                headers={"Authorization": f"Bearer {self.api_key}"},
                json={
                    "model": self.model,
                    "messages": [
                        {
                            "role": "system",
                            "content": (
                                "És um analista SOC sénior a explicar alertas de segurança "
                                "a um estudante de cibersegurança. Respondes sempre em "
                                "português de Portugal, de forma clara e objetiva."
                            ),
                        },
                        {"role": "user", "content": prompt},
                    ],
                    "temperature": 0.3,
                    "max_tokens": 400,
                },
                timeout=30,
            )
            if response.is_error:
                raise httpx.HTTPStatusError(
                    f"{response.status_code} {response.reason_phrase}: {response.text}",
                    request=response.request,
                    response=response,
                )
            data = response.json()
            return data["choices"][0]["message"]["content"].strip()


def _build_prompt(alert: dict) -> str:
    return (
        "Explica este alerta de segurança Windows em 3-4 frases: o que "
        "aconteceu, porque é relevante, e o que fazer a seguir (para além "
        "da recomendação já dada abaixo, sem a repetir).\n\n"
        f"Evento: {alert.get('friendly_name')} (Event ID {alert.get('windows_event_id')})\n"
        f"Severidade: {alert.get('severity')}\n"
        f"Agente: {alert.get('agent_name')} ({alert.get('agent_ip')})\n"
        f"Data: {alert.get('timestamp')}\n"
        f"Descrição da regra Wazuh: {alert.get('rule_description')}\n"
        f"Log original: {alert.get('full_log')}\n"
        f"Recomendação já existente: {alert.get('recommendation')}\n"
    )
