# 🔒 Analisador de Windows Event Logs

**Projeto CET - Cibersegurança**  
Dashboard educacional para análise de segurança de logs do Windows com geração de relatórios HTML.

---

## 📋 Conteúdo

1. `log_analyzer.py` — Script principal de análise
2. `sample_events.json` — Dados de teste para demonstração
3. `README.md` — Esta documentação
4. `QUICKSTART.md` — Guia rápido de utilização (3 minutos)
5. `HARDENING_CHECKLIST.md` — Checklist de hardening Windows/Linux (baseada em CIS Benchmarks)
6. `INCIDENT_RESPONSE.md` — Plano de resposta a incidentes (NIST SP 800-61) com playbooks ligados aos alertas do script
7. `WAZUH_LAB.md` — Laboratório prático de SIEM com Wazuh (Manager, agentes, regras, exercícios)

---

## 🚀 Instalação

### Pré-requisitos

- Python 3.8+
- Sem dependências externas (usa apenas biblioteca padrão)

### Setup

```bash
# Clonar ou copiar arquivos
git clone <repo>
cd log-analyzer

# Executar (direto, sem instalação)
python log_analyzer.py --input sample_events.json --output report.html
```

---

## 📖 Uso

### Análise Básica

```bash
python log_analyzer.py --input logs.json --output report.html
```

### Com Exportação de Alertas (JSON)

```bash
python log_analyzer.py --input logs.json --output report.html --export-json
```

Isto gera também um arquivo `report.json` com todos os alertas estruturados.

### Formatos Suportados

- **JSON** — Exportação de Windows Event Viewer
- **CSV** — Logs em formato de tabela

---

## 🎯 Funcionalidades

### ✅ Análise de Eventos

- **24 tipos de eventos críticos** mapeados (Event IDs do Windows Security)
- **Detecção de anomalias** — padrões suspeitos como brute force
- **Relatório HTML elegante** — visualização limpa e profissional
- **Exportação JSON** — alertas estruturados para integração

### 📊 Eventos Detectados

| Event ID | Nome | Severidade |
|----------|------|-----------|
| 4625 | Falha de Logon | High |
| 4672 | Privilégios Especiais | High |
| 4698 | Tarefa Agendada Criada | High |
| 4726 | Conta de Utilizador Removida | High |
| 4719 | Política de Segurança Alterada | High |
| 4713 | Política Kerberos Alterada | High |
| 4720 | Conta de Utilizador Criada | Medium |
| 4728 | Membro Adicionado a Grupo | High |
| 4756 | Membro Adicionado a Grupo Universal | High |
| ... e mais 14 tipos | Vários | Vários |

---

## 💡 Como Usar (Passo a Passo)

### 1. Testar com Dados de Exemplo

```bash
python log_analyzer.py --input sample_events.json --output demo_report.html
```

Isto gera `demo_report.html` — abra num navegador para ver o relatório.

### 2. Com Logs Reais do Windows

#### Opção A: Exportar do Event Viewer (GUI)

1. Abrir **Event Viewer** (eventvwr.msc)
2. Selecionar **Windows Logs > Security**
3. Clicar em **Action > Export All Events...**
4. Guardar como XML
5. Converter XML para JSON:

```python
# converter.py
import xml.etree.ElementTree as ET
import json

tree = ET.parse('logs.xml')
root = tree.getroot()

events = []
for event in root.findall('.//Event'):
    event_dict = {}
    for child in event:
        tag = child.tag.split('}')[-1]
        event_dict[tag] = child.text
    events.append(event_dict)

with open('logs.json', 'w') as f:
    json.dump(events, f, indent=2)
```

#### Opção B: Usar PowerShell

```powershell
# Exportar últimos 1000 eventos de segurança
Get-EventLog -LogName Security -Newest 1000 | 
  Select-Object TimeGenerated, EventID, Message, Source |
  ConvertTo-Json | 
  Out-File -Path "security_logs.json" -Encoding UTF8
```

### 3. Analisar e Gerar Relatório

```bash
python log_analyzer.py --input security_logs.json --output analise_seguranca.html --export-json
```

---

## 📁 Estrutura do Relatório HTML

O relatório inclui:

### 1. **Header**
   - Título e data de geração
   - Contexto educacional (CET)

### 2. **Dashboard KPI**
   - Total de eventos
   - Contagem por severidade (Crítico, Alto, Médio, Baixo)
   - Total de alertas gerados

### 3. **Alertas de Segurança**
   - Lista ordenada por severidade
   - Cada alerta contém:
     - Título e ID do evento
     - Timestamp e origem
     - Descrição detalhada
     - Recomendação de ação

### 4. **Resumo de Eventos**
   - Tabela com frequência de cada tipo
   - Severidade associada

---

## 🔍 Lógica de Detecção

### Eventos Críticos (CRITICAL_EVENTS)

O script mapeia 24 Event IDs do Windows Security:

```python
CRITICAL_EVENTS = {
    4625: {"name": "Failed Logon", "severity": "high"},
    4672: {"name": "Special Privileges", "severity": "high"},
    4698: {"name": "Scheduled Task Created", "severity": "high"},
    # ... etc
}
```

### Detecção de Anomalias

**Brute Force Detection:**
- Se um utilizador tem > 5 tentativas de logon falhado (Event 4625)
- Gera alerta CRÍTICO com recomendação

---

## 🛠️ Extensões Futuras

Já cobertas neste projeto: checklist de hardening (`HARDENING_CHECKLIST.md`), playbooks de resposta a incidentes (`INCIDENT_RESPONSE.md`) e laboratório Wazuh (`WAZUH_LAB.md`). Próximos passos possíveis:

1. **Dashboard Web Real** (React + FastAPI)
   - Integrar este script como backend
   - Upload de arquivos de logs
   - Filtragem e busca em tempo real

2. **Automatizar Resposta a Incidentes**
   - Ligar os playbooks do `INCIDENT_RESPONSE.md` a Active Response do Wazuh
   - Notificações automáticas por email/Slack quando um alerta crítico é gerado

3. **Certificados/Módulos Concluídos**
   - Documentar formação e certificações relevantes (CET em Cibersegurança e outras)

---

## 📊 Exemplo de Output

### Alertas (Parte do Relatório HTML)

```
🔴 CRÍTICO — Possível Ataque de Força Bruta Detectado
Fonte: administrator | Data: 2024-01-15

Utilizador 'administrator' teve 6 tentativas de logon falhadas
Recomendação: Bloquear conta temporariamente e investigar origem das tentativas

---

🟠 ALTO — Tarefa Agendada Criada
Fonte: SERVER-DC01 | Data: 2024-01-15T10:45:20Z

Tarefa agendada criada: \Microsoft\Windows\System32\tasks\SuspiciousTask
Recomendação: Auditar tarefa agendada. Validar se foi criada por administrador autorizado.
```

---

## 🔐 Recomendações de Segurança

1. **Brute Force (4625)**
   - Implementar bloqueio de conta após N falhas
   - Usar MFA
   - Monitorar IPs suspeitos

2. **Privilégios Especiais (4672)**
   - Revisar legitimidade
   - Auditar ações do utilizador
   - Implementar JIT (Just-In-Time) admin

3. **Tarefas Agendadas (4698)**
   - Whitelist de tarefas permitidas
   - Validar criador da tarefa
   - Monitorar execução

4. **Política de Segurança (4719)**
   - Alertar imediatamente
   - Investigar quem fez a alteração
   - Implementar Group Policy Audit

---

## 📚 Recursos Educacionais

- [Microsoft Event ID Reference](https://docs.microsoft.com/en-us/windows/security/threat-protection/auditing/audit-events)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework/)
- [CIS Windows Security Baseline](https://www.cisecurity.org/benchmark/microsoft_windows_10)

---

## 📝 Notas do Projeto

Este é um **projeto educacional** para o **CET em Cibersegurança**, composto por vários módulos complementares:

| Módulo | Ficheiro | Estado |
|---|---|---|
| Análise de logs (script Python) | `log_analyzer.py` | ✅ Concluído |
| Laboratório SIEM (Wazuh) | `WAZUH_LAB.md` | ✅ Concluído |
| Checklist de hardening Windows/Linux | `HARDENING_CHECKLIST.md` | ✅ Concluído |
| Resposta a incidentes (phishing, MFA, backups, IR) | `INCIDENT_RESPONSE.md` | ✅ Concluído |
| Certificados/módulos concluídos | — | ⏳ Pendente |

Objetivos:
- ✅ Compreender Windows Event Logs
- ✅ Identificar eventos de segurança
- ✅ Gerar alertas baseados em regras
- ✅ Criar relatórios profissionais
- ✅ Configurar um SIEM real (Wazuh) e correlacionar com a análise offline
- ✅ Documentar hardening e resposta a incidentes de forma acionável

O `log_analyzer.py` **não é** um substituto para ferramentas profissionais como Wazuh, Splunk, ou Microsoft Sentinel — é complementar, usado sobretudo para análise forense offline (ver `WAZUH_LAB.md` para a componente de deteção em tempo real).

---

## 📞 Suporte

Para dúvidas ou melhorias:
- Revisar código (bem comentado)
- Testar com dados reais
- Expandir regras de detecção
- Integrar com dashboard web

---

**Criado para FaroForma — Formação em Cibersegurança**
