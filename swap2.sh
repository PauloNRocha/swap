#!/bin/bash
# Script para configuração automática de swap
# Melhorado com tratamento de erros e validações adicionais

set -euo pipefail  # Falha imediata em caso de erro

# Versão do script (atualizada)
SCRIPT_VERSION="1.3.0"

# Definir cores
GREEN='\e[32m'
NC='\e[0m'

# Função para exibir o banner
exibir_banner() {
  echo -e "${GREEN}"
  echo "███████╗██╗    ██╗ █████╗ ██████╗ "
  echo "██╔════╝██║    ██║██╔══██╗██╔══██╗"
  echo "███████╗██║ █╗ ██║███████║██████╔╝"
  echo "╚════██║██║███╗██║██╔══██║██╔═══╝ "
  echo "███████║╚███╔███╔╝██║  ██║██║     "
  echo "╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝     "
  echo "                                  "
  echo -e "${NC}"
  echo -e "${GREEN}Script de configuração de SWAP versão ${SCRIPT_VERSION}${NC}"
  echo -e "${GREEN}Desenvolvido por Paulo Rocha + IA${NC}\n"
}

# Função para exibir mensagens com cores
msg() {
  local color=$1
  shift
  case $color in
    "red")    echo -e "\e[31m$*\e[0m" ;;
    "green")  echo -e "\e[32m$*\e[0m" ;;
    "yellow") echo -e "\e[33m$*\e[0m" ;;
    "blue")   echo -e "\e[34m$*\e[0m" ;;
    *)        echo "$*" ;;
  esac
}

# Função para exibir o menu principal
exibir_menu() {
  echo ""
  msg blue "O que você deseja?"
  echo ""
  msg yellow "1 - Atualizar sistema e configurar swap"
  msg yellow "2 - Configurar Swap"
  msg yellow "3 - Atualizar Sistema Operacional"
  msg yellow "4 - Sair"
  echo ""
  msg blue "Digite sua opção [1-4]: "
  read -r opcao
  echo ""
  
  case $opcao in
    1)
      msg green "✓ Opção selecionada: Atualizar sistema e configurar swap"
      return 1
      ;;
    2)
      msg green "✓ Opção selecionada: Configurar Swap"
      return 2
      ;;
    3)
      msg green "✓ Opção selecionada: Atualizar Sistema Operacional"
      return 3
      ;;
    4)
      msg yellow "Saindo do script..."
      exit 0
      ;;
    *)
      msg red "Opção inválida! Por favor, escolha uma opção entre 1 e 4."
      exibir_menu
      ;;
  esac
}
error_exit() {
  msg red "ERRO: $1"
  exit 1
}

# Função para validar se um comando existe
check_command() {
  command -v "$1" >/dev/null 2>&1 || error_exit "Comando '$1' não encontrado"
}

# Função para atualizar o sistema
atualizar_sistema() {
  # Verifica se é root para atualização
  if [[ $EUID -ne 0 ]]; then
    msg red "Para atualizar o sistema é necessário executar como root (use sudo)."
    return 1
  fi
  
  msg blue "Verificando conectividade com a internet..."
  if timeout 10 ping -c 2 8.8.8.8 >/dev/null 2>&1 || timeout 10 ping -c 2 1.1.1.1 >/dev/null 2>&1; then
    msg green "✓ Conexão detectada. Atualizando o sistema..."
    
    # Atualização do sistema com melhor tratamento de erros
    if ! apt update >/dev/null 2>&1; then
      msg yellow "⚠ Aviso: Falha ao atualizar a lista de pacotes. Continuando..."
    elif ! apt upgrade -y >/dev/null 2>&1; then
      msg yellow "⚠ Aviso: Falha ao atualizar pacotes. Continuando..."
    else
      msg green "✓ Sistema atualizado com sucesso."
      apt autoremove -y >/dev/null 2>&1 || true
      apt autoclean -y >/dev/null 2>&1 || true
    fi
  else
    msg yellow "⚠ Sem conexão com a internet. Não foi possível atualizar o sistema."
    return 1
  fi
}
validate_input() {
  local input="$1"
  if [[ ! "$input" =~ ^[SsNn]?$ ]]; then
    msg yellow "Entrada inválida. Use 's' para Sim ou 'n' para Não."
    return 1
  fi
  return 0
}

# Exibe o banner
exibir_banner

# Exibe o menu e captura a opção
exibir_menu
opcao_escolhida=$?

# Executa verificações apenas quando necessário
case $opcao_escolhida in
  1|2)
    # Para swap, precisa ser root obrigatoriamente
    if [[ $EUID -ne 0 ]]; then
      error_exit "Este script deve ser executado como root (use sudo)."
    fi
    msg green "✓ Verificação de privilégios administrativos bem-sucedida!"

    # Verifica comandos necessários
    msg blue "Verificando dependências..."
    for cmd in apt ping grep awk df fallocate mkswap swapon swapoff; do
      check_command "$cmd"
    done
    msg green "✓ Todas as dependências estão disponíveis."

    # Verifica se o sistema usa apt
    if ! command -v apt &> /dev/null; then
      error_exit "Este script é compatível apenas com sistemas baseados em Debian/Ubuntu (apt)."
    fi
    ;;
  3)
    # Para atualização, verifica comandos básicos
    msg blue "Verificando dependências..."
    for cmd in apt ping; do
      check_command "$cmd"
    done
    msg green "✓ Dependências básicas disponíveis."

    # Verifica se o sistema usa apt
    if ! command -v apt &> /dev/null; then
      error_exit "Este script é compatível apenas com sistemas baseados em Debian/Ubuntu (apt)."
    fi
    ;;
esac

# Executa a ação baseada na opção escolhida
case $opcao_escolhida in
  1)
    # Opção 1: Atualizar sistema e configurar swap
    atualizar_sistema
    # Continua para configurar swap (não precisa return/exit aqui)
    ;;
  2)
    # Opção 2: Apenas configurar swap
    msg blue "Pulando atualização do sistema..."
    ;;
  3)
    # Opção 3: Apenas atualizar sistema
    atualizar_sistema
    msg green "✓ Atualização do sistema concluída!"
    exit 0
    ;;
esac

# Detecta quantidade de RAM com validação
msg blue "Detectando quantidade de RAM..."
if [[ ! -r /proc/meminfo ]]; then
  error_exit "Não foi possível ler informações de memória."
fi

total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
if [[ ! "$total_ram_kb" =~ ^[0-9]+$ ]] || [[ $total_ram_kb -eq 0 ]]; then
  error_exit "Não foi possível detectar a quantidade de RAM."
fi

total_ram_mb=$((total_ram_kb / 1024))

# Lógica de dimensionamento de swap mais conservadora
if [[ $total_ram_mb -le 512 ]]; then
  swap_size="1G"
elif [[ $total_ram_mb -le 1024 ]]; then
  swap_size="2G"
elif [[ $total_ram_mb -le 2048 ]]; then
  swap_size="3G"
elif [[ $total_ram_mb -le 4096 ]]; then
  swap_size="4G"
elif [[ $total_ram_mb -le 8192 ]]; then
  swap_size="6G"
elif [[ $total_ram_mb -le 16384 ]]; then
  swap_size="8G"
else
  swap_size="16G"  # Máximo mais conservador
fi

msg green "✓ RAM detectada: ${total_ram_mb}MB. Tamanho do swap proposto: $swap_size."

# Verifica espaço em disco com margem de segurança
msg blue "Verificando espaço em disco..."
swap_size_bytes=$(( ${swap_size%G} * 1024 * 1024 * 1024 ))
available_space_bytes=$(df --block-size=1 / | awk 'NR==2 {print $4}')

# Margem de segurança de 20% + 1GB extra
required_space=$((swap_size_bytes + swap_size_bytes / 5 + 1024 * 1024 * 1024))

if [[ $available_space_bytes -lt $required_space ]]; then
  available_gb=$((available_space_bytes / 1024 / 1024 / 1024))
  required_gb=$((required_space / 1024 / 1024 / 1024))
  error_exit "Espaço insuficiente. Disponível: ${available_gb}GB, Necessário: ${required_gb}GB"
fi
msg green "✓ Espaço suficiente detectado."

# Desativa outras partições swap do tipo partition
msg blue "Verificando partições de swap ativas..."
if swapon --show=NAME,TYPE --noheadings 2>/dev/null | grep -q "partition"; then
  msg yellow "Desativando partições de swap ativas..."
  
  # Criar backup do fstab antes de modificar
  backup_fstab="/etc/fstab.backup.$(date +%Y%m%d_%H%M%S)"
  cp /etc/fstab "$backup_fstab" || error_exit "Falha ao criar backup do fstab"
  msg green "✓ Backup do fstab criado: $backup_fstab"
  
  while IFS= read -r line; do
    dev=$(echo "$line" | awk '$2 == "partition" { print $1 }')
    if [[ -n "$dev" && "$dev" != "/swapfile" ]]; then
      if swapoff "$dev" 2>/dev/null; then
        msg yellow "✓ Swap desativado: $dev"
        
        # Remove entradas do fstab com mais cuidado
        uuid=$(blkid -s UUID -o value "$dev" 2>/dev/null || true)
        if [[ -n "$uuid" ]]; then
          sed -i "/UUID=$uuid.*swap/d" /etc/fstab
          msg yellow "✓ Entrada UUID removida do fstab"
        fi
        
        device_name=$(basename "$dev")
        sed -i "/${device_name}.*swap/d" /etc/fstab
        msg yellow "✓ Entrada do dispositivo removida do fstab"
      else
        msg yellow "⚠ Não foi possível desativar swap: $dev"
      fi
    fi
  done < <(swapon --show=NAME,TYPE --noheadings 2>/dev/null)
else
  msg green "✓ Nenhuma partição de swap ativa encontrada."
fi

# Gerencia arquivo de swap
msg blue "Verificando arquivo de swap existente..."
current_swap_info=$(swapon --show --bytes 2>/dev/null | grep '/swapfile' || true)

if [[ -n "$current_swap_info" ]]; then
  current_swap_size=$(echo "$current_swap_info" | awk '{print $3}')
  current_swap_gb=$((current_swap_size / 1024 / 1024 / 1024))
  
  if [[ $current_swap_size -lt $swap_size_bytes ]]; then
    msg yellow "Swap existente (${current_swap_gb}GB) é menor que o recomendado. Recriando..."
    
    if swapoff /swapfile && rm -f /swapfile; then
      if fallocate -l "$swap_size" /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null 2>&1 && swapon /swapfile; then
        msg green "✓ Arquivo de swap recriado com sucesso."
      else
        error_exit "Falha ao criar novo arquivo de swap"
      fi
    else
      error_exit "Falha ao remover swap existente"
    fi
  else
    msg green "✓ Swap existente (${current_swap_gb}GB) é adequado."
  fi
else
  msg blue "Criando novo arquivo de swap..."
  
  # Verifica se já existe arquivo sem estar ativo
  if [[ -f /swapfile ]]; then
    msg yellow "Arquivo /swapfile existe mas não está ativo. Removendo..."
    rm -f /swapfile
  fi
  
  if fallocate -l "$swap_size" /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null 2>&1 && swapon /swapfile; then
    msg green "✓ Arquivo de swap criado e ativado com sucesso."
  else
    error_exit "Falha ao criar arquivo de swap"
  fi
fi

# Configura /etc/fstab
msg blue "Configurando /etc/fstab..."
if ! grep -q '/swapfile' /etc/fstab; then
  # Cria backup se ainda não foi criado
  if [[ ! -f "$backup_fstab" ]]; then
    backup_fstab="/etc/fstab.backup.$(date +%Y%m%d_%H%M%S)"
    cp /etc/fstab "$backup_fstab" || error_exit "Falha ao criar backup do fstab"
    msg green "✓ Backup do fstab criado: $backup_fstab"
  fi
  
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  msg green "✓ Swap adicionado ao /etc/fstab."
else
  msg green "✓ Swap já configurado no /etc/fstab."
fi

# Configura parâmetros de desempenho
msg blue "Ajustando configurações de desempenho..."
backup_sysctl="/etc/sysctl.conf.backup.$(date +%Y%m%d_%H%M%S)"

if [[ ! -f /etc/sysctl.conf ]]; then
  touch /etc/sysctl.conf
fi

if cp /etc/sysctl.conf "$backup_sysctl"; then
  msg green "✓ Backup do sysctl.conf criado: $backup_sysctl"
else
  error_exit "Falha ao criar backup do sysctl.conf"
fi

# Parâmetros de configuração
declare -A sysctl_params=(
  ["vm.swappiness"]="10"
  ["vm.vfs_cache_pressure"]="50"
  ["vm.dirty_ratio"]="15"
  ["vm.dirty_background_ratio"]="5"
)

for param in "${!sysctl_params[@]}"; do
  value="${sysctl_params[$param]}"
  param_line="$param=$value"
  
  if grep -q "^$param=" /etc/sysctl.conf; then
    # Atualiza valor existente
    sed -i "s/^$param=.*/$param_line/" /etc/sysctl.conf
    msg green "✓ Parâmetro $param atualizado para $value."
  else
    # Adiciona novo parâmetro
    echo "$param_line" >> /etc/sysctl.conf
    msg green "✓ Parâmetro $param=$value adicionado."
  fi
  
  # Aplica imediatamente
  sysctl "$param_line" >/dev/null 2>&1 || msg yellow "⚠ Aviso: Não foi possível aplicar $param_line imediatamente"
done

msg green "✓ Sistema configurado para melhor desempenho."

# Exibe resumo da configuração
msg blue "=== RESUMO DA CONFIGURAÇÃO ==="
msg green "RAM total: ${total_ram_mb}MB"
msg green "Swap configurado: $swap_size"
msg green "Swappiness: 10 (baixo uso de swap)"
msg green "VFS cache pressure: 50 (balanceado)"
msg blue "================================"

# Solicita reinício com validação de entrada
while true; do
  msg blue "Deseja reiniciar o sistema agora para aplicar todas as configurações? [s/N]: "
  read -r resposta
  
  if validate_input "$resposta"; then
    break
  fi
done

case ${resposta,,} in  # Converte para minúscula
  s|sim|y|yes)
    msg blue "Reiniciando o sistema em 10 segundos..."
    msg yellow "Pressione Ctrl+C para cancelar..."
    
    for ((i=10; i>=1; i--)); do
      printf "\rReiniciando em %d segundos... " "$i"
      sleep 1
    done
    
    msg blue "\nReiniciando agora..."
    reboot
    ;;
  *)
    msg yellow "Reinício cancelado."
    msg blue "Para aplicar todas as configurações, reinicie o sistema manualmente:"
    msg green "sudo reboot"
    exit 0
    ;;
esac