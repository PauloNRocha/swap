#!/bin/bash


set -euo pipefail  # Falha imediata em caso de erro

# Definir cores
GREEN='\e[32m'
NC='\e[0m'

# Extrai a versão do próprio script
SCRIPT_VERSION=1.4.0

# Exibir banner sempre que iniciar
exibir_banner() {
  echo -e "${GREEN}"
  cat << "EOF"
███████╗██╗    ██╗ █████╗ ██████╗
██╔════╝██║    ██║██╔══██╗██╔══██╗
███████╗██║ █╗ ██║███████║██████╔╝
╚════██║██║███╗██║██╔══██║██╔═══╝
███████║╚███╔███╔╝██║  ██║██║
╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝
EOF
  echo -e "${NC}"
  echo -e "${GREEN}Script de configuração de SWAP versão ${SCRIPT_VERSION}${NC}"
  echo -e "${GREEN}Desenvolvido por Paulo Rocha + IA${NC}\n"
}

exibir_banner

# Função para exibir o menu de ajuda
exibir_ajuda() {
  echo "Uso: $0 [opções]"
  echo "Opções:"
  echo "  --size <tamanho>  Define o tamanho do swap (ex: 2G, 4G, 8G)"
  echo "  --help            Exibe este menu de ajuda"
  exit 0
}

# Processa argumentos da linha de comando
custom_swap_size=""
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --size)
      custom_swap_size="$2"
      shift 2
      ;;
    --help)
      exibir_ajuda
      ;;
    *)
      error_exit "Opção inválida: $1"
      ;;
  esac
done

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

# Função para tratamento de erros
error_exit() {
  msg red "ERRO: $1"
  cleanup # Chama a função de limpeza antes de sair
  exit 1
}

# Função de limpeza para reverter alterações
cleanup() {
  msg yellow "Executando limpeza..."
  # Adicione aqui comandos para reverter alterações, se necessário
  # Ex: remover arquivo de swap incompleto
  if [[ -n "${swap_file_incomplete-}" && -f "$swap_file_incomplete" ]]; then
    rm -f "$swap_file_incomplete"
    msg yellow "Arquivo de swap incompleto removido."
  fi
}

# Trap para chamar a função de limpeza em caso de erro ou interrupção
trap 'cleanup' EXIT

# Função para validar se um comando existe
check_command() {
  command -v "$1" >/dev/null 2>&1 || error_exit "Comando '$1' não encontrado"
}



# Verifica se é executado como root
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

# Verifica conectividade com a internet
msg blue "Verificando conectividade com a internet..."
internet_ok=false
if timeout 10 ping -c 2 8.8.8.8 >/dev/null 2>&1 || timeout 10 ping -c 2 1.1.1.1 >/dev/null 2>&1; then
  internet_ok=true
fi

if [ "$internet_ok" = true ]; then
  msg green "✓ Conexão detectada. Atualizando o sistema..."
  apt update >/dev/null 2>&1 || msg yellow "⚠ Aviso: Falha ao atualizar a lista de pacotes."
  apt upgrade -y >/dev/null 2>&1 || msg yellow "⚠ Aviso: Falha ao atualizar pacotes."
  apt autoremove -y >/dev/null 2>&1 || true
  apt autoclean -y >/dev/null 2>&1 || true
  msg green "✓ Sistema atualizado com sucesso."
else
  msg yellow "⚠ Sem conexão com a internet. Pulando atualização."
fi

# Detecta quantidade de RAM
msg blue "Detectando quantidade de RAM..."
if [[ ! -r /proc/meminfo ]]; then
  error_exit "Não foi possível ler informações de memória."
fi

total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
if [[ -z "$total_ram_kb" || ! "$total_ram_kb" =~ ^[0-9]+$ ]]; then
  error_exit "Não foi possível detectar a quantidade de RAM."
fi

total_ram_mb=$((total_ram_kb / 1024))

# Define tamanho do swap
if [[ -n "$custom_swap_size" ]]; then
  swap_size="$custom_swap_size"
  msg blue "Tamanho do swap definido pelo usuário: $swap_size"
else
  if [[ $total_ram_mb -le 512 ]]; then swap_size="1G"
  elif [[ $total_ram_mb -le 1024 ]]; then swap_size="2G"
  elif [[ $total_ram_mb -le 2048 ]]; then swap_size="3G"
  elif [[ $total_ram_mb -le 4096 ]]; then swap_size="4G"
  elif [[ $total_ram_mb -le 8192 ]]; then swap_size="6G"
  elif [[ $total_ram_mb -le 16384 ]]; then swap_size="8G"
  else swap_size="16G"
  fi
  msg green "✓ RAM detectada: ${total_ram_mb}MB. Tamanho do swap proposto: ${swap_size}."
fi

# Verifica espaço em disco
msg blue "Verificando espaço em disco..."
swap_size_bytes=$(( ${swap_size%G} * 1024 * 1024 * 1024 ))
available_space_bytes=$(df --block-size=1 / | awk 'NR==2 {print $4}')
required_space=$((swap_size_bytes + swap_size_bytes / 5 + 1024 * 1024 * 1024))

if [[ $available_space_bytes -lt $required_space ]]; then
  available_gb=$((available_space_bytes / 1024 / 1024 / 1024))
  required_gb=$((required_space / 1024 / 1024 / 1024))
  error_exit "Espaço insuficiente. Disponível: ${available_gb}GB, Necessário: ${required_gb}GB"
fi
msg green "✓ Espaço em disco suficiente."

# Função para criar backup de um arquivo
backup_file() {
  local file_path="$1"
  if [[ -f "$file_path" ]]; then
    local backup_path="${file_path}.backup.$(date +%Y%m%d_%H%M%S)"
    if cp "$file_path" "$backup_path"; then
      msg green "✓ Backup de $file_path criado em $backup_path"
      return 0
    else
      error_exit "Falha ao criar backup de $file_path"
    fi
  fi
  return 1
}

# Desativa outras partições swap do tipo partition
msg blue "Verificando partições de swap ativas..."
if swapon --show=NAME,TYPE --noheadings 2>/dev/null | grep -q "partition"; then
  msg yellow "Desativando partições de swap ativas..."

  backup_file "/etc/fstab"

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

# Função para criar o arquivo de swap
create_swap_file() {
  local size="$1"
  local file_path="$2"

  # Tenta usar fallocate primeiro
  if fallocate -l "$size" "$file_path" >/dev/null 2>&1; then
    msg green "✓ Arquivo de swap criado com fallocate."
  else
    msg yellow "fallocate não suportado ou falhou. Usando dd como alternativa (pode ser mais lento)..."
    # Converte o tamanho para MB para o dd
    local size_mb=${size%G}
    size_mb=$((size_mb * 1024))
    if dd if=/dev/zero of="$file_path" bs=1M count="$size_mb" status=progress >/dev/null 2>&1; then
      msg green "✓ Arquivo de swap criado com dd."
    else
      error_exit "Falha ao criar arquivo de swap com dd"
    fi
  fi

  chmod 600 "$file_path"
  mkswap "$file_path" >/dev/null 2>&1
  swapon "$file_path"
}

# Gerencia arquivo de swap
msg blue "Verificando arquivo de swap existente..."
current_swap_info=$(swapon --show --bytes 2>/dev/null | grep '/swapfile' || true)

if [[ -n "$current_swap_info" ]]; then
  current_swap_size=$(echo "$current_swap_info" | awk '{print $3}')
  current_swap_gb=$((current_swap_size / 1024 / 1024 / 1024))

  if [[ $current_swap_size -lt $swap_size_bytes ]]; then
    msg yellow "Swap existente (${current_swap_gb}GB) é menor que o recomendado. Recriando..."

    if swapoff /swapfile && rm -f /swapfile; then
      create_swap_file "$swap_size" "/swapfile"
      msg green "✓ Arquivo de swap recriado com sucesso."
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

  create_swap_file "$swap_size" "/swapfile"
  msg green "✓ Arquivo de swap criado e ativado com sucesso."
fi

# Configura /etc/fstab
msg blue "Configurando /etc/fstab..."
if ! grep -q '/swapfile' /etc/fstab; then
  backup_file "/etc/fstab"

  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  msg green "✓ Swap adicionado ao /etc/fstab."
else
  msg green "✓ Swap já configurado no /etc/fstab."
fi

# Configura parâmetros de desempenho
msg blue "Ajustando configurações de desempenho..."

if [[ ! -f /etc/sysctl.conf ]]; then
  touch /etc/sysctl.conf
fi

backup_file "/etc/sysctl.conf"

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
  read -rp "$(msg blue 'Deseja reiniciar o sistema agora para aplicar todas as configurações? [s/N]: ')" resposta
  resposta=${resposta,,} # Converte para minúscula
  if [[ "$resposta" =~ ^(s|sim|y|yes)$ ]]; then
    msg blue "Reiniciando o sistema em 10 segundos..."
    msg yellow "Pressione Ctrl+C para cancelar..."
    for ((i=10; i>=1; i--)); do
      printf "\rReiniciando em %d segundos... " "$i"
      sleep 1
    done
    msg blue "\nReiniciando agora..."
    reboot
    break
  elif [[ "$resposta" =~ ^(n|nao|no)?$ ]]; then
    msg yellow "Reinício cancelado."
    msg blue "Para aplicar todas as configurações, reinicie o sistema manualmente:"
    msg green "sudo reboot"
    break
  else
    msg yellow "Entrada inválida. Use 's' para Sim ou 'n' para Não."
  fi
done