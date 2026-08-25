# 🔬 Laboratório Wazuh em Hyper-V — Guia Completo

**Projeto CET - Cibersegurança | Fase 3: Laboratório SIEM**

---

## Porquê Wazuh (e não Security Onion)

| | Wazuh | Security Onion |
|---|---|---|
| Foco | Endpoint (agente instalado no Windows) | Rede (precisa de porta espelhada/SPAN) |
| RAM mínima | 8 GB (quickstart) | 16 GB+ (desde que passou a usar Elastic Agent) |
| Setup em Hyper-V | Direto — instalação manual em Ubuntu Server | Complicado — captura de tráfego de rede não é trivial em VM |
| Encaixa no teu projeto | ✅ Lê os mesmos Event IDs que o `log_analyzer_real.py` já trata | ⚠️ Foco diferente (NIDS: Suricata/Zeek) |

Conclusão: para o teu caso — CET, Hyper-V, foco em Windows Event Logs — o Wazuh é a escolha certa.

---

## Arquitetura do Laboratório

```
┌─────────────────────────────────────────┐
│         Anfitrião Windows (Hyper-V)       │
│                                            │
│  ┌──────────────────┐   ┌──────────────┐ │
│  │  VM Ubuntu Server │   │ Este Windows │ │
│  │  22.04 LTS        │   │ (ou outra VM)│ │
│  │                    │   │              │ │
│  │  Wazuh Indexer     │◄──┤ Wazuh Agent  │ │
│  │  Wazuh Server      │   │ (envia       │ │
│  │  Wazuh Dashboard   │   │  Event Logs) │ │
│  └──────────────────┘   └──────────────┘ │
│         Virtual Switch (Hyper-V)          │
└─────────────────────────────────────────┘
```

---

## PARTE 1 — Preparar o Hyper-V

### 1.1 Ativar Hyper-V

PowerShell como Administrador:
```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
```
Reiniciar o computador.

### 1.2 Criar Virtual Switch

No **Hyper-V Manager** → **Virtual Switch Manager**:
- Criar um switch **Externo** (se quiseres que a VM tenha IP na tua rede local, mais fácil para testar) ou **Interno** (isolado, mais seguro para laboratório)
- Nome sugerido: `Lab-Wazuh`

Recomendação para começar: **Externo**, ligado ao teu adaptador de rede físico — assim o teu Windows e a VM Wazuh ficam na mesma sub-rede e comunicam sem complicações de NAT.

---

## PARTE 2 — Criar a VM Ubuntu Server

### 2.1 Descarregar Ubuntu Server 22.04 LTS

https://ubuntu.com/download/server → `ubuntu-22.04.x-live-server-amd64.iso`

### 2.2 Criar a VM no Hyper-V Manager

**New → Virtual Machine**

| Definição | Valor |
|---|---|
| Geração | **Geração 2** |
| Memória | **8192 MB** (mínimo) — idealmente 10-12 GB se tiveres disponível |
| Rede | O switch `Lab-Wazuh` criado atrás |
| Disco | **60 GB** (VHDX dinâmico) |
| Instalação | A partir da ISO do Ubuntu Server |
| vCPU | 4 (depois de criada, em Settings → Processor) |

### 2.3 Ajustar Firmware (importante!)

Antes de arrancar, em **Settings → Security**:
- **Desativar Secure Boot** (ou mudar o template para "Microsoft UEFI Certificate Authority")

Sem isto, a VM não arranca a partir da ISO do Ubuntu.

### 2.4 Instalar Ubuntu Server

Arrancar a VM e seguir o instalador:
- Idioma / teclado: Português
- Rede: deixar em DHCP automático (anota o IP que vai aparecer, vais precisar dele)
- Storage: usar disco inteiro (layout padrão)
- Utilizador: cria um (ex: `fernando`) — **anota a password**
- **"Install OpenSSH server"** → marcar **SIM** (essencial, para depois trabalhares via SSH a partir do teu Windows em vez da consola do Hyper-V)
- Terminar instalação, remover a ISO virtual, reiniciar

### 2.5 Confirmar o IP da VM

Depois de reiniciar e fazer login na consola do Hyper-V:
```bash
ip a
```
Anota o IP (ex: `192.168.1.150`) — vais precisar dele em todos os passos seguintes.

A partir daqui, podes ligar via SSH do teu Windows (PowerShell ou Windows Terminal):
```powershell
ssh fernando@192.168.1.150
```

---

## PARTE 3 — Instalar o Wazuh (Quickstart Nó Único)

Já dentro da VM Ubuntu (via SSH):

### 3.1 Atualizar o sistema
```bash
sudo apt update && sudo apt upgrade -y
```

### 3.2 Descarregar e correr o instalador assistido

Este único script instala Indexer + Server + Dashboard (versão atual 4.14):

```bash
curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh
sudo bash ./wazuh-install.sh -a --install-dependencies
```

Isto demora **10-15 minutos**. No final, o terminal mostra algo como:

```
INFO: --- Summary ---
INFO: You can access the web interface https://<WAZUH_SERVER_IP>
User: admin
Password: <password gerada automaticamente>
```

**⚠️ Guarda esta password imediatamente** — não vai reaparecer facilmente.

### 3.3 Recuperar as passwords depois (se precisares)

```bash
sudo tar -O -xvf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt
```

### 3.4 Confirmar que os serviços estão ativos

```bash
sudo systemctl status wazuh-manager
sudo systemctl status wazuh-indexer
sudo systemctl status wazuh-dashboard
```

Todos devem mostrar `active (running)`.

---

## PARTE 4 — Aceder ao Dashboard

No browser do teu Windows:

```
https://192.168.1.150
```
(substitui pelo IP real da tua VM)

- Aparece aviso de certificado autoassinado → **Avançado → Continuar**
- Login: `admin` / a password do passo 3.2

Deves ver o Wazuh Dashboard vazio (ainda sem agentes).

---

## PARTE 5 — Instalar o Agente Wazuh no Windows

No teu Windows (ou noutra VM Windows que queiras monitorizar), **PowerShell como Administrador**:

```powershell
$installer = "$env:TEMP\wazuh-agent.msi"
Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.7-1.msi" -OutFile $installer

Start-Process msiexec.exe -Wait -ArgumentList @(
  "/i", $installer,
  "/q",
  "WAZUH_MANAGER=192.168.1.150",
  "WAZUH_AGENT_NAME=$env:COMPUTERNAME"
)

NET START WazuhSvc
```

Substitui `192.168.1.150` pelo IP real da tua VM Wazuh.

### Confirmar que o agente arrancou

```powershell
Get-Service *wazuh*
```

Deve mostrar `Running`.

### Portas necessárias

O agente comunica com o manager em:
- **1514/TCP** — envio de logs
- **1515/TCP** — registo inicial

Se tiveres firewall entre a VM e o Windows (Windows Defender Firewall no anfitrião, por exemplo), confirma que estas portas estão abertas na direção VM ↔ anfitrião.

---

## PARTE 6 — Validar

### 6.1 No Dashboard Wazuh

**Management → Endpoints** (ou "Agents", dependendo da versão) → deves ver o teu Windows listado como `Active`.

### 6.2 Gerar um evento de teste

No Windows, tenta fazer logon com password errada de propósito, ou corre:

```powershell
# Simula tentativa de logon falhada
runas /user:administrador cmd
# (introduz uma password errada de propósito)
```

### 6.3 Confirmar no Dashboard

**Threat Hunting → Security Events** → filtra por `rule.id: 60122` ou pesquisa `4625` → deve aparecer o evento em segundos.

---

## PARTE 7 — Ligar ao Teu Projeto Existente

O teu `log_analyzer_real.py` já sabe interpretar os mesmos Event IDs (4625, 4672, 4698, 4726, etc.) que o Wazuh está agora a receber em tempo real. Duas formas de os juntar:

### Opção A — Exportar do Wazuh e analisar com o teu script
O Wazuh guarda os logs brutos em `/var/ossec/logs/archives/archives.json` no servidor. Podes copiar esse ficheiro e adaptar o parser JSON do teu script para o ler.

### Opção B — Consultar a API do Wazuh diretamente (mais robusto)
O Wazuh expõe uma API REST (porta 55000) de onde consegues pedir alertas diretamente em JSON, sem precisar de exportar manualmente. Esta é a base natural para a **Fase 2 (Dashboard Web)** — o teu backend FastAPI pode consultar esta API e usar a mesma lógica de classificação que já construíste.

Isto é o próximo passo lógico depois de validares que o laboratório está a funcionar.

---

## 🐛 Troubleshooting

**VM não arranca da ISO**
→ Confirma que Secure Boot está desativado (Parte 2.3)

**`wazuh-install.sh` falha por falta de RAM**
→ Sobe a VM para pelo menos 8GB. Com menos, o Indexer (OpenSearch) não arranca de forma fiável.

**Dashboard não carrega no browser**
→ Confirma que consegues fazer `ping <IP_da_VM>` a partir do Windows
→ Confirma o serviço: `sudo systemctl status wazuh-dashboard`

**Agente Windows instala mas não aparece "Active" no Dashboard**
→ Verifica se o IP do `WAZUH_MANAGER` está correto
→ Testa conectividade: `Test-NetConnection 192.168.1.150 -Port 1514`
→ Reinicia o serviço: `Restart-Service WazuhSvc`

**"Access Denied" ao correr comandos PowerShell**
→ Confirma que abriste o PowerShell como Administrador

---

## 📋 Checklist de Progresso

- [ ] Hyper-V ativado e Virtual Switch criado
- [ ] VM Ubuntu Server 22.04 criada e a correr
- [ ] SSH a funcionar a partir do Windows
- [ ] Wazuh instalado (`wazuh-install.sh -a`)
- [ ] Dashboard acessível via browser
- [ ] Agente Windows instalado
- [ ] Agente aparece "Active" no Dashboard
- [ ] Evento de teste (4625) visível no Threat Hunting

---

## 🚀 Próximo Passo

Depois de completares o checklist acima, o laboratório está pronto. A partir daqui os caminhos naturais são:

1. **API do Wazuh → Dashboard Web** (Fase 2 do projeto, agora com dados reais em vez de ficheiros estáticos)
2. **Regras personalizadas** — escrever regras Wazuh próprias que espelhem a lógica de deteção que já tens em `log_analyzer_real.py`
3. **Mais agentes** — adicionar uma segunda VM Windows para simular um pequeno domínio e gerar cenários de ataque mais realistas (brute force entre máquinas, movimento lateral)
