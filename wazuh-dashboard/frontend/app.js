// Dashboard de Cibersegurança — lógica de frontend
// Consome a API FastAPI (backend/main.py) e preenche a interface

const API_BASE = "http://localhost:8000";

const windowSelect = document.getElementById("window-select");
const severityFilter = document.getElementById("severity-filter");
const refreshBtn = document.getElementById("refresh-btn");
const statusIndicator = document.getElementById("status-indicator");

function setStatus(ok) {
  statusIndicator.textContent = ok ? "● ligado ao Wazuh" : "● sem ligação";
  statusIndicator.className = "status-indicator " + (ok ? "status-ok" : "status-error");
}

function severityBadge(severity) {
  const labels = {
    critical: "Crítico",
    high: "Alto",
    medium: "Médio",
    low: "Baixo",
    info: "Info",
  };
  return `<span class="severity-badge ${severity}">${labels[severity] || severity}</span>`;
}

function formatTimestamp(ts) {
  if (!ts) return "-";
  try {
    return new Date(ts).toLocaleString("pt-PT");
  } catch {
    return ts;
  }
}

async function fetchJSON(path, options) {
  const response = await fetch(`${API_BASE}${path}`, options);
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(body.detail || `Erro HTTP ${response.status}`);
  }
  return response.json();
}

async function loadStats(hours) {
  const stats = await fetchJSON(`/api/stats?hours=${hours}`);

  document.getElementById("kpi-total").textContent = stats.total_alerts ?? 0;
  document.getElementById("kpi-critical").textContent = stats.by_severity?.critical ?? 0;
  document.getElementById("kpi-high").textContent = stats.by_severity?.high ?? 0;
  document.getElementById("kpi-medium").textContent = stats.by_severity?.medium ?? 0;
  document.getElementById("kpi-low").textContent = stats.by_severity?.low ?? 0;

  const tbody = document.getElementById("top-events-body");
  tbody.innerHTML = "";
  (stats.top_events || []).forEach((ev) => {
    const tr = document.createElement("tr");
    tr.innerHTML = `<td>${ev.event_id}</td><td>${ev.name}</td><td><strong>${ev.count}</strong></td>`;
    tbody.appendChild(tr);
  });
}

async function loadAgents() {
  const data = await fetchJSON(`/api/agents`);
  const activeCount = (data.agents || []).filter((a) => a.status === "active").length;
  document.getElementById("kpi-agents").textContent = activeCount;

  const list = document.getElementById("agents-list");
  list.innerHTML = "";

  if (!data.agents || data.agents.length === 0) {
    list.innerHTML = '<p class="empty-state">Nenhum agente encontrado</p>';
    return;
  }

  data.agents.forEach((agent) => {
    const row = document.createElement("div");
    row.className = "agent-row";
    row.innerHTML = `
      <span>${agent.name} <small style="color:#999">(${agent.ip || "-"})</small></span>
      <span class="agent-status ${agent.status}">${agent.status}</span>
    `;
    list.appendChild(row);
  });
}

// Alertas atualmente renderizados, indexados por posição — usado pelo botão
// "Explicar com IA" para saber a que alerta corresponde sem ter de embutir
// dados crus (potencialmente vindos de logs Windows não confiáveis, ex:
// full_log) num atributo HTML.
let renderedAlerts = [];

async function loadAlerts(hours, severity) {
  let url = `/api/alerts?hours=${hours}`;
  if (severity) url += `&severity=${severity}`;

  const data = await fetchJSON(url);
  const list = document.getElementById("alerts-list");
  list.innerHTML = "";

  if (!data.alerts || data.alerts.length === 0) {
    renderedAlerts = [];
    list.innerHTML = '<p class="empty-state">Sem alertas neste período</p>';
    return;
  }

  const severityOrder = { critical: 0, high: 1, medium: 2, low: 3, info: 4 };
  const sorted = [...data.alerts].sort(
    (a, b) => (severityOrder[a.severity] ?? 5) - (severityOrder[b.severity] ?? 5)
  );

  renderedAlerts = sorted.slice(0, 100);
  renderedAlerts.forEach((alert, index) => {
    const item = document.createElement("div");
    item.className = `alert-item ${alert.severity}`;
    item.dataset.alertIndex = String(index);
    item.innerHTML = `
      <div class="alert-title">
        <span>${alert.friendly_name}${alert.windows_event_id ? " (ID " + alert.windows_event_id + ")" : ""}</span>
        ${severityBadge(alert.severity)}
      </div>
      <div class="alert-meta">
        ${alert.agent_name} • ${formatTimestamp(alert.timestamp)}
      </div>
      <div class="alert-meta">${alert.rule_description || ""}</div>
      <div class="alert-recommendation"><strong>Recomendação:</strong> ${alert.recommendation}</div>
      <div class="alert-explain-row">
        <button type="button" class="explain-btn">🤖 Explicar com IA</button>
      </div>
      <div class="alert-explanation" hidden></div>
    `;
    list.appendChild(item);
  });
}

async function handleExplainClick(button) {
  const item = button.closest(".alert-item");
  const alert = renderedAlerts[Number(item.dataset.alertIndex)];
  const explanationEl = item.querySelector(".alert-explanation");
  if (!alert || !explanationEl) return;

  button.disabled = true;
  button.textContent = "A pensar...";
  explanationEl.hidden = false;
  explanationEl.className = "alert-explanation";
  explanationEl.textContent = "A gerar explicação...";

  try {
    const result = await fetchJSON("/api/alerts/explain", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(alert),
    });
    // textContent, não innerHTML: full_log/rule_description podem conter
    // dados de logs Windows não confiáveis, e passam pelo modelo antes de
    // voltar aqui — não confiar na resposta como HTML seguro.
    explanationEl.textContent = result.explanation;
    button.textContent = "🔄 Gerar nova explicação";
  } catch (err) {
    explanationEl.className = "alert-explanation alert-explanation-error";
    explanationEl.textContent = `Erro ao gerar explicação: ${err.message}`;
    button.textContent = "🤖 Explicar com IA";
  } finally {
    button.disabled = false;
  }
}

async function loadBruteForce(hours) {
  const data = await fetchJSON(`/api/brute-force?hours=${hours}`);
  const panel = document.getElementById("brute-force-panel");
  const list = document.getElementById("brute-force-list");

  if (!data.suspects || data.suspects.length === 0) {
    panel.style.display = "none";
    return;
  }

  panel.style.display = "block";
  list.innerHTML = "";
  data.suspects.forEach((s) => {
    const item = document.createElement("div");
    item.className = "bf-item";
    item.innerHTML = `
      <span><strong>${s.user}</strong> — ${s.failed_attempts} tentativas falhadas (${s.source_agent})</span>
      <span>${formatTimestamp(s.last_attempt)}</span>
    `;
    list.appendChild(item);
  });
}

async function refreshDashboard() {
  const hours = windowSelect.value;
  const severity = severityFilter.value;

  try {
    await Promise.all([
      loadStats(hours),
      loadAgents(),
      loadAlerts(hours, severity),
      loadBruteForce(hours),
    ]);
    setStatus(true);
  } catch (err) {
    console.error(err);
    setStatus(false);
  }
}

refreshBtn.addEventListener("click", refreshDashboard);
windowSelect.addEventListener("change", refreshDashboard);
severityFilter.addEventListener("change", refreshDashboard);

// Delegação de evento: a lista é recriada a cada refresh (30s), por isso
// o listener vive no contentor em vez de em cada botão individual.
document.getElementById("alerts-list").addEventListener("click", (event) => {
  const button = event.target.closest(".explain-btn");
  if (button) handleExplainClick(button);
});

// Carrega ao abrir e depois atualiza automaticamente a cada 30s
refreshDashboard();
setInterval(refreshDashboard, 30000);
