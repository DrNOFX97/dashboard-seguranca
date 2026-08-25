# 🐺 Laboratório Wazuh — SIEM/XDR

**Projeto CET - Cibersegurança**
Laboratório prático para montar um SIEM open-source (Wazuh), ligar agentes Windows/Linux, detetar os mesmos tipos de eventos que o `log_analyzer.py` analisa offline — mas agora em tempo real — e comparar as duas abordagens.

---

## 🎯 Objetivo do Laboratório

1. Instalar o **Wazuh Manager + Indexer + Dashboard** (stack central)
2. Instalar o **Wazuh Agent** numa máquina Windows e/ou Linux
3. Configurar deteção para os mesmos Event IDs já mapeados no `log_analyzer.py` (4625, 4672, 4698, 4719, 4726, 4728...)
4. Simular ataques simples (brute force) e validar que o Wazuh gera alertas
5. Exportar alertas do Wazuh e comparar/reutilizar com o script Python deste projeto

---

## 🏗️ Arquitetura

```
┌─────────────────────┐         ┌──────────────────────────────────────┐
│   Máquina Windows    │         │            Wazuh Server                │
│   (Wazuh Agent)      │────────▶│  ┌────────────┐  ┌──────────────────┐ │
│   Event Logs          │  1514/  │  │  Manager   │─▶│  Indexer          │ │
│   (Security, System)  │  TCP    │  │  (análise, │  │  (OpenSearch —    │ │
└─────────────────────┘         │  │   regras)  │  │   armazenamento)  │ │
                                  │  └────────────┘  └──────────────────┘ │
┌─────────────────────┐         │         │                              │
│   Máquina Linux      │────────▶│         ▼                              │
│   (Wazuh Agent)      │         │  ┌──────────────────┐                 │
│   /var/log/auth.log  │         │  │  Dashboard (Kibana│                 │
└─────────────────────┘         │  │  fork) — porta 443│                 │
                                  │  └──────────────────┘                 │
                                  └──────────────────────────────────────┘
```

- **Manager**: recebe eventos dos agentes, aplica regras (decoders + rules), gera alertas
- **Indexer**: armazena os alertas (baseado em OpenSearch)
- **Dashboard**: interface web para visualizar e investigar alertas (porta 443, login `admin`)
- **Agent**: instalado nas máquinas monitorizadas, recolhe logs e envia para o Manager

---

## 📋 Requisitos

| Componente | Mínimo Recomendado |
|---|---|
| Wazuh Server (host da lab) | 4 vCPU, 8 GB RAM, 50 GB disco |
| VM Windows (agente) | Windows 10/11 ou Server, 2 GB RAM |
| VM Linux (agente) | Ubuntu/Debian, 1 GB RAM |
| Software | Docker + Docker Compose (opção mais rápida para lab) OU VM dedicada (produção) |

> Para um laboratório de estudo, a instalação via **Docker** é a mais rápida a montar e a desmontar. Para simular um ambiente mais próximo de produção, usa a instalação nativa em VM (Ubuntu Server).

---

## 🚀 Instalação — Opção A: Docker (Quickstart)

```bash
# 1. Clonar o repositório oficial do wazuh-docker
git clone https://github.com/wazuh/wazuh-docker.git -b v4.x --depth=1
cd wazuh-docker/single-node

# 2. Gerar certificados necessários
docker compose -f generate-indexer-certs.yml run --rm generator

# 3. Subir a stack completa (Manager + Indexer + Dashboard)
docker compose up -d

# 4. Verificar que os containers estão saudáveis
docker compose ps
```

> Substitui `v4.x` pela versão estável mais recente disponível no repositório no momento em que fizeres o lab.

Acede ao dashboard em `https://localhost` (aceita o certificado autoassinado). Credenciais por defeito ficam no `.env` do repositório — **altera-as antes de expor a lab a qualquer rede partilhada**.

## 🚀 Instalação — Opção B: VM Nativa (mais próxima de produção)

```bash
# Numa VM Ubuntu Server 22.04 limpa:
curl -sO https://packages.wazuh.com/4.x/wazuh-install.sh
sudo bash wazuh-install.sh -a
```

O script instala e configura automaticamente Manager, Indexer e Dashboard, e apresenta no fim a password gerada para o utilizador `admin`. Guarda-a — não é reapresentada.

---

## 🖥️ Deploy do Agent — Windows

1. No **Dashboard**, ir a `Agents management > Deploy new agent`
2. Escolher **Windows**, indicar o IP do Manager
3. Executar no PowerShell da máquina Windows (como Administrador):

```powershell
Invoke-WebRequest -Uri https://packages.wazuh.com/4.x/windows/wazuh-agent-4.x.x-1.msi -OutFile wazuh-agent.msi
msiexec.exe /i wazuh-agent.msi /q WAZUH_MANAGER='<IP_DO_MANAGER>'
NET START WazuhSvc
```

4. Confirmar no Dashboard que o agente aparece como **Active**

### Garantir recolha do Security Event Log

No ficheiro `C:\Program Files (x86)\ossec-agent\ossec.conf`, confirmar que existe:

```xml
<localfile>
  <location>Security</location>
  <log_format>eventchannel</log_format>
</localfile>
```

Este é o canal que contém os Event IDs 4625, 4672, 4698, 4719, 4726, 4728 — os mesmos que o `log_analyzer.py` já sabe interpretar.

---

## 🐧 Deploy do Agent — Linux

```bash
curl -so wazuh-agent.deb https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.x.x_amd64.deb
sudo WAZUH_MANAGER='<IP_DO_MANAGER>' dpkg -i ./wazuh-agent.deb
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
```

Por defeito o agent já recolhe `/var/log/auth.log` (SSH, sudo) — cobre o equivalente Linux das secções de autenticação da checklist de hardening (`HARDENING_CHECKLIST.md`).

---

## 🛠️ Regras Customizadas — Alinhar com o `log_analyzer.py`

O Wazuh já traz regras nativas (`0575-win-security_rules.xml`) para muitos Event IDs do Windows, mas para replicar exatamente a lógica de severidade do `log_analyzer.py`, cria uma regra local em `/var/ossec/etc/rules/local_rules.xml` no Manager:

```xml
<group name="local,windows_security,">

  <!-- Alinhado com CRITICAL_EVENTS do log_analyzer.py -->
  <rule id="100010" level="10">
    <if_sid>60122</if_sid>
    <field name="win.system.eventID">^4698$</field>
    <description>Tarefa Agendada Criada — validar se autorizada (ver INCIDENT_RESPONSE.md, Playbook 5)</description>
    <group>scheduled_task,</group>
  </rule>

  <rule id="100011" level="12">
    <if_sid>60122</if_sid>
    <field name="win.system.eventID">^4719$</field>
    <description>Política de Segurança Alterada — CRÍTICO, seguir Playbook 5</description>
    <group>policy_change,</group>
  </rule>

  <rule id="100012" level="10">
    <if_sid>60122</if_sid>
    <field name="win.system.eventID">^4728|4756$</field>
    <description>Membro adicionado a grupo privilegiado — seguir Playbook 2 (escalada de privilégios)</description>
    <group>privilege_escalation,</group>
  </rule>

</group>
```

Depois de editar, reiniciar o Manager:

```bash
sudo systemctl restart wazuh-manager
```

### Brute Force — usar o módulo nativo `active-response` / regra de frequência

O Wazuh já deteta força bruta via correlação de eventos (`frequency` + `timeframe`) na regra base `60204`/`60205` para Windows. Para replicar o limiar do `log_analyzer.py` (>5 falhas), confirma/ajusta:

```xml
<rule id="100013" level="12" frequency="6" timeframe="120">
  <if_matched_sid>60122</if_matched_sid>
  <field name="win.system.eventID">^4625$</field>
  <same_source_ip />
  <description>Possível ataque de força bruta — 6+ falhas de logon em 2 min (ver Playbook 1)</description>
  <group>authentication_failures,brute_force,</group>
</rule>
```

---

## 🧪 Exercícios do Laboratório

### Exercício 1 — Validar Ligação do Agente

- [ ] Confirmar agente **Active** no Dashboard (`Agents management`)
- [ ] Confirmar que eventos chegam: `Discover` no Dashboard, filtrar por `agent.name`

### Exercício 2 — Simular Força Bruta (Windows)

Numa máquina de teste (nunca em produção), gera falhas de login propositadas:

```powershell
# Simula tentativas de logon falhadas (ajusta credenciais para umas inválidas de propósito)
for ($i=1; $i -le 6; $i++) {
    runas /user:administrator "cmd.exe" 2>$null
}
```

- [ ] Confirmar que o alerta de brute force aparece no Dashboard em `Security events`
- [ ] Comparar severidade atribuída pelo Wazuh com a severidade que o `log_analyzer.py` atribuiria ao mesmo log exportado

### Exercício 3 — Simular Alteração de Grupo Privilegiado

```powershell
net localgroup Administrators <utilizador_teste> /add
```

- [ ] Confirmar alerta correspondente à regra `100012`
- [ ] Seguir o **Playbook 2** do `INCIDENT_RESPONSE.md` como exercício de resposta

### Exercício 4 — Exportar e Reutilizar no `log_analyzer.py`

1. No Dashboard, ir a `Security events`, filtrar o intervalo do teste
2. Exportar os resultados (`Share > CSV Reports`, ou via API: `GET /security/user/authenticate` + `GET /alerts`)
3. Converter o export para o formato aceite pelo `log_analyzer.py` (`EventID`, `TimeCreated`, `Computer`, `TargetUserName`)
4. Correr:

```bash
python log_analyzer.py --input wazuh_export.json --output comparacao.html --export-json
```

5. Comparar os alertas gerados pelas duas ferramentas — este exercício demonstra a diferença entre **deteção em tempo real correlacionada** (Wazuh) e **análise forense offline** (`log_analyzer.py`).

---

## 🔍 Casos de Uso Adicionais para Explorar

| Caso de Uso | Módulo Wazuh |
|---|---|
| Deteção de malware/rootkits | File Integrity Monitoring (FIM) + Rootcheck |
| Compliance CIS Benchmark automático | SCA (Security Configuration Assessment) — valida a `HARDENING_CHECKLIST.md` automaticamente |
| Deteção de vulnerabilidades | Vulnerability Detection module |
| Resposta automática | Active Response (ex: bloquear IP automaticamente após brute force) |

> Sugestão de extensão do lab: ativar o módulo **SCA** e correr um scan CIS contra a VM Windows/Linux — os resultados devem coincidir em grande parte com os itens já listados manualmente em `HARDENING_CHECKLIST.md`.

---

## 🐞 Troubleshooting Comum

| Problema | Causa Provável | Solução |
|---|---|---|
| Agente aparece "Never Connected" | Firewall a bloquear porta 1514 | Abrir porta 1514/TCP entre agente e manager |
| Dashboard não carrega | Indexer ainda a iniciar | Esperar 1-2 min, verificar `docker compose logs wazuh.indexer` |
| Sem eventos do Windows Security Log | `eventchannel` mal configurado | Confirmar `ossec.conf` do agente, reiniciar `WazuhSvc` |
| Regras customizadas não aplicam | Erro de sintaxe XML | Validar com `/var/ossec/bin/wazuh-logtest` antes de reiniciar o manager |

---

## 📚 Referências

- [Documentação Oficial Wazuh](https://documentation.wazuh.com/)
- [Wazuh Docker Quickstart](https://github.com/wazuh/wazuh-docker)
- [Wazuh Ruleset Reference](https://documentation.wazuh.com/current/user-manual/ruleset/index.html)
- [MITRE ATT&CK — mapeamento usado pelas regras Wazuh](https://attack.mitre.org/)

---

## 🔗 Integração com Este Projeto

| Componente do Projeto | Papel no Laboratório |
|---|---|
| `log_analyzer.py` | Análise offline/forense dos mesmos Event IDs; usado no Exercício 4 para comparação |
| `HARDENING_CHECKLIST.md` | Base de comparação para o módulo SCA do Wazuh |
| `INCIDENT_RESPONSE.md` | Playbooks seguidos quando o Wazuh gera um alerta nos Exercícios 2 e 3 |

---

**Projeto CET - Cibersegurança — FaroForma**
