"""
Dashboard de Cibersegurança — Backend FastAPI
Fase 2 do projeto CET — consome as APIs do Wazuh e serve dados prontos
para o frontend HTML/CSS.

Correr localmente:
    uvicorn main:app --reload --port 8000

Depois abrir frontend/index.html no browser (ou servir via qualquer
servidor estático simples).
"""

import os
from collections import Counter
from datetime import datetime

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from ai_client import AIHubMixClient
from event_catalog import classify_alert
from wazuh_client import WazuhIndexerClient, WazuhManagerClient

load_dotenv()

WAZUH_MANAGER_URL = os.getenv("WAZUH_MANAGER_URL", "https://localhost:55000")
WAZUH_MANAGER_USER = os.getenv("WAZUH_MANAGER_USER", "wazuh-wui")
WAZUH_MANAGER_PASSWORD = os.getenv("WAZUH_MANAGER_PASSWORD", "")

WAZUH_INDEXER_URL = os.getenv("WAZUH_INDEXER_URL", "https://localhost:9200")
WAZUH_INDEXER_USER = os.getenv("WAZUH_INDEXER_USER", "admin")
WAZUH_INDEXER_PASSWORD = os.getenv("WAZUH_INDEXER_PASSWORD", "")

AIHUBMIX_API_KEY = os.getenv("AIHUBMIX_API_KEY", "")
AIHUBMIX_MODEL = os.getenv("AIHUBMIX_MODEL", "auto")

app = FastAPI(
    title="Dashboard Cibersegurança — CET",
    description="API que liga ao Wazuh e expõe dados prontos para o dashboard",
    version="2.0.0",
)

# Em desenvolvimento local o frontend (ficheiro estático) corre numa origem
# diferente do backend, por isso liberamos CORS. Em produção, restringir
# allow_origins ao domínio real do frontend.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)

manager_client = WazuhManagerClient(
    WAZUH_MANAGER_URL, WAZUH_MANAGER_USER, WAZUH_MANAGER_PASSWORD
)
indexer_client = WazuhIndexerClient(
    WAZUH_INDEXER_URL, WAZUH_INDEXER_USER, WAZUH_INDEXER_PASSWORD
)

# Só é criado se a chave estiver configurada — /api/alerts/explain devolve
# 503 em vez de rebentar quando a funcionalidade não está ligada.
ai_client = AIHubMixClient(AIHUBMIX_API_KEY, AIHUBMIX_MODEL) if AIHUBMIX_API_KEY else None


class EnrichedAlert(BaseModel):
    """Mesma forma que o objeto devolvido por _enrich_alert() / GET /api/alerts."""

    timestamp: str | None = None
    agent_name: str | None = None
    agent_ip: str | None = None
    rule_id: str | None = None
    rule_description: str | None = None
    wazuh_level: int | None = None
    windows_event_id: int | None = None
    friendly_name: str | None = None
    severity: str | None = None
    recommendation: str | None = None
    full_log: str | None = None


def _extract_windows_event_id(alert: dict) -> int | None:
    """
    O Wazuh guarda o Event ID original do Windows dentro de data.win.system.eventID.
    Nem todos os alertas vêm de logs Windows, por isso tratamos a ausência
    do campo com normalidade.
    """
    try:
        raw = alert.get("data", {}).get("win", {}).get("system", {}).get("eventID")
        return int(raw) if raw is not None else None
    except (ValueError, TypeError):
        return None


def _enrich_alert(alert: dict) -> dict:
    """Junta a um alerta cru do Wazuh a nossa camada de classificação (Fase 1)."""
    win_event_id = _extract_windows_event_id(alert)
    classification = classify_alert(win_event_id)

    return {
        "timestamp": alert.get("@timestamp"),
        "agent_name": alert.get("agent", {}).get("name", "Unknown"),
        "agent_ip": alert.get("agent", {}).get("ip", "-"),
        "rule_id": alert.get("rule", {}).get("id"),
        "rule_description": alert.get("rule", {}).get("description"),
        "wazuh_level": alert.get("rule", {}).get("level"),
        "windows_event_id": win_event_id,
        "friendly_name": classification["friendly_name"],
        "severity": classification["severity"],
        "recommendation": classification["recommendation"],
        "full_log": alert.get("full_log", ""),
    }


@app.get("/api/health")
async def health():
    """Confirma que o backend está de pé (não testa ligação ao Wazuh)."""
    return {"status": "ok", "timestamp": datetime.utcnow().isoformat()}


@app.get("/api/agents")
async def get_agents():
    """Lista de agentes Wazuh e o seu estado atual."""
    try:
        agents = await manager_client.get_agents()
        summary = await manager_client.get_agents_summary()
        return {
            "agents": [
                {
                    "id": a.get("id"),
                    "name": a.get("name"),
                    "ip": a.get("ip"),
                    "status": a.get("status"),
                    "os": a.get("os", {}).get("name", "Unknown"),
                    "last_keep_alive": a.get("lastKeepAlive"),
                }
                for a in agents
            ],
            "summary": summary,
        }
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Erro ao contactar Wazuh Manager: {e}")


@app.get("/api/alerts")
async def get_alerts(
    hours: int = Query(24, ge=1, le=168, description="Janela temporal em horas"),
    min_level: int = Query(0, ge=0, le=16, description="Nível mínimo de severidade Wazuh"),
    agent_name: str | None = Query(None, description="Filtrar por nome de agente"),
    severity: str | None = Query(None, description="Filtrar por severidade classificada (critical/high/medium/low)"),
):
    """
    Alertas recentes, já enriquecidos com a classificação de Event ID
    (nome amigável, severidade, recomendação).
    """
    try:
        raw_alerts = await indexer_client.get_recent_alerts(
            hours=hours, min_level=min_level, agent_name=agent_name
        )
        enriched = [_enrich_alert(a) for a in raw_alerts]

        if severity:
            enriched = [a for a in enriched if a["severity"] == severity]

        return {"total": len(enriched), "alerts": enriched}
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Erro ao contactar Wazuh Indexer: {e}")


@app.get("/api/stats")
async def get_stats(hours: int = Query(24, ge=1, le=168)):
    """
    Estatísticas agregadas para os KPIs do dashboard:
    total de alertas, contagem por severidade classificada, top eventos.
    """
    try:
        raw_alerts = await indexer_client.get_recent_alerts(hours=hours, size=500)
        enriched = [_enrich_alert(a) for a in raw_alerts]

        severity_counts = Counter(a["severity"] for a in enriched)
        event_counts = Counter(
            (a["windows_event_id"], a["friendly_name"])
            for a in enriched
            if a["windows_event_id"] is not None
        )
        agent_counts = Counter(a["agent_name"] for a in enriched)

        top_events = [
            {"event_id": eid, "name": name, "count": count}
            for (eid, name), count in event_counts.most_common(10)
        ]

        return {
            "window_hours": hours,
            "total_alerts": len(enriched),
            "by_severity": dict(severity_counts),
            "top_events": top_events,
            "by_agent": dict(agent_counts),
        }
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Erro ao contactar Wazuh Indexer: {e}")


@app.get("/api/brute-force")
async def detect_brute_force(
    hours: int = Query(24, ge=1, le=168),
    threshold: int = Query(5, ge=1, description="Nº mínimo de falhas para gerar alerta"),
):
    """
    Deteção de força bruta: agrupa Event ID 4625 (Failed Logon) por
    utilizador-alvo e assinala quem excedeu o threshold.
    Mesma lógica do log_analyzer_real.py, aplicada aqui a dados ao vivo.
    """
    try:
        raw_alerts = await indexer_client.get_recent_alerts(hours=hours, size=1000)

        failed_logons: dict[str, list[dict]] = {}
        for alert in raw_alerts:
            win_id = _extract_windows_event_id(alert)
            if win_id == 4625:
                target_user = (
                    alert.get("data", {}).get("win", {}).get("eventdata", {}).get("targetUserName", "Unknown")
                )
                failed_logons.setdefault(target_user, []).append(alert)

        suspects = [
            {
                "user": user,
                "failed_attempts": len(attempts),
                "last_attempt": attempts[0].get("@timestamp"),
                "source_agent": attempts[0].get("agent", {}).get("name"),
            }
            for user, attempts in failed_logons.items()
            if len(attempts) >= threshold
        ]

        return {"window_hours": hours, "threshold": threshold, "suspects": suspects}
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Erro ao contactar Wazuh Indexer: {e}")


@app.post("/api/alerts/explain")
async def explain_alert(alert: EnrichedAlert):
    """
    Gera, via AIhubmix, uma explicação mais rica em PT-PT para um alerta já
    enriquecido (o mesmo objeto devolvido por GET /api/alerts). Complementa,
    não substitui, a recomendação estática do event_catalog.py.
    """
    if ai_client is None:
        raise HTTPException(status_code=503, detail="AIHUBMIX_API_KEY não configurada no backend.")
    try:
        explanation = await ai_client.explain_alert(alert.model_dump())
        return {"explanation": explanation}
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Erro ao contactar a AIhubmix: {e}")
