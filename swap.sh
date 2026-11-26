#!/bin/bash
set -euo pipefail

SCRIPT_VERSION=1.5.9
LOG_FILE="/var/log/swap_script.log"
FSTAB="/etc/fstab"
SYSCTL_FILE="/etc/sysctl.d/90-swap-script.conf"
SWAP_FILE="/swapfile"
ZVOL_DIR="/dev/zvol"
LOCK_FILE="/run/swap-script.lock"
CRYPTTAB="/etc/crypttab"
CMDLINE="/proc/cmdline"
INITRAMFS_DIR="/etc/initramfs-tools"
SYSTEMD_DIR="/run/systemd/system"
MEMINFO="/proc/meminfo"
GREEN='\e[32m'
NC='\e[0m'

log_msg() {
  local color=$1
  shift
  local code=
  case "$color" in
    red) code=31 ;;
    green) code=32 ;;
    yellow) code=33 ;;
    blue) code=34 ;;
  esac
  if [[ -t 1 && -z "${NO_COLOR-}" && -n "$code" ]]; then
    printf '\e[%sm%s\e[0m\n' "$code" "$*"
  else
    printf '%s\n' "$*"
  fi
  if [[ "${log_enabled:-false}" == true ]]; then
    printf '[%s] [%s] %s\n' "$(date '+%F %T')" "$color" "$*" >> "$LOG_FILE" || :
  fi
}

error_exit() {
  log_msg red "ERRO: $*" >&2
  exit 1
}

# Função para exibir o banner inicial
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
  log_msg green "Desenvolvido por Codex (OpenAI), com direção e testes de Paulo Rocha"
}

exibir_ajuda() {
  cat <<EOF_HELP
Uso: $0 [opções]
  --size <tamanho>     Define o tamanho (ex.: 2G, 512M).
  --replace-existing  Autoriza migrar outros swaps registrados no /etc/fstab.
                      Sem esta opção, swaps existentes fora do alvo são preservados.
  --help              Exibe esta ajuda.
EOF_HELP
}

require_root() {
  [[ "$EUID" == 0 ]] || error_exit "Este script deve ser executado como root (use sudo)."
}

check_command() {
  command -v "$1" >/dev/null 2>&1 || error_exit "Comando '$1' não encontrado."
}

parse_size_to_bytes() {
  local input=$1 digits unit max
  [[ "$input" =~ ^0*([1-9][0-9]*)([MmGg])$ ]] || return 1
  digits=${BASH_REMATCH[1]}
  case "${BASH_REMATCH[2]}" in
    g|G) unit=$((1024 ** 3)) ;;
    m|M) unit=$((1024 ** 2)) ;;
  esac
  # Mantém espaço para a margem de disco e evita overflow da aritmética do Bash.
  max=$(( (1 << 50) / unit ))
  (( ${#digits} <= ${#max} && digits <= max )) || return 1
  printf '%s\n' "$(( digits * unit ))"
}

automatic_size() {
  local ram=$1
  if   (( ram <= 512 ));   then echo 1G
  elif (( ram <= 1024 ));  then echo 2G
  elif (( ram <= 2048 ));  then echo 3G
  elif (( ram <= 4096 ));  then echo 4G
  elif (( ram <= 8192 ));  then echo 6G
  elif (( ram <= 16384 )); then echo 8G
  else echo 16G
  fi
}

same_device() {
  [[ "$1" == "$2" || ( -n "$1" && -n "$2" && "$1" -ef "$2" ) ]]
}

resolve_source() {
  local source=$1
  case "$source" in
    /*) printf '%s\n' "$source" ;;
    UUID=*|LABEL=*|PARTUUID=*|PARTLABEL=*) findfs "$source" 2>/dev/null ;;
    *) return 1 ;;
  esac
}

read_active_swaps() {
  local table line device bytes priority extra
  table=$(LC_ALL=C swapon --show=NAME,SIZE,PRIO --bytes --raw --noheadings) || return 1
  active_devices=() active_sizes=() active_priorities=()
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    read -r device bytes priority extra <<< "$line"
    # Recusa formatos ambíguos sem interpretar escapes do nome como argumentos.
    [[ "$device" == /* && "$device" != *\\* && "$bytes" =~ ^[1-9][0-9]{0,17}$ &&
       "$priority" =~ ^-?[0-9]{1,5}$ && -z "$extra" ]] || return 1
    active_devices+=("$device")
    active_sizes+=("$bytes")
    active_priorities+=("$priority")
  done <<< "$table"
}

active_index() {
  local index
  for index in "${!active_devices[@]}"; do
    if same_device "${active_devices[index]}" "$1"; then
      printf '%s\n' "$index" || return 1
      # No trap EXIT, um return sem argumento pode herdar o status do trap.
      return 0
    fi
  done
  return 1
}

# O ponto final preserva as quebras de linha finais na substituição de comando.
read_fstab() {
  cat -- "$FSTAB" && printf .
}

analyze_fstab() {
  local line source _mount type options _rest device
  foreign_fstab=() foreign_fstab_devices=() foreign_fstab_options=()
  target_entries=() target_options=sw
  fstab_lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    fstab_lines+=("$line")
    [[ "$line" =~ ^[[:space:]]*($|\#) ]] && continue
    read -r source _mount type options _rest <<< "$line"
    [[ "$type" == swap ]] || continue
    device=
    if [[ "$source" != *\\* ]]; then
      device=$(resolve_source "$source") || device=
    fi
    if same_device "$device" "$target"; then
      if (( ${#target_entries[@]} == 0 )); then
        target_options=${options:-sw}
      fi
      target_entries+=("$(("${#fstab_lines[@]}" - 1))")
    else
      foreign_fstab+=("$source")
      foreign_fstab_devices+=("$device")
      foreign_fstab_options+=("${options:-sw}")
    fi
  done < <(printf '%s' "${original_fstab%.}")
}

is_block_device() {
  [[ -b "$1" ]]
}

swap_signature() {
  [[ "$(blkid -p -s TYPE -o value -- "$1")" == swap ]]
}

select_target() {
  local root_source
  fs_type=$(findmnt --mountpoint / --noheadings --output FSTYPE) ||
    error_exit "Não foi possível identificar o sistema de arquivos raiz."
  target=$SWAP_FILE
  if [[ "$fs_type" == zfs ]]; then
    check_command zfs
    root_source=$(findmnt --mountpoint / --noheadings --output SOURCE) ||
      error_exit "Não foi possível identificar o dataset raiz."
    pool=${root_source%%/*}
    [[ "$pool" =~ ^[[:alpha:]][[:alnum:]_.:-]*$ ]] || error_exit "Nome de pool ZFS inválido."
    dataset=$pool/swap
    target=$ZVOL_DIR/$dataset
  fi
}

inspect_target() {
  local datasets name kind
  target_exists=false
  if [[ "$fs_type" == zfs ]]; then
    datasets=$(zfs list -H -d 1 -o name,type "$pool") ||
      error_exit "Falha ao listar datasets do pool $pool."
    while IFS=$'\t' read -r name kind; do
      [[ "$name" == "$dataset" ]] || continue
      [[ "$kind" == volume ]] || error_exit "$dataset já existe e não é um zvol; nada será removido."
      target_exists=true
    done <<< "$datasets"
    if [[ "$target_exists" == true ]]; then
      is_block_device "$target" || error_exit "O dispositivo do zvol não está disponível: $target."
    elif [[ -e "$target" || -L "$target" ]]; then
      error_exit "O caminho $target já existe, mas não corresponde a um zvol esperado."
    fi
  elif [[ -e "$target" || -L "$target" ]]; then
    [[ ! -L "$target" && -f "$target" && $(stat -c '%a:%h' -- "$target") == '600:1' && -O "$target" ]] ||
      error_exit "$target deve ser um arquivo regular do root, modo 0600 e sem links."
    target_exists=true
  fi
  if [[ "$target_exists" == true ]]; then
    swap_signature "$target" || error_exit "$target não tem assinatura swap válida; nada será sobrescrito."
  fi
}

migration_guards() {
  local file settings name _source _key opts units line state unit active_source types source_fs target_fs
  local -a resume_files=("$INITRAMFS_DIR/initramfs.conf" "$INITRAMFS_DIR/conf.d/"*)
  settings=$(cat -- "$CMDLINE") || error_exit "Não foi possível ler os parâmetros do kernel."
  if [[ "$settings" =~ (^|[[:space:]])resume(_offset)?= ]]; then
    error_exit "Hibernação configurada no boot. Faça a migração de swap manualmente."
  fi
  for file in "${resume_files[@]}"; do
    [[ -f "$file" ]] || continue
    settings=$(sed -nE '/^[[:space:]]*(export[[:space:]]+)?RESUME[[:space:]]*=/p' "$file") ||
      error_exit "Não foi possível ler $file."
    while IFS= read -r line; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*(export[[:space:]]+)?RESUME[[:space:]]*=[[:space:]]*[\"\']?(none|auto)?[\"\']?([[:space:]]*\#.*|[[:space:]]*)$ ]] ||
        error_exit "Hibernação configurada em $file. Faça a migração manualmente."
    done <<< "$settings"
  done
  if [[ -f "$CRYPTTAB" ]]; then
    while read -r name _source _key opts _ || [[ -n "$name" ]]; do
      [[ -z "$name" || "$name" == \#* ]] && continue
      [[ ",$opts," != *,swap,* ]] || error_exit "Swap gerenciado por crypttab. Faça a migração manualmente."
    done < "$CRYPTTAB"
  fi
  # A migração por fstab não pode suprimir unidades administradas separadamente.
  if [[ -d "$SYSTEMD_DIR" ]]; then
    units=$(systemctl list-unit-files --type=swap --no-legend --no-pager) ||
      error_exit "Não foi possível inventariar as unidades de swap do systemd."
    while read -r unit state _; do
      [[ -n "$unit" ]] || continue
      [[ "$state" == generated ]] ||
        error_exit "Unidade de swap independente ($unit). Faça a migração manualmente."
      active_source=$(systemctl show --property=SourcePath --value -- "$unit") ||
        error_exit "Não foi possível verificar a origem de $unit."
      [[ "$active_source" == "$FSTAB" ]] ||
        error_exit "Unidade de swap não gerada pelo fstab ($unit). Faça a migração manualmente."
    done <<< "$units"
  fi
  for active_source in "${foreign_fstab_devices[@]}"; do
    if [[ -z "$active_source" || "$active_source" == *[[:space:]\\]* ]] ||
       { [[ ! -f "$active_source" ]] && ! is_block_device "$active_source"; } ||
       ! swap_signature "$active_source"; then
      error_exit "O fstab contém um swap inacessível ou não reconhecido. Revise a entrada antes de migrar."
    fi
    if is_block_device "$active_source"; then
      types=$(lsblk --inverse --raw --noheadings --output TYPE -- "$active_source") ||
        error_exit "Não foi possível verificar a cadeia de dispositivos de $active_source."
      [[ -n "$types" ]] || error_exit "Cadeia de dispositivos vazia para $active_source."
      if grep -qx '[[:space:]]*crypt[[:space:]]*' <<< "$types"; then
        error_exit "Swap em dispositivo criptografado ($active_source). Faça a migração manualmente."
      fi
    else
      source_fs=$(stat -Lc %d -- "$active_source") || error_exit "Não foi possível verificar $active_source."
      target_fs=$(stat -c %d -- "${target%/*}/") || error_exit "Não foi possível verificar o filesystem de $target."
      [[ "$source_fs" == "$target_fs" ]] ||
        error_exit "Swap em outro sistema de arquivos ($active_source). Faça a migração manualmente."
    fi
  done
}

check_space() {
  local bytes required
  if [[ "$fs_type" == zfs ]]; then
    bytes=$(zfs get -Hp -o value available "$pool") || error_exit "Falha ao consultar espaço no pool ZFS."
  else
    bytes=$(df -B1 --output=avail -- "${target%/*}/" | awk 'NR == 2 {print $1}') ||
      error_exit "Falha ao consultar espaço no sistema de arquivos."
  fi
  [[ "$bytes" =~ ^[0-9]{1,18}$ ]] || error_exit "Valor de espaço disponível inválido."
  required=$((size_bytes + size_bytes / 5 + 1024 ** 3))
  (( bytes >= required )) ||
    error_exit "Espaço insuficiente: disponíveis $bytes bytes, necessários $required bytes (com margem)."
}

prepare_swapfile() {
  local use_dd=${1:-false}
  if [[ -z "$work_dir" ]]; then
    work_dir=$(mktemp -d -- "${target}.work.XXXXXX") || error_exit "Falha ao criar diretório temporário."
  fi
  staged_file=$work_dir/next
  prepared_with_dd=false
  if [[ "$fs_type" == btrfs ]]; then
    btrfs filesystem mkswapfile --size "$size_bytes" "$staged_file" ||
      error_exit "Falha ao preparar o arquivo NOCOW no Btrfs."
    chmod 600 -- "$staged_file"
    btrfs inspect-internal map-swapfile "$staged_file" >/dev/null ||
      error_exit "O Btrfs não pôde mapear o arquivo de swap."
    return
  fi

  : > "$staged_file"
  chmod 600 -- "$staged_file"
  if [[ "$use_dd" == true ]] || ! fallocate -l "$size_bytes" -- "$staged_file" 2>/dev/null; then
    prepared_with_dd=true
    dd if=/dev/zero of="$staged_file" bs=1M count="$((size_bytes / 1024 ** 2))" status=none ||
      error_exit "Falha ao alocar o arquivo de swap com dd."
  fi
  mkswap -- "$staged_file" >/dev/null || error_exit "Falha ao inicializar o arquivo de swap."
}

create_zvol() {
  local page_size
  page_size=$(getconf PAGESIZE) || error_exit "Não foi possível obter o tamanho de página do kernel."
  zfs create -V "$size_bytes" -b "$page_size" \
    -o compression=zle -o logbias=throughput -o sync=always \
    -o primarycache=metadata -o secondarycache=none -o com.sun:auto-snapshot=false \
    "$dataset" || error_exit "Falha ao criar o zvol $dataset."
  zvol_created=true
  zvol_guid=$(zfs get -Hp -o value guid "$dataset") ||
    error_exit "Não foi possível confirmar a identidade do zvol recém-criado: $dataset."
  [[ "$zvol_guid" =~ ^[0-9]+$ ]] || error_exit "Identificador inválido para o zvol $dataset."

  if command -v udevadm >/dev/null; then
    udevadm settle --timeout=10 || :
  fi
  for _ in {1..20}; do
    is_block_device "$target" && break
    sleep 0.2
  done
  is_block_device "$target" || error_exit "Dispositivo não encontrado: $target."
  mkswap -- "$target" >/dev/null || error_exit "Falha ao inicializar o zvol $dataset."
}

install_staged_file() {
  installed_id=$(stat -c '%d:%i' -- "$staged_file") || error_exit "Falha ao identificar o arquivo de swap preparado."
  mv -T --no-clobber -- "$staged_file" "$target" && [[ ! -e "$staged_file" ]] ||
    error_exit "Não foi possível instalar o novo arquivo de swap: $target."
  file_installed=true
}

activation_args() {
  local options=$1 priority=$2 opt
  local -a tokens
  swap_args=()
  IFS=, read -ra tokens <<< "$options"
  for opt in "${tokens[@]}"; do
    case "$opt" in
      discard) swap_args+=(--discard) ;;
      discard=once|discard=pages) swap_args+=("--$opt") ;;
      pri=*) [[ -n "$priority" ]] || swap_args+=(--priority "${opt#pri=}") ;;
    esac
  done
  if [[ -n "$priority" && "$priority" != -* ]]; then
    swap_args+=(--priority "$priority")
  fi
}

find_fstab_options() {
  local device=$1 index
  for index in "${!foreign_fstab_devices[@]}"; do
    if same_device "$device" "${foreign_fstab_devices[index]}"; then
      printf '%s\n' "${foreign_fstab_options[index]}"
      return
    fi
  done
  return 1
}

deactivate_old() {
  local device=$1 priority=$2 options=$3
  off_devices+=("$device") off_priorities+=("$priority") off_options+=("$options")
  swapoff -- "$device" || error_exit "Falha ao desativar $device."
}

prepare_fstab() {
  local line _source _mount type _rest index target_index found=false keep
  fstab_tmp=$(mktemp -- "${FSTAB}.swap.XXXXXX") || error_exit "Falha ao preparar o fstab."
  cp --attributes-only --preserve=all -- "$FSTAB" "$fstab_tmp" ||
    error_exit "Falha ao preservar os metadados do fstab."
  {
    for index in "${!fstab_lines[@]}"; do
      line=${fstab_lines[index]}
      if [[ ! "$line" =~ ^[[:space:]]*($|\#) ]]; then
        read -r _source _mount type _rest <<< "$line"
        if [[ "$type" == swap ]]; then
          keep=false
          for target_index in "${target_entries[@]}"; do
            if [[ "$index" == "$target_index" ]]; then
              keep=true
              break
            fi
          done
          if [[ "$keep" == true && "$found" == false ]]; then
            printf '%s\n' "$line"
            found=true
            continue
          fi
          [[ "$replace" == true || "$keep" == true ]] && continue
        fi
      fi
      printf '%s\n' "$line"
    done
    if [[ "$found" == false ]]; then
      printf '%s none swap sw 0 0\n' "$target"
    fi
  } > "$fstab_tmp"
  if cmp -s -- "$fstab_tmp" "$FSTAB"; then
    rm -f -- "$fstab_tmp"
    fstab_tmp=
    return
  fi
  fstab_backup=$(mktemp -- "${FSTAB}.backup.$(date +%Y%m%d_%H%M%S).XXXXXX") ||
    error_exit "Falha ao reservar o backup do fstab."
  cp --preserve=all -- "$FSTAB" "$fstab_backup" ||
    error_exit "Falha ao gravar o backup do fstab."
}

rollback() {
  local rc=$? index device actual_guid healthy=true safe_to_remove=true
  trap - EXIT
  trap '' INT TERM HUP
  set +e
  if [[ "$committed" != true && ( "$activation_started" == true || "${#off_devices[@]}" -gt 0 ) ]]; then
    if read_active_swaps; then
      for index in "${!off_devices[@]}"; do
        device=${off_devices[index]}
        [[ -n "$work_dir" && -e "$work_dir/previous" ]] && same_device "$device" "$target" && continue
        active_index "$device" >/dev/null && continue
        activation_args "${off_options[index]}" "${off_priorities[index]}"
        swapon "${swap_args[@]}" -- "$device" || { log_msg red "Não foi possível reativar $device." >&2; healthy=false; }
      done
      if [[ "$activation_started" == true ]]; then
        if [[ "$healthy" != true ]] || { active_index "$target" >/dev/null && ! swapoff -- "$target"; }; then
          safe_to_remove=false
        fi
      fi
    else
      safe_to_remove=false
    fi
  fi

  if [[ "$committed" != true && "$safe_to_remove" == true ]]; then
    if [[ "$file_installed" == true ]]; then
      if [[ "$(stat -c '%d:%i' -- "$target")" != "$installed_id" ]] || ! rm -f -- "$target"; then
        safe_to_remove=false
      fi
    fi
    if [[ "$safe_to_remove" == true && -n "$work_dir" && -e "$work_dir/previous" ]]; then
      if mv -T --no-clobber -- "$work_dir/previous" "$target" && [[ ! -e "$work_dir/previous" ]]; then
        if [[ -n "$original_active" ]]; then
          activation_args "$target_options" "$original_priority"
          swapon "${swap_args[@]}" -- "$target" || log_msg red "Arquivo antigo restaurado, mas não reativado: $target." >&2
        fi
      else
        safe_to_remove=false
      fi
    fi
    if [[ "$zvol_created" == true ]]; then
      if [[ ! "$zvol_guid" =~ ^[0-9]+$ ]] ||
         ! actual_guid=$(zfs get -Hp -o value guid "$dataset") ||
         [[ "$actual_guid" != "$zvol_guid" ]]; then
        log_msg red "Identidade do zvol não confirmada; não removido: $dataset." >&2
      elif ! zfs destroy "$dataset"; then
        log_msg red "Não foi possível remover o zvol criado nesta execução: $dataset." >&2
      fi
    fi
  fi
  if [[ "$safe_to_remove" == true ]]; then
    if [[ -n "$work_dir" ]]; then
      rm -f -- "$work_dir/next" "$work_dir/previous"
      rmdir -- "$work_dir" 2>/dev/null || :
    fi
  else
    log_msg red "Rollback incompleto. Verifique os swaps ativos; recursos preservados: $target ${work_dir:-}." >&2
  fi
  if [[ -n "$fstab_tmp" ]]; then
    rm -f -- "$fstab_tmp"
  fi
  exit "$rc"
}

persist_tuning() {
  local contents tmp
  contents=$'# Gerenciado pelo swap.sh\nvm.swappiness = 10\nvm.vfs_cache_pressure = 50\nvm.dirty_ratio = 15\nvm.dirty_background_ratio = 5'
  if [[ -L "$SYSCTL_FILE" || ( -e "$SYSCTL_FILE" && ! -f "$SYSCTL_FILE" ) ]]; then
    log_msg yellow "Ajustes não aplicados: $SYSCTL_FILE não é um arquivo regular."
    return
  fi
  if [[ -e "$SYSCTL_FILE" ]]; then
    if ! cmp -s -- "$SYSCTL_FILE" <(printf '%s\n' "$contents"); then
      log_msg yellow "Ajustes não aplicados: $SYSCTL_FILE já existe com conteúdo diferente."
      return
    fi
  else
    if ! { mkdir -p -- "${SYSCTL_FILE%/*}" &&
           tmp=$(mktemp -- "${SYSCTL_FILE}.XXXXXX") &&
           printf '%s\n' "$contents" > "$tmp" &&
           chmod 644 -- "$tmp" &&
           ln -T -- "$tmp" "$SYSCTL_FILE"; }; then
      if [[ -n "${tmp:-}" ]]; then rm -f -- "$tmp"; fi
      log_msg yellow "Não foi possível gravar os ajustes em $SYSCTL_FILE."
      return
    fi
    rm -f -- "$tmp"
  fi
  if sysctl -p "$SYSCTL_FILE" >/dev/null; then
    log_msg green "Ajustes de memória aplicados e registrados em $SYSCTL_FILE."
  else
    log_msg yellow "Swap configurado, mas nem todos os ajustes de memória puderam ser aplicados."
  fi
}

main() {
  local custom_size='' replace=false ram_kb size size_bytes allocated difference page_size index device options
  local fs_type target pool='' dataset='' target_exists original_fstab fstab_tmp='' fstab_backup=''
  local original_active='' original_priority='' work_dir='' staged_file='' fstab_changed=false
  local zvol_created=false zvol_guid='' file_installed=false installed_id=''
  local prepared_with_dd=false activation_started=false committed=false
  local log_enabled=false
  local -a active_devices active_sizes active_priorities foreign_fstab foreign_fstab_devices
  local -a foreign_fstab_options target_entries fstab_lines swap_args
  local -a old_devices=() old_priorities=() old_options=() off_devices=() off_priorities=() off_options=()

  while (( $# )); do
    case "$1" in
      --size)
        [[ $# -ge 2 ]] || error_exit "Informe um tamanho após --size."
        custom_size=$2
        size_bytes=$(parse_size_to_bytes "$custom_size") || error_exit "Tamanho inválido: use um inteiro positivo seguido de M ou G."
        shift ;;
      --replace-existing) replace=true ;;
      --help) exibir_ajuda; return ;;
      *) error_exit "Opção inválida: $1. Consulte --help." ;;
    esac
    shift
  done
  require_root
  for device in findmnt findfs swapon swapoff blkid lsblk mkswap stat mktemp cmp df awk flock sysctl; do
    check_command "$device"
  done
  umask 077
  [[ ! -L "$LOCK_FILE" && ( ! -e "$LOCK_FILE" || ( -f "$LOCK_FILE" && -O "$LOCK_FILE" ) ) ]] ||
    error_exit "Arquivo de bloqueio inválido: $LOCK_FILE."
  exec 9>>"$LOCK_FILE"
  flock -n 9 || error_exit "Outra execução de swap.sh está em andamento."
  if [[ -t 1 && -z "${NO_COLOR-}" ]]; then
    exibir_banner
  else
    log_msg green "Script de configuração de SWAP versão $SCRIPT_VERSION"
  fi

  select_target
  [[ -f "$FSTAB" && ! -L "$FSTAB" ]] || error_exit "O fstab deve ser um arquivo regular, sem link simbólico."
  original_fstab=$(read_fstab) || error_exit "Não foi possível ler o fstab."
  read_active_swaps || error_exit "Não foi possível inventariar os swaps ativos; nenhuma alteração realizada."
  analyze_fstab
  for index in "${!active_devices[@]}"; do
    device=${active_devices[index]}
    if same_device "$device" "$target"; then
      original_active=$device
      original_priority=${active_priorities[index]}
      allocated=${active_sizes[index]}
    else
      old_devices+=("$device")
      old_priorities+=("${active_priorities[index]}")
    fi
  done

  if (( ${#old_devices[@]} + ${#foreign_fstab[@]} > 0 )); then
    if [[ "$replace" == false ]]; then
      log_msg yellow "Swap existente preservado. Para migrar um swap do fstab, use --replace-existing após revisar a configuração."
      return
    fi
    migration_guards
    for device in "${old_devices[@]}"; do
      options=$(find_fstab_options "$device") ||
        error_exit "Swap ativo fora do fstab ($device). Faça a migração manualmente."
      old_options+=("$options")
    done
  fi

  if [[ "$fs_type" != zfs ]]; then
    case "$fs_type" in
      ext2|ext3|ext4|xfs) ;;
      btrfs) check_command btrfs ;;
      *) error_exit "Sistema de arquivos sem suporte para swapfile: $fs_type." ;;
    esac
  fi
  inspect_target
  if [[ "$target_exists" == false && -n "$original_active" ]]; then
    error_exit "O swap ativo $original_active não pôde ser identificado no disco."
  fi
  if [[ -z "$original_active" && ",$target_options," == *,noauto,* ]]; then
    error_exit "O alvo $target está inativo e tem noauto no fstab. A configuração foi preservada."
  fi

  if [[ -z "$custom_size" ]]; then
    ram_kb=$(awk '$1 == "MemTotal:" {print $2; exit}' "$MEMINFO")
    [[ "$ram_kb" =~ ^[1-9][0-9]{0,12}$ ]] || error_exit "Não foi possível detectar a RAM."
    size=$(automatic_size "$((ram_kb / 1024))")
    size_bytes=$(parse_size_to_bytes "$size")
  fi

  local provision=true
  if [[ "$target_exists" == true ]]; then
    provision=false
    if [[ -n "$custom_size" ]]; then
      if [[ -z "$original_active" ]]; then
        if [[ "$fs_type" == zfs ]]; then
          allocated=$(zfs get -Hp -o value volsize "$dataset") || error_exit "Falha ao consultar o tamanho do zvol."
        else
          allocated=$(stat -c %s -- "$target") || error_exit "Falha ao consultar o tamanho do arquivo."
        fi
      fi
      [[ "$allocated" =~ ^[1-9][0-9]{0,17}$ ]] || error_exit "Tamanho do swap existente inválido."
      difference=$((size_bytes - allocated))
      # Somente a diferença de até uma página do kernel é metadado do swap.
      page_size=$(getconf PAGESIZE) || error_exit "Não foi possível obter o tamanho de página do kernel."
      [[ "$page_size" =~ ^[1-9][0-9]{0,6}$ ]] || error_exit "Tamanho de página do kernel inválido."
      if (( difference > page_size || difference < 0 )); then
        [[ "$fs_type" != zfs ]] || error_exit "O zvol existente não será redimensionado automaticamente: $dataset."
        migration_guards
        provision=true
      fi
    fi
  fi
  if [[ "$provision" == true ]]; then check_space; fi

  if [[ ! -L "$LOG_FILE" && ( ! -e "$LOG_FILE" || -f "$LOG_FILE" ) ]] &&
     touch -- "$LOG_FILE" 2>/dev/null; then
    log_enabled=true
  fi

  trap rollback EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP

  log_msg blue "Alvo: $target. Swaps externos ativos a desativar: ${#old_devices[@]}."
  [[ "$(read_fstab)" == "$original_fstab" ]] || error_exit "O fstab foi alterado durante a execução."
  prepare_fstab

  if [[ "$provision" == true && "$fs_type" == zfs ]]; then
    create_zvol
  elif [[ "$provision" == true ]]; then
    prepare_swapfile
    if [[ "$target_exists" == true ]]; then
      if [[ -n "$original_active" ]]; then
        deactivate_old "$original_active" "$original_priority" "$target_options"
      fi
      mv -T -- "$target" "$work_dir/previous" || error_exit "Falha ao preservar o arquivo de swap antigo."
    fi
    install_staged_file
  fi

  if [[ -z "$original_active" || "$provision" == true ]]; then
    activation_started=true
    activation_args "$target_options" "$original_priority"
    local swapon_error
    if ! swapon_error=$(LC_ALL=C swapon "${swap_args[@]}" -- "$target" 2>&1); then
      if [[ "$file_installed" == true && "$fs_type" != btrfs && "$prepared_with_dd" == false &&
            "$swapon_error" == *holes* ]]; then
        if ! read_active_swaps || active_index "$target" >/dev/null ||
           [[ "$(stat -c '%d:%i' -- "$target")" != "$installed_id" ]]; then
          error_exit "Não foi possível confirmar que o arquivo pode ser substituído pelo fallback."
        fi
        rm -- "$target" || error_exit "Falha ao retirar o arquivo que não pôde ser ativado."
        file_installed=false
        prepare_swapfile true
        install_staged_file
        swapon "${swap_args[@]}" -- "$target" || error_exit "Falha ao ativar $target após preparar com dd."
      else
        error_exit "Falha ao ativar $target: $swapon_error"
      fi
    fi
  fi
  if ! read_active_swaps || ! active_index "$target" >/dev/null; then
    error_exit "Não foi possível confirmar que o swap alvo está ativo."
  fi
  log_msg green "Ativação confirmada: $target."
  for index in "${!old_devices[@]}"; do
    deactivate_old "${old_devices[index]}" "${old_priorities[index]}" "${old_options[index]}"
  done
  if ! read_active_swaps || ! active_index "$target" >/dev/null || (( ${#active_devices[@]} != 1 )); then
    error_exit "O estado final dos swaps ativos não corresponde ao plano."
  fi

  [[ "$(read_fstab)" == "$original_fstab" ]] || error_exit "O fstab foi alterado durante a execução."
  if [[ -n "$fstab_tmp" ]]; then
    # Evita separar a confirmação do commit do rename por um sinal tratável.
    trap '' INT TERM HUP
    mv -T -- "$fstab_tmp" "$FSTAB" || error_exit "Falha ao gravar o fstab."
    fstab_tmp=
    fstab_changed=true
  fi
  committed=true
  trap - EXIT INT TERM HUP
  if [[ -n "$work_dir" ]]; then
    if ! rm -f -- "$work_dir/previous" || ! rmdir -- "$work_dir"; then
      log_msg yellow "Troca concluída, mas o diretório de trabalho não foi removido: $work_dir."
    fi
  fi

  umask 022
  if [[ "$fstab_changed" == true ]]; then
    log_msg green "Entrada de swap atualizada em $FSTAB. Backup: $fstab_backup"
    if [[ -d "$SYSTEMD_DIR" ]] && ! systemctl daemon-reload; then
      log_msg yellow "Não foi possível recarregar o systemd. Execute systemctl daemon-reload após verificar o fstab."
    fi
  fi
  persist_tuning
  index=$(active_index "$target")
  log_msg green "Swap ativo em $target: ${active_sizes[index]} bytes. Não é necessário reiniciar."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
