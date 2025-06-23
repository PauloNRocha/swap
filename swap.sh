#!/bin/bash
# Version: 1.1.2


# Função para exibir mensagens com cores
msg() {
  local color=$1
  shift
  case $color in
    "red")    echo -e "\e[31m$*\e[0m" ;;
    "green")  echo -e "\e[32m$*\e[0m" ;;
    "yellow") echo -e "\e[33m$*\e[0m" ;;
    "blue")   echo -e "\e[34m$*\e[0m" ;;
  esac
}

# Verifica se é executado como root
if [ "$EUID" -ne 0 ]; then
  msg red "Este script deve ser executado como root."
  exit 1
fi
msg green "Verificação de root bem-sucedida!"

# Verifica se o sistema usa apt
if ! command -v apt &> /dev/null; then
  msg red "Este script é compatível apenas com sistemas baseados em Debian/Ubuntu (apt)."
  exit 1
fi

# Verifica conectividade com a internet
msg blue "Verificando conectividade com a internet..."
if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
  msg green "Conexão detectada. Atualizando o sistema..."
  if apt update > /dev/null 2>&1 && apt upgrade -y > /dev/null 2>&1 && apt autoremove -y > /dev/null 2>&1 && apt autoclean -y > /dev/null 2>&1; then
    msg green "Sistema atualizado com sucesso."
  else
    msg red "Erro ao atualizar o sistema. Verifique os repositórios."
  fi
else
  msg yellow "Sem conexão com a internet. Pulando atualização."
fi

# Detecta quantidade de RAM
msg blue "Detectando quantidade de RAM..."
total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
total_ram_mb=$((total_ram_kb / 1024))

# Define tamanho do swap com base na RAM
case $total_ram_mb in
  [0-1024])   swap_size="2G" ;;
  [1-2][0-9][0-9][0-9]) swap_size="4G" ;; # 1025-2999 MB
  [3-4][0-9][0-9][0-9]) swap_size="6G" ;; # 3000-4999 MB
  [5-8][0-9][0-9][0-9]) swap_size="8G" ;; # 5000-8999 MB
  1[0-6][0-9][0-9][0-9]) swap_size="16G" ;; # 10000-16999 MB
  *) swap_size="32G" ;; # >= 17000 MB
esac
msg green "RAM detectada: ${total_ram_mb}MB. Tamanho do swap: $swap_size."

# Verifica espaço em disco
msg blue "Verificando espaço em disco..."
swap_size_bytes=$(( ${swap_size%G} * 1024 * 1024 * 1024 ))
available_space_bytes=$(df --block-size=1 / | awk 'NR==2 {print $4}')

if [ "$available_space_bytes" -lt "$swap_size_bytes" ]; then
  msg red "Espaço insuficiente para criar swap de $swap_size."
  exit 1
fi
msg green "Espaço suficiente detectado."

# Gerencia arquivo de swap
msg blue "Verificando swap existente..."
if swapon --show | grep -q '/swapfile'; then
  current_swap_size=$(swapon --show --bytes | grep '/swapfile' | awk '{print $3}')
  if [ "$current_swap_size" -lt "$swap_size_bytes" ]; then
    msg yellow "Swap existente é menor. Recriando..."
    swapoff /swapfile && rm /swapfile &&
    fallocate -l "$swap_size" /swapfile && chmod 600 /swapfile &&
    mkswap /swapfile > /dev/null 2>&1 && swapon /swapfile
    msg green "Arquivo de swap recriado."
  else
    msg green "Swap existente é suficiente."
  fi
else
  msg blue "Criando novo arquivo de swap..."
  fallocate -l "$swap_size" /swapfile &&
  chmod 600 /swapfile &&
  mkswap /swapfile > /dev/null 2>&1 &&
  swapon /swapfile
  msg green "Arquivo de swap criado."
fi

# Configura /etc/fstab
msg blue "Configurando /etc/fstab..."
backup_fstab="/etc/fstab.backup.$(date +%Y-%m-%d_%H-%M-%S)"
if cp /etc/fstab "$backup_fstab"; then
  msg green "Backup do /etc/fstab criado em $backup_fstab."
else
  msg red "Erro ao criar backup do /etc/fstab."
  exit 1
fi
if grep -q '/swapfile' /etc/fstab; then
  msg green "Swap já configurado no /etc/fstab."
else
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  msg green "Swap adicionado ao /etc/fstab."
fi

# Configura parâmetros de desempenho
msg blue "Ajustando configurações de desempenho..."
backup_sysctl="/etc/sysctl.conf.backup.$(date +%Y-%m-%d_%H-%M-%S)"
if cp /etc/sysctl.conf "$backup_sysctl"; then
  msg green "Backup do /etc/sysctl.conf criado em $backup_sysctl."
else
  msg red "Erro ao criar backup do /etc/sysctl.conf."
  exit 1
fi

for param in "vm.swappiness=10" "vm.vfs_cache_pressure=50"; do
  if grep -q "^$param" /etc/sysctl.conf; then
    msg green "Parâmetro $param já configurado."
  else
    echo "$param" >> /etc/sysctl.conf
    msg green "Parâmetro $param adicionado."
  fi
done
sysctl vm.swappiness=10 > /dev/null
sysctl vm.vfs_cache_pressure=50 > /dev/null
msg green "Sistema configurado para melhor desempenho."

# Solicita reinício
msg blue "Deseja reiniciar agora? [s/N]: "
read -r resposta
case $resposta in
  [Ss]*)
    msg blue "Reiniciando o sistema em 15 segundos..."
    for ((i=15; i>=1; i--)); do
      echo -ne "\rReiniciando em $i segundos..."
      sleep 1
    done
    msg blue "\nReiniciando agora..."
    reboot
    ;;
  *)
    msg yellow "Reinício cancelado."
    exit 0
    ;;
esac