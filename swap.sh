#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo -e "\e[31mEste script deve ser executado como root ou com permissões de root.\e[0m"
  exit 1
fi
echo -e "\n\e[32mVerificação de root bem-sucedida! Continuando a execução do script...\e[0m\n"
sleep 2

echo -e "\e[34mVerificando conectividade com a internet...\e[0m\n"
sleep 1
if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
  echo -e "\e[32mConexão com a internet detectada. Continuando para atualização do sistema...\e[0m\n"
  sleep 2
  echo -e "\e[34mAtualizando seu sistema...\e[0m\n"
  apt update > /dev/null 2>&1 && apt upgrade -y > /dev/null 2>&1 && apt autoremove -y > /dev/null 2>&1 && apt autoclean -y > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "\e[32mSistema atualizado com sucesso.\e[0m\n"
  else
    echo -e "\e[31mErro ao atualizar o sistema. Verifique sua configuração de repositórios.\e[0m\n"
  fi
else
  echo -e "\e[31mNenhuma conexão com a internet detectada. Pulando a etapa de atualização do sistema.\e[0m\n"
fi
sleep 2

echo -e "\e[34mDetectando quantidade de RAM disponível...\e[0m\n"
sleep 1
total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
total_ram_mb=$((total_ram_kb / 1024))

if [ "$total_ram_mb" -le 1024 ]; then
  swap_size="2G"
elif [ "$total_ram_mb" -le 2048 ]; then
  swap_size="4G"
elif [ "$total_ram_mb" -le 4096 ]; then
  swap_size="6G"
elif [ "$total_ram_mb" -le 8192 ]; then
  swap_size="8G"
elif [ "$total_ram_mb" -le 16384 ]; then
  swap_size="16G"
else
  swap_size="32G"
fi
echo -e "\e[32mRAM detectada: ${total_ram_mb}MB. Tamanho do swap definido para: $swap_size.\e[0m\n"
sleep 2

echo -e "\e[34mVerificando espaço disponível em disco...\e[0m\n"
sleep 1
swap_size_bytes=$(( ${swap_size%G} * 1024 * 1024 * 1024 ))
available_space_bytes=$(df --block-size=1 / | awk 'NR==2 {print $4}')

if [ "$available_space_bytes" -lt "$swap_size_bytes" ]; then
  echo -e "\e[31mEspaço insuficiente em disco para criar um arquivo de swap de $swap_size. Operação abortada.\e[0m\n"
  exit 1
else
  echo -e "\e[32mEspaço suficiente detectado para criar o arquivo de swap.\e[0m\n"
fi
sleep 2

echo -e "\e[34mVerificando swap existente...\e[0m\n"
sleep 1
if swapon --show | grep -q '/swapfile'; then
  atual_swap_size=$(swapon --show --bytes | grep '/swapfile' | awk '{print $3}')
  if [ "$atual_swap_size" -lt "$swap_size_bytes" ]; then
    echo -e "\e[33mSwap existente é menor do que o necessário. Recriando...\e[0m\n"
    sleep 2
    swapoff /swapfile > /dev/null 2>&1
    rm /swapfile > /dev/null 2>&1
    fallocate -l $swap_size /swapfile > /dev/null 2>&1
    chmod 600 /swapfile > /dev/null 2>&1
    mkswap /swapfile > /dev/null 2>&1
    swapon /swapfile > /dev/null 2>&1
    echo -e "\e[32mArquivo de swap recriado com sucesso.\e[0m\n"
  else
    echo -e "\e[32mSwap existente é suficiente. Nenhuma alteração necessária.\e[0m\n"
  fi
else
  echo -e "\e[34mNenhum swap detectado. Criando novo arquivo de swap...\e[0m\n"
  sleep 2
  fallocate -l $swap_size /swapfile > /dev/null 2>&1
  chmod 600 /swapfile > /dev/null 2>&1
  mkswap /swapfile > /dev/null 2>&1
  swapon /swapfile > /dev/null 2>&1
  echo -e "\e[32mArquivo de swap criado com sucesso.\e[0m\n"
fi
sleep 2

echo -e "\e[34mConfigurando o /etc/fstab para montagem automática do swap...\e[0m\n"
sleep 1
backup_fstab="/etc/fstab.backup.$(date +'%Y-%m-%d_%H-%M-%S')"
cp /etc/fstab "$backup_fstab" > /dev/null 2>&1
echo -e "\e[32mBackup do /etc/fstab criado em $backup_fstab.\e[0m\n"
sleep 1
if grep -q '/swapfile' /etc/fstab; then
  echo -e "\e[32mConfiguração de swap já existente no /etc/fstab. Pulando...\e[0m\n"
else
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo -e "\e[32mConfiguração adicionada ao /etc/fstab.\e[0m\n"
fi
sleep 2

echo -e "\e[34mAjustando parâmetros de desempenho do sistema...\e[0m\n"
sleep 1
backup_sysctl="/etc/sysctl.conf.backup.$(date +'%Y-%m-%d_%H-%M-%S')"
cp /etc/sysctl.conf "$backup_sysctl" > /dev/null 2>&1
echo -e "\e[32mBackup do /etc/sysctl.conf criado em $backup_sysctl.\e[0m\n"
sleep 1

if grep -q 'vm.swappiness=10' /etc/sysctl.conf; then
  echo -e "\e[32mAjuste 'vm.swappiness=10' já existe no /etc/sysctl.conf. Pulando...\e[0m\n"
else
  echo 'vm.swappiness=10' >> /etc/sysctl.conf
  echo -e "\e[32mAjuste 'vm.swappiness=10' adicionado ao /etc/sysctl.conf.\e[0m\n"
fi
sleep 1

if grep -q 'vm.vfs_cache_pressure=50' /etc/sysctl.conf; then
  echo -e "\e[32mAjuste 'vm.vfs_cache_pressure=50' já existe no /etc/sysctl.conf. Pulando...\e[0m\n"
else
  echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf
  echo -e "\e[32mAjuste 'vm.vfs_cache_pressure=50' adicionado ao /etc/sysctl.conf.\e[0m\n"
fi
sleep 2

sysctl vm.swappiness=10 > /dev/null 2>&1
sysctl vm.vfs_cache_pressure=50 > /dev/null 2>&1
echo -e "\e[32mSistema ajustado para melhor desempenho com novo arquivo de swap.\e[0m\n"
sleep 2

read -p "Deseja reiniciar agora? [s/N]: " resposta

if [[ "$resposta" =~ ^[Ss]$ ]]; then
  echo -e "\e[34mO sistema será reiniciado dentro de $i segundos...\e[0m\n"
  sleep 2
  for ((i=15; i>=1; i--)); do
    echo -e "\e[33mReiniciando o sistena em 15 segundos...\e[0m"
    sleep 1
  done
  echo -e "\n\e[34mReiniciando o sistema agora...\e[0m"
  reboot
else
  echo -e "\e[33mReinício cancelado pelo usuário. Script encerrado.\e[0m\n"
  sleep 2
  exit 0
fi
