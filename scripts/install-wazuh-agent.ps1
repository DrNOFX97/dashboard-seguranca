<#
.SYNOPSIS
    Automatiza a Parte 5 do laboratorio Wazuh (ver LAB_WAZUH_HYPERV.md):
    instala e arranca o agente Wazuh numa maquina Windows.

.DESCRIPTION
    Corre no Windows que queres monitorizar (o anfitriao ou outra VM Windows),
    como Administrador. Descarrega o MSI oficial, instala silenciosamente com
    o IP do manager, arranca o servico e confirma que ficou "Running".

.EXAMPLE
    .\install-wazuh-agent.ps1 -WazuhManagerIP 192.168.1.150
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    # IP da VM do Wazuh Manager (ver Parte 2.5 do guia)
    [Parameter(Mandatory = $true)]
    [string]$WazuhManagerIP,

    # Nome com que o agente aparece no Dashboard
    [string]$AgentName = $env:COMPUTERNAME,

    # Versao do instalador (ver https://packages.wazuh.com/4.x/windows/)
    [string]$AgentVersion = "4.14.7-1",

    # Reinstala mesmo que o servico WazuhSvc ja exista
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

# --- 0. Tem de correr como Administrador ---------------------------------
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Este script tem de correr num PowerShell como Administrador. Abre o PowerShell com 'Executar como Administrador' e tenta de novo."
    exit 1
}

# --- 1. Verificar se ja existe um agente instalado --------------------------
$existingService = Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue
if ($existingService -and -not $Force) {
    Write-Host "O servico 'WazuhSvc' ja existe (estado atual: $($existingService.Status)). Nao vou reinstalar por cima -- passa -Force se quiseres forcar a reinstalacao, ou desinstala o agente atual primeiro (Painel de Controlo -> Programas)." -ForegroundColor Yellow
    exit 0
}

# --- 2. Descarregar o instalador MSI (Parte 5 do guia) -----------------------
$installerUrl = "https://packages.wazuh.com/4.x/windows/wazuh-agent-${AgentVersion}.msi"
$installerPath = Join-Path $env:TEMP "wazuh-agent.msi"

Write-Step "A descarregar o agente Wazuh ${AgentVersion} de ${installerUrl}..."
if ($PSCmdlet.ShouldProcess($installerUrl, "Invoke-WebRequest")) {
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
}

# --- 3. Instalar silenciosamente ---------------------------------------------
Write-Step "A instalar o agente (manager=$WazuhManagerIP, nome=$AgentName)..."
if ($PSCmdlet.ShouldProcess($installerPath, "msiexec /i")) {
    $msiArgs = @(
        "/i", $installerPath,
        "/q",
        "WAZUH_MANAGER=$WazuhManagerIP",
        "WAZUH_AGENT_NAME=$AgentName"
    )
    $process = Start-Process msiexec.exe -Wait -ArgumentList $msiArgs -PassThru
    if ($process.ExitCode -ne 0) {
        Write-Error "msiexec terminou com exit code $($process.ExitCode). Consulta o Event Viewer (Application) para detalhes."
        exit 1
    }
}

# --- 4. Arrancar o servico ----------------------------------------------------
Write-Step "A arrancar o servico WazuhSvc..."
if ($PSCmdlet.ShouldProcess("WazuhSvc", "Start-Service")) {
    Start-Service -Name "WazuhSvc"
}

# --- 5. Confirmar que ficou "Running" (com retries, o arranque pode demorar) -
Write-Step "A confirmar o estado do servico..."
$service = $null
for ($i = 0; $i -lt 10; $i++) {
    $service = Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") { break }
    Start-Sleep -Seconds 2
}

Get-Service -Name "*wazuh*" | Format-Table Name, Status, DisplayName -AutoSize

if ($service -and $service.Status -eq "Running") {
    Write-Host "`nAgente Wazuh instalado e a correr." -ForegroundColor Green
}
else {
    Write-Error "O servico WazuhSvc nao ficou 'Running'. Verifica 'Get-Service WazuhSvc' e o Event Viewer (Application) para a causa."
    exit 1
}

Write-Host @"

[MANUAL] Ultimo passo (Parte 6 do guia):
  1. No Dashboard Wazuh (https://$WazuhManagerIP) -> Management -> Endpoints/Agents
     -> confirma que '$AgentName' aparece como 'Active'.
  2. Gera um evento de teste (ex: logon falhado de proposito) e confirma
     que aparece em Threat Hunting -> Security Events (rule.id 60122 / Event 4625).

Portas necessarias entre esta maquina e o manager: 1514/TCP (logs) e
1515/TCP (registo inicial). Se a ligacao falhar, testa com:
  Test-NetConnection $WazuhManagerIP -Port 1514
"@ -ForegroundColor Yellow
