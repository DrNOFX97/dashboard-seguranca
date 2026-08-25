# Scripts do Laboratório Wazuh

Automatizam o que é seguro automatizar do guia `LAB_WAZUH_HYPERV.md` (está na
raiz do repositório). Nenhum destes scripts corre sozinho — lê cada um antes
de correr, e corre-os na ordem abaixo.

## Ordem de execução

1. **`setup-hyperv-lab.ps1`** (Windows anfitrião, PowerShell como Admin)
   Ativa o Hyper-V (se preciso), cria o Virtual Switch `Lab-Wazuh` e cria a
   VM Ubuntu (Geração 2, 8GB RAM, 4 vCPU, 60GB). Para antes de instalar o SO.
2. *(manual — ver secção abaixo)* Instalar o Ubuntu Server na VM.
3. **`install-wazuh.sh`** (dentro da VM Ubuntu, via SSH)
   Atualiza o sistema, instala o Wazuh (quickstart, nó único) e confirma que
   os 3 serviços estão `active (running)`.
4. *(manual — ver secção abaixo)* Validar o acesso ao Wazuh Dashboard.
5. **`install-wazuh-agent.ps1`** (na máquina Windows a monitorizar, PowerShell como Admin)
   Instala e arranca o agente Wazuh, apontado para o IP do manager.
6. *(manual — ver secção abaixo)* Confirmar o agente "Active" e gerar um evento de teste.

## Passos que não são automatizáveis com segurança

Estes ficam mesmo a cargo do utilizador — não há forma segura (ou sequer
possível, a partir do SO) de os automatizar:

- **Ativar virtualização de hardware (Intel VT-x / AMD-V) na BIOS/UEFI.**
  É uma definição de firmware fora do alcance do sistema operativo.
  `setup-hyperv-lab.ps1` deteta se está desligada e para com instruções,
  mas não pode ativá-la por ti.
- **Reiniciar o PC depois de ativar a feature do Hyper-V.** O Windows exige
  reboot antes dos cmdlets de Hyper-V ficarem disponíveis; o script para e
  pede para correres de novo depois de reiniciar.
- **Escolher o adaptador de rede físico para o switch `External`.**
  `setup-hyperv-lab.ps1` recusa-se a adivinhar isto (`-NetAdapterName`
  obrigatório para `-SwitchType External`) — escolher o adaptador errado
  pode cortar a ligação de rede do anfitrião.
- **Instalação do Ubuntu Server (Parte 2.4 do guia).** É um instalador
  interativo (idioma, layout de disco, utilizador/password, checkbox do
  OpenSSH) — corre-se a partir da consola da VM (`vmconnect`), não por script.
- **Anotar o IP da VM e a primeira ligação SSH (Parte 2.5).** O IP só existe
  depois do Ubuntu instalado e a rede DHCP atribuída; confirma-se com `ip a`
  na consola da VM.
- **Primeira ligação ao Wazuh Dashboard no browser (Parte 4).** Inclui aceitar
  o aviso de certificado autoassinado e fazer login — ação manual no browser.
- **Validar o agente como "Active" e gerar/confirmar um evento de teste no
  Dashboard (Parte 6).** É verificação visual na UI do Wazuh, não algo que um
  script possa confirmar de forma fiável.
- **Regras de firewall de terceiros entre a VM e o anfitrião**, se as portas
  1514/1515 estiverem bloqueadas por algo além da Firewall do Windows padrão.
  `install-wazuh-agent.ps1` só reporta o estado do serviço, não mexe em
  configurações de firewall de rede que não controla.

Para os passos completos e o contexto de cada um, ver `LAB_WAZUH_HYPERV.md`
na raiz do repositório.
