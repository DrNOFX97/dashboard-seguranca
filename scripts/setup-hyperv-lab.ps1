<#
.SYNOPSIS
    Automatiza a Parte 1 e Parte 2 do laboratorio Wazuh (ver LAB_WAZUH_HYPERV.md):
    ativa o Hyper-V, cria o Virtual Switch e cria a VM Ubuntu Server (sem instalar o SO).

.DESCRIPTION
    Corre no Windows anfitriao, como Administrador. O script para depois de criar a VM:
    a instalacao do Ubuntu Server em si (Parte 2.4 do guia) e interativa e tem de ser
    feita manualmente a partir da consola da VM (vmconnect / Hyper-V Manager).

.NOTES
    Se o Hyper-V ainda nao estava ativo, o script ativa a feature e para -- e preciso
    reiniciar o PC e voltar a correr o script para criar o switch e a VM.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    # Nome da VM a criar
    [string]$VMName = "WazuhLab-Ubuntu",

    # Nome do Virtual Switch (ver Parte 1.2 do guia)
    [string]$SwitchName = "Lab-Wazuh",

    # External = mesma sub-rede que o anfitriao (recomendado no guia); Internal = isolado
    [ValidateSet("External", "Internal", "Private")]
    [string]$SwitchType = "External",

    # Obrigatorio quando -SwitchType External: nome do adaptador de rede fisico a associar
    # (ver `Get-NetAdapter` para listar). Nao adivinhamos isto para nao desligar a tua rede.
    [string]$NetAdapterName,

    # Specs da VM (ver Parte 2.2 do guia)
    [int]$MemoryGB = 8,
    [int]$VCpuCount = 4,
    [int]$DiskSizeGB = 60,
    [int]$Generation = 2,

    # Por omissao usa os paths por defeito do Hyper-V host (Get-VMHost)
    [string]$VMPath,
    [string]$VHDPath,

    # Opcional: caminho para a ISO do Ubuntu Server 22.04. Se indicado, e montada e
    # definida como primeiro dispositivo de arranque. Se omitido, tens de montar
    # manualmente depois (Hyper-V Manager -> Settings -> DVD Drive).
    [string]$IsoPath
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-ManualStep {
    param([string]$Message)
    Write-Host "`n[MANUAL] $Message" -ForegroundColor Yellow
}

# --- 0. Tem de correr como Administrador ---------------------------------
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Este script tem de correr num PowerShell como Administrador. Abre o PowerShell com 'Executar como Administrador' e tenta de novo."
    exit 1
}

# --- 1. Verificar requisitos de virtualizacao de hardware ------------------
# Isto NAO e automatizavel: se a virtualizacao (VT-x/AMD-V) estiver desligada na
# BIOS/UEFI, tem de ser ativada manualmente la -- nao ha forma segura de o fazer
# a partir do sistema operativo.
Write-Step "A verificar requisitos de virtualizacao de hardware..."
$computerInfo = Get-ComputerInfo -Property HyperV*
if ($computerInfo.HyperVRequirementVirtualizationFirmwareEnabled -eq $false) {
    Write-ManualStep @"
A virtualizacao de hardware (Intel VT-x / AMD-V) parece estar DESLIGADA na firmware.
Isto tem de ser ativado manualmente na BIOS/UEFI do PC (normalmente em
Advanced -> CPU Configuration -> Virtualization Technology, ou semelhante) --
nao existe forma segura de o fazer a partir do Windows. Depois de ativar,
volta a correr este script.
"@
    exit 1
}

# --- 2. Verificar / ativar a feature do Hyper-V -----------------------------
Write-Step "A verificar se o Hyper-V ja esta ativo..."
$hyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All

if ($hyperVFeature.State -eq "Enabled") {
    Write-Host "Hyper-V ja esta ativo." -ForegroundColor Green
}
else {
    Write-Step "Hyper-V nao esta ativo -- a ativar (Enable-WindowsOptionalFeature)..."
    if ($PSCmdlet.ShouldProcess("Microsoft-Hyper-V", "Enable-WindowsOptionalFeature")) {
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart | Out-Null
    }
    Write-ManualStep @"
Hyper-V foi ativado mas precisa de REINICIAR O PC antes de continuar.
Depois de reiniciar, volta a correr este mesmo script -- ele vai saltar
este passo e continuar a partir da criacao do switch e da VM.
"@
    exit 0
}

# --- 3. Criar o Virtual Switch (Parte 1.2 do guia) --------------------------
Write-Step "A verificar o Virtual Switch '$SwitchName'..."
$existingSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue

if ($existingSwitch) {
    Write-Host "Virtual Switch '$SwitchName' ja existe (tipo: $($existingSwitch.SwitchType)) -- a reutilizar." -ForegroundColor Green
}
else {
    if ($SwitchType -eq "External" -and -not $NetAdapterName) {
        Write-Host "`nAdaptadores de rede disponiveis:" -ForegroundColor Yellow
        Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Format-Table Name, InterfaceDescription, Status -AutoSize
        Write-Error "Para -SwitchType External tens de indicar -NetAdapterName <nome> com um dos adaptadores acima. Isto nao e adivinhado automaticamente para nao desligar a tua ligacao de rede atual."
        exit 1
    }

    Write-Step "A criar Virtual Switch '$SwitchName' (tipo: $SwitchType)..."
    if ($PSCmdlet.ShouldProcess($SwitchName, "New-VMSwitch")) {
        if ($SwitchType -eq "External") {
            New-VMSwitch -Name $SwitchName -NetAdapterName $NetAdapterName -AllowManagementOS $true | Out-Null
        }
        else {
            New-VMSwitch -Name $SwitchName -SwitchType $SwitchType | Out-Null
        }
    }
    Write-Host "Virtual Switch '$SwitchName' criado." -ForegroundColor Green
}

# --- 4. Criar a VM (Parte 2.2 e 2.3 do guia) ---------------------------------
Write-Step "A verificar se a VM '$VMName' ja existe..."
$existingVM = Get-VM -Name $VMName -ErrorAction SilentlyContinue

if ($existingVM) {
    Write-Host "A VM '$VMName' ja existe -- nao vou recria-la nem alterar a sua configuracao. Apaga-a manualmente primeiro (Remove-VM) se quiseres recomecar do zero." -ForegroundColor Yellow
    exit 0
}

$vmHost = Get-VMHost
if (-not $VMPath) { $VMPath = $vmHost.VirtualMachinePath }
if (-not $VHDPath) { $VHDPath = Join-Path $vmHost.VirtualHardDiskPath "$VMName.vhdx" }

Write-Step "A criar a VM '$VMName' (Geracao $Generation, $MemoryGB GB RAM, $DiskSizeGB GB disco dinamico)..."
if ($PSCmdlet.ShouldProcess($VMName, "New-VM")) {
    New-VM -Name $VMName `
        -Generation $Generation `
        -MemoryStartupBytes ($MemoryGB * 1GB) `
        -NewVHDPath $VHDPath `
        -NewVHDSizeBytes ($DiskSizeGB * 1GB) `
        -SwitchName $SwitchName `
        -Path $VMPath | Out-Null

    Write-Step "A configurar vCPUs ($VCpuCount)..."
    Set-VMProcessor -VMName $VMName -Count $VCpuCount

    Write-Step "A desativar Secure Boot (necessario para arrancar a ISO do Ubuntu em Geracao 2)..."
    Set-VMFirmware -VMName $VMName -EnableSecureBoot Off

    if ($IsoPath) {
        if (-not (Test-Path $IsoPath)) {
            Write-Error "IsoPath '$IsoPath' nao encontrado. A VM foi criada, mas sem ISO montada -- monta-a manualmente."
        }
        else {
            Write-Step "A montar a ISO do Ubuntu ($IsoPath) e a definir como primeiro dispositivo de arranque..."
            $dvdDrive = Add-VMDvdDrive -VMName $VMName -Path $IsoPath -Passthru
            Set-VMFirmware -VMName $VMName -FirstBootDevice $dvdDrive
        }
    }
}

Write-Host "`nVM '$VMName' criada com sucesso." -ForegroundColor Green

# --- 5. Proximos passos (manuais) -------------------------------------------
Write-ManualStep @"
A VM esta criada mas o Ubuntu Server ainda NAO esta instalado -- isso e
interativo e tem de ser feito a mao (ver Parte 2.4 de LAB_WAZUH_HYPERV.md):

  1. Se nao passaste -IsoPath, monta a ISO do Ubuntu Server 22.04 manualmente:
     Hyper-V Manager -> $VMName -> Settings -> DVD Drive -> aponta para o .iso
  2. Arranca a VM e liga por consola:
     Start-VM -Name $VMName
     vmconnect.exe localhost $VMName
  3. Segue o instalador do Ubuntu (idioma, rede DHCP, disco inteiro,
     utilizador, e marca 'Install OpenSSH server' -- essencial).
  4. Depois de instalado e reiniciado, confirma o IP com 'ip a' na consola
     e liga por SSH a partir do Windows:
     ssh <utilizador>@<ip-da-vm>
  5. Copia scripts/install-wazuh.sh para dentro da VM e corre-o (Parte 3
     do guia) -- e o proximo passo automatizado desta serie.
"@
