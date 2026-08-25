#!/usr/bin/env bash
#
# Automatiza a Parte 3 do laboratorio Wazuh (ver LAB_WAZUH_HYPERV.md):
# instala o Wazuh (Manager + Indexer + Dashboard) num no unico, via o
# script oficial de quickstart, e confirma que os 3 servicos arrancaram.
#
# Corre DENTRO da VM Ubuntu Server, depois do SO instalado (Parte 2.4) e
# de teres ligado por SSH. Precisa de sudo.
#
#   chmod +x install-wazuh.sh
#   ./install-wazuh.sh
#
set -euo pipefail

# --- Parametros ajustaveis --------------------------------------------------
WAZUH_VERSION="4.14"
WAZUH_INSTALL_URL="https://packages.wazuh.com/${WAZUH_VERSION}/wazuh-install.sh"
WAZUH_INSTALL_SCRIPT="wazuh-install.sh"
WAZUH_INSTALL_FILES_TAR="wazuh-install-files.tar"
WAZUH_SERVICES=("wazuh-manager" "wazuh-indexer" "wazuh-dashboard")

log() { echo -e "\n==> $*"; }
manual() { echo -e "\n[MANUAL] $*"; }

if [[ "$(id -u)" -eq 0 ]]; then
    echo "Nao corras este script diretamente como root -- corre como o teu utilizador normal, o script usa 'sudo' onde precisa." >&2
    exit 1
fi

# --- 1. Atualizar o sistema (Parte 3.1) -------------------------------------
log "A atualizar o sistema (apt update && apt upgrade)..."
sudo apt update
sudo apt upgrade -y

# --- 2. Instalar o Wazuh (Parte 3.2) ----------------------------------------
if systemctl list-unit-files 2>/dev/null | grep -q '^wazuh-manager'; then
    log "O Wazuh ja parece estar instalado (existe o servico wazuh-manager) -- a saltar a instalacao."
else
    log "A descarregar o instalador oficial do Wazuh ${WAZUH_VERSION}..."
    curl -sO "${WAZUH_INSTALL_URL}"

    log "A correr o instalador (quickstart, no unico) -- isto demora 10-15 minutos..."
    sudo bash "./${WAZUH_INSTALL_SCRIPT}" -a --install-dependencies
fi

# --- 3. Mostrar as passwords geradas (Parte 3.3) ----------------------------
log "Passwords geradas pelo instalador (guarda-as agora, nao sao faceis de recuperar depois):"
if [[ -f "${WAZUH_INSTALL_FILES_TAR}" ]]; then
    sudo tar -O -xvf "${WAZUH_INSTALL_FILES_TAR}" wazuh-install-files/wazuh-passwords.txt
else
    echo "Nao encontrei '${WAZUH_INSTALL_FILES_TAR}' na pasta atual. Se a instalacao ja tinha sido feita antes noutro diretorio, procura o ficheiro la, ou consulta a documentacao do Wazuh para gerar novas passwords." >&2
fi

# --- 4. Confirmar que os 3 servicos estao ativos (Parte 3.4) ----------------
log "A confirmar o estado dos servicos..."
all_active=true
for service in "${WAZUH_SERVICES[@]}"; do
    if sudo systemctl is-active --quiet "${service}"; then
        echo "  [OK]     ${service}: active (running)"
    else
        echo "  [FALHOU] ${service}: $(sudo systemctl is-active "${service}" 2>/dev/null || echo 'unknown')"
        all_active=false
    fi
done

if [[ "${all_active}" == true ]]; then
    log "Os 3 servicos (manager, indexer, dashboard) estao 'active (running)'."
else
    echo "Pelo menos um servico nao esta ativo -- corre 'sudo systemctl status <servico>' e 'sudo journalctl -u <servico>' para investigar antes de continuar." >&2
    exit 1
fi

manual "Proximos passos (Parte 4 e 5 do guia, manuais):

  1. No browser do Windows anfitriao, abre https://<IP-desta-VM>
     (aviso de certificado autoassinado -> Avancado -> Continuar)
     Login: admin / password mostrada acima.
  2. Confirma no Dashboard que aparece vazio (ainda sem agentes).
  3. A partir do Windows anfitriao (ou da maquina que queres monitorizar),
     corre scripts/install-wazuh-agent.ps1 -WazuhManagerIP <IP-desta-VM>
     -- e o proximo passo automatizado desta serie.
"
