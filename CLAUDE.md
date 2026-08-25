# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Educational cybersecurity portfolio project (CET em Cibersegurança, FaroForma). Not a git repository — a flat folder of deliverables spanning three phases. All content (docs, code comments, CLI output, UI strings) is written in **Portuguese (PT-PT)**; keep new content consistent with that.

- **Fase 1** — `log_analyzer.py`: standalone script that analyzes a static Windows Event Log export (JSON/CSV) and renders an HTML report. Python 3.8+ standard library only, no dependencies.
- **Fase 2** — `wazuh-dashboard/`: a FastAPI backend + static HTML/JS frontend that queries a **live** Wazuh instance instead of a static file.
- **Fase 3** — `LAB_WAZUH_HYPERV.md`: an infrastructure how-to for standing up the Wazuh Manager/Indexer/Dashboard in a Hyper-V VM plus a Windows agent. It's the live backend that Fase 2's `.env` points at; there's no code to run from it.

## File organization

Fase 2 lives entirely under `wazuh-dashboard/`: `backend/` (`main.py`, `wazuh_client.py`, `event_catalog.py`, `requirements.txt`, `.env.example`, `test_with_mock.py`) and `frontend/` (`index.html`, `app.js`, `style.css`), plus its own `wazuh-dashboard/README.md`. There are no loose duplicate copies at the repo root — if you ever see `main.py`/`wazuh_client.py`/`index.html` at the top level again, treat it as drift from this tree, not a second source of truth.

## Commands

No build system, package manager, or test suite for Fase 1. Fase 2 has a `requirements.txt` (inside the zip) and a mock-based smoke test.

### Fase 1 — offline analyzer
```bash
python log_analyzer.py --input sample_events.json --output report.html
python log_analyzer.py --input sample_events.json --output report.html --export-json   # also writes report.json
```
`--input` accepts `.json` (Windows Event Viewer export, or `{"events": [...]}`) or `.csv`. No automated test — verify changes by running the command above against `sample_events.json` and inspecting the generated `report.html`.

### Fase 2 — live dashboard
```bash
cd wazuh-dashboard/backend
py -m venv .venv                          # first time only
./.venv/Scripts/python.exe -m pip install -r requirements.txt
cp .env.example .env                      # fill in WAZUH_MANAGER_* / WAZUH_INDEXER_* (see LAB_WAZUH_HYPERV.md)
PYTHONIOENCODING=utf-8 ./.venv/Scripts/python.exe test_with_mock.py   # sanity check without a live Wazuh — should print "Todos os testes passaram"
./.venv/Scripts/python.exe -m uvicorn main:app --reload --port 8000
```
Dependencies install into `.venv/` (per-backend virtualenv), not the global/system Python — don't `pip install` these globally, it collides with unrelated tools on a shared machine (e.g. downgrading a globally-pinned `httpx`/`python-dotenv`). `PYTHONIOENCODING=utf-8` is needed on Windows because `test_with_mock.py` prints `✓`/`→`, which the default `cp1252` console encoding can't handle.
Frontend is dependency-free HTML/CSS/JS: open `wazuh-dashboard/frontend/index.html` directly, or `python -m http.server 5500` from `frontend/` to avoid CORS/file:// quirks. Swagger UI for the API is at `http://localhost:8000/docs`.

## Architecture

### Fase 1 — `log_analyzer.py`

Single-file pipeline built around `WindowsEventLogAnalyzer`:

1. **Parse** — `parse_evtx_json()` / `parse_csv_logs()` load raw events into `self.events`.
2. **Analyze** — `analyze_events()` walks every event, tallies `self.statistics`, and for any Event ID present in the `CRITICAL_EVENTS` dict (27 Windows Security Event IDs → name/severity) creates an `EventAlert` dataclass appended to `self.alerts`. The lookup casts `event_id` to `int` before checking `CRITICAL_EVENTS` (whose keys are `int`) — a past bug here compared a `str(event_id)` against the `int` keys, which silently matched nothing and meant no per-event alerts were ever generated (only the brute-force anomaly alert survived). Keep this cast when touching this code.
3. **Detect anomalies** — `_detect_anomalies()` runs separately (currently: brute-force detection — >5 failed logons, Event ID 4625, from the same `TargetUserName` triggers a synthetic `critical` alert).
4. **Report** — `generate_html_report()` renders a self-contained HTML dashboard (inline CSS, no external assets); `export_alerts_json()` writes structured alerts for downstream tooling.

When adding detection rules, extend `CRITICAL_EVENTS` (and `_get_recommendation()` / `_build_description()` for event-specific text) rather than adding parallel logic — everything else (stats, HTML rendering, JSON export) reads off that single dict and `self.alerts`.

### Fase 2 — `wazuh-dashboard/`

- `backend/wazuh_client.py` — two separate API clients, because Wazuh splits concerns across two ports and two auth schemes:
  - `WazuhManagerClient` (port 55000): agents/cluster metadata only, JWT auth via `/security/user/authenticate` (token cached, renewed ~1 min before its 15-min expiry).
  - `WazuhIndexerClient` (port 9200, OpenSearch underneath): where alerts actually live, Basic Auth, queries the `wazuh-alerts-*` index with OpenSearch/Elasticsearch DSL (`get_recent_alerts`, `get_alert_stats`).
- `backend/event_catalog.py` — `CRITICAL_EVENTS` + `RECOMMENDATIONS` + `classify_alert()`. This deliberately re-implements the same Event ID → name/severity/recommendation mapping as Fase 1's `CRITICAL_EVENTS` in `log_analyzer.py`, so both phases classify events identically — **when you edit one, edit the other** (see Cross-document coupling below).
- `backend/main.py` — FastAPI app wiring the two clients together. Every alert from the Indexer is run through `_extract_windows_event_id()` (reads `data.win.system.eventID`) and `_enrich_alert()` (adds the `event_catalog` classification) before being returned. Endpoints: `/api/health`, `/api/agents`, `/api/alerts` (filterable by `hours`/`min_level`/`agent_name`/`severity`), `/api/stats` (aggregates by severity/event/agent), `/api/brute-force` (same >N-failed-logons-per-user logic as Fase 1's anomaly detector, applied to live data), `/api/alerts/explain` (POST — see below).
- `backend/ai_client.py` — `AIHubMixClient`, a thin wrapper around the [AIhubmix](https://github.com/AIhubmix) OpenAI-compatible gateway (`https://api.aihubmix.com/v1`, 400+ models behind one key). `POST /api/alerts/explain` takes the same JSON shape `/api/alerts` returns (validated by the `EnrichedAlert` Pydantic model in `main.py`) and asks the model for a short PT-PT explanation, on top of — not replacing — `event_catalog.py`'s static recommendation. Configured via `AIHUBMIX_API_KEY` / `AIHUBMIX_MODEL` (default `auto`, AIhubmix's own cost/quality routing) in `.env`; when the key is unset, `main.py` leaves `ai_client = None` and the endpoint returns `503` instead of failing.
- `frontend/` — static `index.html` + `app.js` + `style.css`, polls the backend every 30s, no build step.

## Cross-document coupling

The Markdown files and the Fase 2 backend are not independent — they reference the same Event IDs and severities as `CRITICAL_EVENTS` in `log_analyzer.py`, so changes to one side should be reflected in the others:

- `wazuh-dashboard/backend/event_catalog.py` — its `CRITICAL_EVENTS`/`RECOMMENDATIONS` mirror `log_analyzer.py`'s. Keep both in sync when adding/changing an Event ID's name, severity, or recommendation text.
- `INCIDENT_RESPONSE.md` — each playbook is keyed to a specific alert the script produces (e.g. `anomaly_brute_force` → Playbook 1, Event ID 4728/4756 → Playbook 2, 4719 → Playbook 5).
- `WAZUH_LAB.md` — the custom Wazuh detection rules (local_rules.xml snippets) are written to mirror the same Event IDs/severities as `CRITICAL_EVENTS`, and Exercise 4 round-trips a Wazuh alert export back through `log_analyzer.py` for comparison.
- `HARDENING_CHECKLIST.md` — the Wazuh SCA module (mentioned in `WAZUH_LAB.md`) is expected to validate the same controls listed here.
- `report.html` / `report.json` in the repo root are **generated sample output** (from `sample_events.json`), not hand-maintained source — regenerate them via the Fase 1 command above rather than editing directly.

## Laboratório Wazuh

`scripts/` has three scripts that automate what's safe to automate from `LAB_WAZUH_HYPERV.md` (Fase 3) — none of them run each other, and none should be run unattended (VM creation, `sudo`, and installing a Windows service all need eyes on them). Order:

1. `scripts/setup-hyperv-lab.ps1` — Windows host, PowerShell as Admin. Enables Hyper-V if needed (stops and asks for a reboot if it had to), creates the `Lab-Wazuh` Virtual Switch, creates the Ubuntu VM (Gen 2, 8GB/4vCPU/60GB, Secure Boot off). Stops there — does not install Ubuntu.
2. *(manual)* Install Ubuntu Server on the VM console, note its IP, SSH in — Parte 2.4/2.5 of `LAB_WAZUH_HYPERV.md`.
3. `scripts/install-wazuh.sh` — inside the Ubuntu VM via SSH. Updates the system, runs the official `wazuh-install.sh -a`, prints the generated passwords, and verifies all 3 services (`wazuh-manager`/`wazuh-indexer`/`wazuh-dashboard`) are `active (running)`.
4. *(manual)* First login to the Wazuh Dashboard in a browser (self-signed cert warning) — Parte 4.
5. `scripts/install-wazuh-agent.ps1 -WazuhManagerIP <ip>` — on the Windows machine to monitor, PowerShell as Admin. Downloads the MSI, installs silently, starts `WazuhSvc`, confirms it's `Running`.
6. *(manual)* Confirm the agent shows "Active" in the Dashboard and generate a test event (e.g. a failed logon, Event ID 4625) — Parte 6.

`scripts/README.md` lists every step in this flow that genuinely can't be automated (BIOS/UEFI virtualization, the reboot after enabling Hyper-V, picking the physical NIC for the external switch, the interactive Ubuntu installer, the two in-browser validation steps) and why. `LAB_WAZUH_HYPERV.md` (repo root, not `docs/`) has the full narrative guide these scripts implement.

## Adding a new project module

`README.md` has a status table of modules (script, Wazuh lab, hardening checklist, incident response, certificates). When adding a new top-level `.md` deliverable, update that table and the "Conteúdo" file list in `README.md`.
