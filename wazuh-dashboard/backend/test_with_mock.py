"""
Testa o backend com respostas simuladas do Wazuh (sem precisar do
laboratório real ligado). Útil para validar a lógica antes de teres
o Hyper-V a correr, e para debug se algo correr mal mais tarde.
"""

import asyncio
from unittest.mock import AsyncMock, patch

import event_catalog
import main


MOCK_ALERT_BRUTE_FORCE = {
    "@timestamp": "2026-08-25T08:23:45.000Z",
    "agent": {"name": "WORKSTATION-01", "ip": "192.168.1.100"},
    "rule": {"id": "60204", "description": "Multiple Windows Logon Failures", "level": 10},
    "data": {
        "win": {
            "system": {"eventID": "4625"},
            "eventdata": {"targetUserName": "administrator"},
        }
    },
    "full_log": "Failed logon attempt for administrator",
}

MOCK_ALERT_TASK_CREATED = {
    "@timestamp": "2026-08-25T09:12:00.000Z",
    "agent": {"name": "SERVER-DC01", "ip": "192.168.1.10"},
    "rule": {"id": "92057", "description": "Scheduled task created", "level": 12},
    "data": {"win": {"system": {"eventID": "4698"}}},
    "full_log": "Scheduled task created: SuspiciousTask",
}


def test_classify_alert_known():
    result = event_catalog.classify_alert(4625)
    assert result["friendly_name"] == "Failed Logon"
    assert result["severity"] == "high"
    print("✓ classify_alert(4625) →", result)


def test_classify_alert_unknown():
    result = event_catalog.classify_alert(9999)
    assert result["severity"] == "info"
    print("✓ classify_alert(9999) →", result)


def test_extract_windows_event_id():
    assert main._extract_windows_event_id(MOCK_ALERT_BRUTE_FORCE) == 4625
    assert main._extract_windows_event_id({}) is None
    print("✓ _extract_windows_event_id funciona com e sem dados")


def test_enrich_alert():
    enriched = main._enrich_alert(MOCK_ALERT_BRUTE_FORCE)
    assert enriched["windows_event_id"] == 4625
    assert enriched["severity"] == "high"
    assert enriched["agent_name"] == "WORKSTATION-01"
    print("✓ _enrich_alert →", enriched)


async def test_stats_endpoint_with_mock():
    """Simula a Indexer API a devolver 2 alertas e confirma a agregação."""
    mock_get_recent_alerts = AsyncMock(
        return_value=[MOCK_ALERT_BRUTE_FORCE, MOCK_ALERT_TASK_CREATED]
    )

    with patch.object(main.indexer_client, "get_recent_alerts", mock_get_recent_alerts):
        result = await main.get_stats(hours=24)

    assert result["total_alerts"] == 2
    assert result["by_severity"]["high"] == 2
    print("✓ /api/stats com mock →", result)


async def test_brute_force_endpoint_with_mock():
    """Simula 6 falhas de logon para o mesmo utilizador e confirma deteção."""
    repeated_failures = [MOCK_ALERT_BRUTE_FORCE] * 6
    mock_get_recent_alerts = AsyncMock(return_value=repeated_failures)

    with patch.object(main.indexer_client, "get_recent_alerts", mock_get_recent_alerts):
        result = await main.detect_brute_force(hours=24, threshold=5)

    assert len(result["suspects"]) == 1
    assert result["suspects"][0]["user"] == "administrator"
    assert result["suspects"][0]["failed_attempts"] == 6
    print("✓ /api/brute-force com mock →", result)


def run_all():
    test_classify_alert_known()
    test_classify_alert_unknown()
    test_extract_windows_event_id()
    test_enrich_alert()
    asyncio.run(test_stats_endpoint_with_mock())
    asyncio.run(test_brute_force_endpoint_with_mock())
    print("\n✅ Todos os testes passaram")


if __name__ == "__main__":
    run_all()
