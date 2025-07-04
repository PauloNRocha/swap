#!/bin/bash

set -euo pipefail # Falha imediata em caso de erro

# ==============================================================================
# CONFIGURAÇÃO E VARIÁVEIS GLOBAIS
# ==============================================================================
SCRIPT_VERSION=1.5.0
LOG_FILE="/var/log/swap_script.log"
LOG_ENABLED=false

# Definir cores
GREEN='\e[32m'
NC='\e[0m'

# ==============================================================================
# DEFINIÇÃO DE FUNÇÕES
# ==============================================================================

# Função para exibir mensagens com cores (usada por log_msg)
_msg() {
  local color=$1
  shift
  case $color in
  "red") echo -e "\e[31m$*\e[0m" ;;
  "green") echo -e "\e[32m$*\e[0m" ;;
  "yellow") echo -e "\e[33m$*\e[0m" ;;
  "blue") echo -e "\e[34m$*\e[0m" ;;
  *) echo "$*" ;;
  esac
}

# Função para registrar mensagens em log e no console
log_msg() {
  local color="$1"
  shift
  local message="$*"
  local timestamp
  timestamp=$(date "+%Y-%m-%d %H:%M:%S")

  # Exibe a mensagem no console
  _msg "$color" "$message"

  # Grava a mensagem no arquivo de log
  if [[ "$LOG_ENABLED" = true ]]; then
    # Remove códigos de cor antes de salvar no log
    local plain_message
    plain_message=$(echo "$message" | sed 's/\x1b\[[0-9;]*m//g')
    echo "[$timestamp] [$color] $plain_message" >>"$LOG_FILE"
  fi
}

# Função para converter tamanho (ex: 2G, 512M) para bytes
parse_size_to_bytes() {
  local size_str="$1"
  local size_bytes
  local num
  local unit

  if [[ ! "$size_str" =~ ^([0-9]+)([GgMm])$ ]]; then
    error_exit "Formato de tamanho inválido: '$size_str'. Use um número seguido por 'G' ou 'M' (ex: 4G, 512M)."
  fi

  num=$(echo "$size_str" | sed -E 's/([0-9]+)([GgMm])/\1/')
  unit=$(echo "$size_str" | sed -E 's/([0-9]+)([GgMm])/\2/' | tr '[:upper:]' '[:lower:]')

  if [[ "$unit" == "g" ]]; then
    size_bytes=$((num * 1024 * 1024 * 1024))
  elif [[ "$unit" == "m" ]]; then
    size_bytes=$((num * 1024 * 1024))
  fi

  echo "$size_bytes"
}

# Exibir banner sempre que iniciar
exibir_banner() {
  echo -e "${GREEN}"
  cat <<EOF
███████╗██╗    ██╗ █████╗ ██████╗
██╔════╝██║    ██║██╔══██╗██╔══██╗
███████╗██║ █╗ ██║███████║██████╔╝
╚════██║██║███╗██║██╔══██║██╔═══╝
███████║╚███╔███╔╝██║  ██║██║
╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝
EOF
  echo -e "${NC}"
  log_msg green "Script de configuração de SWAP versão ${SCRIPT_VERSION}"
  log_msg green "Desenvolvido por Paulo Rocha + IA\n"
}

# Função para exibir o menu de ajuda
exibir_ajuda() {
  echo "Uso: $0 [opções]"
  echo "Opções:"
  echo "  --size <tamanho>  Define o tamanho do swap (ex: 2G, 512M)"
  echo "  --help            Exibe este menu de ajuda"
  exit 0
}

# Função de limpeza para reverter alterações
cleanup() {
  log_msg yellow "Executando limpeza..."
  if [[ -n "${swap_file_incomplete-}" && -f "$swap_file_incomplete" ]]; then
    rm -f "$swap_file_incomplete"
    log_msg yellow "Arquivo de swap incompleto removido."
  fi
}

# Função para tratamento de erros
error_exit() {
  log_msg red "ERRO: $1"
  exit 1
}

# Trap para chamar a função de limpeza em caso de erro ou interrupção
trap 'cleanup' EXIT

# Função para validar se um comando existe
check_command() {
  command -v "$1" >/dev/null 2>&1 || error_exit "Comando '$1' não encontrado"
}

# Função para criar backup de um arquivo
backup_file() {
  local file_path="$1"
  if [[ -f "$file_path" ]]; then
    local backup_path="${file_path}.backup.$(date +%Y%m%d_%H%M%S)"
    if cp "$file_path" "$backup_path"; then
      log_msg green "✓ Backup de $file_path criado em $backup_path"
      return 0
    else
      error_exit "Falha ao criar backup de $file_path"
    fi
  fi
  return 1
}

# Função para criar o arquivo de swap
create_swap_file() {
  local size_str="$1"
  local file_path="$2"
  local size_mb

  log_msg blue "Criando arquivo de swap com tamanho $size_str..."
  swap_file_incomplete="$file_path" # Marca o arquivo para limpeza em caso de falha

  if fallocate -l "$size_str" "$file_path" >/dev/null 2>&1; then
    log_msg green "✓ Arquivo de swap criado com fallocate."
  else
    log_msg yellow "fallocate não suportado ou falhou. Usando dd como alternativa (pode ser mais lento)..."
    
    if [[ "$size_str" == *[Gg] ]]; then
      size_mb=$(echo "$size_str" | sed -E 's/([0-9]+)[Gg]/\1/')
      size_mb=$((size_mb * 1024))
    else
      size_mb=$(echo "$size_str" | sed -E 's/([0-9]+)[Mm]/\1/')
    fi

    if dd if=/dev/zero of="$file_path" bs=1M count="$size_mb" status=none >/dev/null 2>&1; then
      log_msg green "✓ Arquivo de swap criado com dd."
    else
      error_exit "Falha ao criar arquivo de swap com dd"
    fi
  fi

  chmod 600 "$file_path"
  mkswap "$file_path" >/dev/null 2>&1
  swapon "$file_path"
  swap_file_incomplete="" # Desmarca o arquivo após sucesso
}

# ==============================================================================
# LÓGICA PRINCIPAL
# ==============================================================================

exibir_banner

# Tenta configurar o log
if touch "$LOG_FILE" &>/dev/null; then
  LOG_ENABLED=true
  log_msg blue "Log habilitado. As saídas serão salvas em $LOG_FILE"
else
  log_msg yellow "Aviso: Não foi possível escrever em '$LOG_FILE'. O log estará desabilitado."
fi

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
    error_exit "Opção inválida: $1. Use --help para ver as opções."
    ;;
  esac
done

# Verifica se é executado como root
if [[ $EUID -ne 0 ]]; then
  error_exit "Este script deve ser executado como root (use sudo)."
fi
log_msg green "✓ Verificação de privilégios administrativos bem-sucedida!"

# Verifica comandos necessários
log_msg blue "Verificando dependências..."
for cmd in apt ping grep awk df fallocate mkswap swapon swapoff; do
  check_command "$cmd"
done
log_msg green "✓ Todas as dependências estão disponíveis."

# Verifica se o sistema usa apt
if ! command -v apt &>/dev/null; then
  error_exit "Este script é compatível apenas com sistemas baseados em Debian/Ubuntu (apt)."
fi

# Detecta quantidade de RAM
log_msg blue "Detectando quantidade de RAM..."
if [[ ! -r /proc/meminfo ]]; then
  error_exit "Não foi possível ler informações de memória."
}

total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
if [[ -z "$total_ram_kb" || ! "$total_ram_kb" =~ ^[0-9]+$ ]]; then
  error_exit "Não foi possível detectar a quantidade de RAM."
}

total_ram_mb=$((total_ram_kb / 1024))

# Define tamanho do swap
if [[ -n "$custom_swap_size" ]]; then
  # Valida o formato do tamanho antes de usar
  parse_size_to_bytes "$custom_swap_size" >/dev/null
  swap_size="$custom_swap_size"
  log_msg blue "Tamanho do swap definido pelo usuário: $swap_size"
else
  if [[ $total_ram_mb -le 512 ]]; then swap_size="1G"
  elif [[ $total_ram_mb -le 1024 ]]; then swap_size="2G"
  elif [[ $total_ram_mb -le 2048 ]]; then swap_size="3G"
  elif [[ $total_ram_mb -le 4096 ]]; then swap_size="4G"
  elif [[ $total_ram_mb -le 8192 ]]; then swap_size="6G"
  elif [[ $total_ram_mb -le 16384 ]]; then swap_size="8G"
  else swap_size="16G"
  fi
  log_msg green "✓ RAM detectada: ${total_ram_mb}MB. Tamanho do swap proposto: ${swap_size}."
fi

# Converte o tamanho do swap (string) para bytes (integer)
swap_size_bytes=$(parse_size_to_bytes "$swap_size")

# Verifica espaço em disco
log_msg blue "Verificando espaço em disco..."
available_space_bytes=$(df --block-size=1 / | awk 'NR==2 {print $4}')
required_space=$((swap_size_bytes + swap_size_bytes / 5 + 1024 * 1024 * 1024))

if [[ $available_space_bytes -lt $required_space ]]; then
  available_gb=$((available_space_bytes / 1024 / 1024 / 1024))
  required_gb=$((required_space / 1024 / 1024 / 1024))
  error_exit "Espaço insuficiente. Disponível: ${available_gb}GB, Necessário: ${required_gb}GB"
fi
log_msg green "✓ Espaço em disco suficiente."

# Desativa outras partições swap do tipo partition
log_msg blue "Verificando partições de swap ativas..."
if swapon --show=NAME,TYPE --noheadings 2>/dev/null | grep -q "partition"; then
  log_msg yellow "Desativando partições de swap ativas..."

  backup_file "/etc/fstab"

  while IFS= read -r line; do
    dev=$(echo "$line" | awk '$2 == "partition" { print $1 }')
    if [[ -n "$dev" && "$dev" != "/swapfile" ]]; then
      if swapoff "$dev" 2>/dev/null; then
        log_msg yellow "✓ Swap desativado: $dev"

        uuid=$(blkid -s UUID -o value "$dev" 2>/dev/null || true)
        if [[ -n "$uuid" ]]; then
          sed -i "/UUID=$uuid.*swap/d" /etc/fstab
          log_msg yellow "✓ Entrada UUID removida do fstab"
        fi

        device_name=$(basename "$dev")
        sed -i "/${device_name}.*swap/d" /etc/fstab
        log_msg yellow "✓ Entrada do dispositivo removida do fstab"
      else
        log_msg yellow "⚠ Não foi possível desativar swap: $dev"
      fi
    fi
  done < <(swapon --show=NAME,TYPE --noheadings 2>/dev/null)
else
  log_msg green "✓ Nenhuma partição de swap ativa encontrada."
fi

# Gerencia arquivo de swap
log_msg blue "Verificando arquivo de swap existente..."
current_swap_info=$(swapon --show --bytes 2>/dev/null | grep '/swapfile' || true)

if [[ -n "$current_swap_info" ]]; then
  current_swap_size=$(echo "$current_swap_info" | awk '{print $3}')
  current_swap_gb=$((current_swap_size / 1024 / 1024 / 1024))

  if [[ $current_swap_size -lt $swap_size_bytes ]]; then
    log_msg yellow "Swap existente (${current_swap_gb}GB) é menor que o recomendado. Recriando..."

    if swapoff /swapfile && rm -f /swapfile; then
      create_swap_file "$swap_size" "/swapfile"
      log_msg green "✓ Arquivo de swap recriado com sucesso."
    else
      error_exit "Falha ao remover swap existente"
    fi
  else
    log_msg green "✓ Swap existente (${current_swap_gb}GB) é adequado."
  fi
else
  log_msg blue "Criando novo arquivo de swap..."

  if [[ -f /swapfile ]]; then
    log_msg yellow "Arquivo /swapfile existe mas não está ativo. Removendo..."
    rm -f /swapfile
  fi

  create_swap_file "$swap_size" "/swapfile"
  log_msg green "✓ Arquivo de swap criado e ativado com sucesso."
fi

# Configura /etc/fstab
log_msg blue "Configurando /etc/fstab..."
if ! grep -q '/swapfile' /etc/fstab; then
  backup_file "/etc/fstab"

  echo '/swapfile none swap sw 0 0' >>/etc/fstab
  log_msg green "✓ Swap adicionado ao /etc/fstab."
else
  log_msg green "✓ Swap já configurado no /etc/fstab."
fi

# Configura parâmetros de desempenho
log_msg blue "Ajustando configurações de desempenho..."

if [[ ! -f /etc/sysctl.conf ]]; then
  touch /etc/sysctl.conf
fi

backup_file "/etc/sysctl.conf"

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
    sed -i "s/^$param=.*/$param_line/" /etc/sysctl.conf
    log_msg green "✓ Parâmetro $param atualizado para $value."
  else
    echo "$param_line" >>/etc/sysctl.conf
    log_msg green "✓ Parâmetro $param=$value adicionado."
  fi

  sysctl "$param_line" >/dev/null 2>&1 || log_msg yellow "⚠ Aviso: Não foi possível aplicar $param_line imediatamente"
done

log_msg green "✓ Sistema configurado para melhor desempenho."

# Exibe resumo da configuração
log_msg blue "=== RESUMO DA CONFIGURAÇÃO ==="
log_msg green "RAM total: ${total_ram_mb}MB"
log_msg green "Swap configurado: $swap_size"
log_msg green "Swappiness: 10 (baixo uso de swap)"
log_msg green "VFS cache pressure: 50 (balanceado)"
log_msg blue "================================"

# Solicita reinício com validação de entrada
while true; do
  read -rp "$(_msg blue 'Deseja reiniciar o sistema agora para aplicar todas as configurações? [s/N]: ')" resposta
  resposta=${resposta,,} # Converte para minúscula
  if [[ "$resposta" =~ ^(s|sim|y|yes)$ ]]; then
    log_msg blue "Reiniciando o sistema em 10 segundos..."
    log_msg yellow "Pressione Ctrl+C para cancelar..."
    for ((i = 10; i >= 1; i--)); do
      printf "\rReiniciando em %d segundos... " "$i"
      sleep 1
    done
    log_msg blue "\nReiniciando agora..."
    reboot
    break
  elif [[ "$resposta" =~ ^(n|nao|no)?$ ]]; then
    log_msg yellow "Reinício cancelado."
    log_msg blue "Para aplicar todas as configurações, reinicie o sistema manualmente:"
    log_msg green "sudo reboot"
    break
  else
    log_msg yellow "Entrada inválida. Use 's' para Sim ou 'n' para Não."
  fi
done
