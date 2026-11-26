#!/bin/bash
# shellcheck disable=SC2034
set -euo pipefail
if (( EUID == 0 )); then
  printf '%s\n' 'Execute os testes sem sudo.' >&2
  exit 1
fi

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
# shellcheck source=swap.sh
source ./swap.sh

lab=$(mktemp -d)
trap 'rm -rf -- "$lab"' EXIT

fail() {
  printf '\nFALHA: %s\n' "$*" >&2
  cat -- "$case_dir/output" "$trace" >&2
  exit 1
}

setup() {
  case_dir=$lab/$1
  mkdir -p -- "$case_dir"/{etc,run,dev,zvol/rpool}
  FSTAB=$case_dir/etc/fstab
  LOCK_FILE=$case_dir/run/lock
  SYSCTL_FILE=$case_dir/etc/sysctl.d/90-swap-script.conf
  SWAP_FILE=$case_dir/swapfile
  ZVOL_DIR=$case_dir/zvol
  LOG_FILE=$case_dir/operation.log
  CMDLINE=$case_dir/cmdline
  CRYPTTAB=$case_dir/etc/crypttab
  INITRAMFS_DIR=$case_dir/etc/initramfs-tools
  SYSTEMD_DIR=$case_dir/run/systemd
  MEMINFO=$case_dir/meminfo
  lv=$case_dir/dev/dm-0
  lv2=$case_dir/dev/dm-1
  zvol=$ZVOL_DIR/rpool/swap
  active=$case_dir/active
  trace=$case_dir/trace
  alloc=107374182400
  filesystem=ext4
  fail_show=false
  fail_show_after_off=false
  fail_off=
  fail_on=
  fail_restore=
  holes=false
  fail_btrfs_map=false
  fail_apply=false
  fail_fstab_move=false
  fake_crypt=false
  fake_units=
  fake_native_path=
  create_race=false
  fail_zvol_format=false
  change_guid=false
  printf 'UUID=root / ext4 defaults 0 1\n# comentario\n\n' > "$FSTAB"
  printf 'quiet\n' > "$CMDLINE"
  printf 'MemTotal: 2000000 kB\n' > "$MEMINFO"
  printf '# manter esta configuracao\nvm.swappiness=42\n' > "$case_dir/etc/sysctl.conf"
  chmod 640 "$FSTAB"
  touch -- "$active" "$trace" "$lv" "$lv2"
}

require_root() { :; }
findmnt() { case "$*" in *FSTYPE) echo "$filesystem";; *SOURCE) echo 'rpool/ROOT/debian';; *) return 99;; esac; }
findfs() { case "$1" in UUID=lv) echo "$lv";; UUID=lv2) echo "$lv2";; *) return 1;; esac; }
is_block_device() { [[ "$1" == "$lv" || "$1" == "$lv2" || ( "$1" == "$zvol" && -f "$zvol" ) ]]; }
blkid() {
  local device=${*: -1}
  if [[ "$device" == "$lv" || "$device" == "$lv2" || "$device" == "$zvol" ]] ||
     [[ -f "$device" && $(head -c 4 -- "$device") == SWAP ]]; then
    echo swap
  fi
}
lsblk() { echo lvm; if [[ "$fake_crypt" == true ]]; then echo crypt; fi; echo disk; }
df() { printf 'Avail\n%s\n' "$alloc"; }
getconf() { echo 4096; }
udevadm() { :; }
sleep() { :; }

mark_file() {
  printf SWAP | command dd of="$1" conv=notrunc status=none
}
fallocate() {
  printf 'fallocate %s\n' "$*" >> "$trace"
  [[ "$1" == -l && "$3" == -- && "$4" == "$SWAP_FILE".work.*/next ]] || return 99
  truncate -s "$2" -- "$4"
}
dd() {
  printf 'dd %s\n' "$*" >> "$trace"
  local arg outfile='' count=''
  for arg; do
    case "$arg" in of=*) outfile=${arg#of=};; count=*) count=${arg#count=};; esac
  done
  [[ "$outfile" == "$SWAP_FILE".work.*/next && "$count" =~ ^[0-9]+$ ]] || return 99
  truncate -s "$((count * 1024 * 1024))" -- "$outfile"
}
mkswap() {
  printf 'mkswap %s\n' "$*" >> "$trace"
  if [[ "$2" == "$zvol" ]]; then
    if [[ "$change_guid" == true ]]; then touch "$case_dir/guid-changed"; fi
    [[ "$fail_zvol_format" == false ]]
  else
    [[ "$2" == "$SWAP_FILE".work.*/next ]] && mark_file "$2"
  fi
}
btrfs() {
  printf 'btrfs %s\n' "$*" >> "$trace"
  if [[ "$1 $2" == 'filesystem mkswapfile' && "$5" == "$SWAP_FILE".work.*/next ]]; then
    truncate -s "$4" -- "$5"
    mark_file "$5"
  else
    [[ "$1 $2" == 'inspect-internal map-swapfile' && "$fail_btrfs_map" == false ]]
  fi
}
zfs() {
  printf 'zfs %s\n' "$*" >> "$trace"
  case "$1" in
    list)
      printf 'rpool\tfilesystem\n'
      if [[ -f "$case_dir/collision" ]]; then printf 'rpool/swap\tfilesystem\n'; fi
      if [[ -f "$zvol" ]]; then printf 'rpool/swap\tvolume\n'; fi ;;
    get)
      case "$*" in
        *available*) echo "$alloc";;
        *volsize*) stat -c %s -- "$zvol";;
        *guid*) if [[ -f "$case_dir/guid-changed" ]]; then echo 5678; else echo 1234; fi ;;
        *) return 99;;
      esac ;;
    create)
      [[ "${*: -1}" == 'rpool/swap' ]] || return 99
      truncate -s "$3" -- "$zvol"
      [[ "$create_race" == false ]] ;;
    destroy) [[ "$2" == 'rpool/swap' ]] && rm -- "$zvol" ;;
    *) return 99 ;;
  esac
}

swapon() {
  if [[ "$1" == --show=* ]]; then
    printf 'list\n' >> "$trace"
    [[ "$fail_show" == false ]] || return 1
    if [[ "$fail_show_after_off" == true ]] && grep -q '^off ' "$trace"; then return 1; fi
    cat -- "$active" || return 1
    return 0
  fi
  local device=${*: -1} priority=-2 bytes file_bytes
  printf 'on %s\n' "$*" >> "$trace"
  if [[ "$fail_on" == "$device" && ! -e "$case_dir/failed-once" ]]; then
    touch "$case_dir/failed-once"
    echo 'falha simulada' >&2
    return 1
  fi
  if [[ "$holes" == true ]] && ! grep -q '^dd ' "$trace"; then
    echo 'it appears to have holes' >&2
    return 1
  fi
  [[ "$fail_restore" != "$device" ]] || return 1
  if [[ "$1" == --priority ]]; then priority=$2; fi
  if [[ "$device" == "$lv" || "$device" == "$lv2" ]]; then
    bytes=1073737728
  else
    file_bytes=$(stat -c %s -- "$device") || return 99
    bytes=$((file_bytes - 4096))
  fi
  printf '%s %s %s\n' "$device" "$bytes" "$priority" >> "$active"
}
swapoff() {
  local device=${*: -1}
  printf 'off %s\n' "$device" >> "$trace"
  [[ "$device" != "$fail_off" ]] || return 2
  awk -v target="$device" '$1 != target' "$active" > "$active.tmp"
  command mv -- "$active.tmp" "$active"
}
sysctl() {
  printf 'sysctl %s\n' "$*" >> "$trace"
  [[ "$1" == -p && "$2" == "$SYSCTL_FILE" && "$fail_apply" == false ]]
}
systemctl() {
  printf 'systemctl %s\n' "$*" >> "$trace"
  case "$1" in
    list-unit-files) printf '%s' "$fake_units";;
    show) printf '%s\n' "$fake_native_path";;
    daemon-reload) :;;
    *) return 99;;
  esac
}
mv() {
  if [[ "$fail_fstab_move" == true && "${*: -1}" == "$FSTAB" ]]; then return 1; fi
  command mv "$@"
}

run() {
  local expected=$1 rc=0
  shift
  # O subshell conserva a configuração real fora das fixtures. main roda com errexit.
  (trap - EXIT; main "$@") > "$case_dir/output" 2>&1 &
  wait "$!" || rc=$?
  [[ "$rc" == "$expected" ]] || fail "esperava código $expected, recebeu $rc"
  printf 'OK: %s\n' "${case_dir##*/}"
}
set_lvs() {
  printf '%s 1073737728 7\n' "$lv" > "$active"
  printf 'UUID=lv none swap sw,pri=7 0 0\n' >> "$FSTAB"
  if [[ "${1:-}" == two ]]; then
    printf '%s 1073737728 8\n' "$lv2" >> "$active"
    printf 'UUID=lv2 none swap sw,pri=8 0 0\n' >> "$FSTAB"
  fi
}
set_existing_file() {
  truncate -s 8M -- "$SWAP_FILE"
  chmod 600 -- "$SWAP_FILE"
  mark_file "$SWAP_FILE"
  printf '%s 8384512 5\n' "$SWAP_FILE" > "$active"
  printf '%s none swap sw,pri=5 0 0\n' "$SWAP_FILE" >> "$FSTAB"
}
assert_old() { grep -qF "$lv " "$active" || fail "LV não está ativo"; }
assert_no_file() { [[ ! -e "$SWAP_FILE" ]] || fail "arquivo de swap não deveria existir"; }
assert_no_fstab_write() { cmp -s "$FSTAB" "$case_dir/original" || fail "fstab foi alterado"; }
assert_no_swap_commands() { ! grep -Eq '^(on|off|fallocate|zfs destroy) ' "$trace" || fail "operação de swap inesperada"; }

setup lvm-preservado
set_lvs
cp "$FSTAB" "$case_dir/original"
run 0 --size 8M
assert_old
assert_no_file
assert_no_fstab_write
assert_no_swap_commands
[[ ! -e "$SYSCTL_FILE" ]] || fail "não deveria aplicar sysctl"

setup lvm-inativo-preservado
printf 'UUID=lv none swap defaults 0 0\n' >> "$FSTAB"
cp "$FSTAB" "$case_dir/original"
run 0
assert_no_file
assert_no_fstab_write
assert_no_swap_commands

setup raiz-ext4-em-lvm
sed -i 's|UUID=root|/dev/mapper/vg-root|' "$FSTAB"
run 0 --size 08m
grep -qF '/dev/mapper/vg-root / ext4' "$FSTAB" || fail "linha da raiz alterada"
grep -qF "$SWAP_FILE 8384512 " "$active" || fail "arquivo não ativo"
[[ "$(stat -c %a "$FSTAB")" == 640 && "$(stat -c %a "$SWAP_FILE")" == 600 ]] || fail "permissões"
grep -qx 'vm.swappiness = 10' "$SYSCTL_FILE" || fail "sysctl não persistido"
grep -qx 'vm.swappiness=42' "$case_dir/etc/sysctl.conf" || fail "sysctl.conf foi modificado"
grep -q 'sysctl -p' "$trace" || fail "sysctl não aplicado"

setup primeira-execucao-tamanho-automatico
printf 'MemTotal: 8388608 kB\n' > "$MEMINFO"
run 0
[[ "$(stat -c %s -- "$SWAP_FILE")" == 6442450944 ]] || fail "8 GiB de RAM deveriam gerar 6 GiB de swap"
grep -qF "$SWAP_FILE none swap sw 0 0" "$FSTAB" || fail "swap automático não persistido"
grep -qF "$SWAP_FILE 6442446848 " "$active" || fail "swap automático não ativado"

setup noauto-arquivo-ausente
printf '%s none swap sw,noauto 0 0\n' "$SWAP_FILE" >> "$FSTAB"
cp -- "$FSTAB" "$case_dir/original"
run 1 --size 8M
grep -q 'noauto' "$case_dir/output" || fail "faltou explicar o bloqueio por noauto"
assert_no_file
assert_no_swap_commands
assert_no_fstab_write
[[ ! -s "$active" && ! -e "$SYSCTL_FILE" ]] || fail "noauto não deveria mudar a configuração"

setup noauto-arquivo-inativo
set_existing_file
: > "$active"
sed -i 's/sw,pri=5/sw,noauto,pri=5/' "$FSTAB"
cp -- "$FSTAB" "$case_dir/original"
run 1
assert_no_swap_commands
assert_no_fstab_write
[[ -f "$SWAP_FILE" && ! -s "$active" && ! -e "$SYSCTL_FILE" ]] || fail "swap inativo deveria ser preservado"

setup noauto-arquivo-ativo
set_existing_file
sed -i 's/sw,pri=5/sw,noauto,pri=5/' "$FSTAB"
cp -- "$FSTAB" "$case_dir/original"
cp -- "$active" "$case_dir/active.before"
run 0 --size 8M
assert_no_swap_commands
assert_no_fstab_write
cmp -s -- "$active" "$case_dir/active.before" || fail "swap já ativo deveria ser preservado"

setup migracao-explicita
set_lvs
cp "$FSTAB" "$case_dir/original"
run 0 --size 8M --replace-existing
[[ "$(grep -n '^on ' "$trace" | cut -d: -f1)" -lt "$(grep -n '^off ' "$trace" | cut -d: -f1)" ]] || fail "ordem de ativação"
! grep -q '^UUID=lv ' "$FSTAB" || fail "fstab ainda contém LV"
grep -qF "$SWAP_FILE 8384512 " "$active" || fail "arquivo não ativo"
[[ -e "$lv" ]] || fail "dispositivo original removido"
backups=("$FSTAB".backup.*)
if (( ${#backups[@]} != 1 )) || ! cmp -s "${backups[0]}" "$case_dir/original"; then
  fail "backup do fstab incorreto"
fi
[[ "$(command findmnt --fstab --tab-file "$FSTAB" --types swap --noheadings --output SOURCE)" == "$SWAP_FILE" ]] ||
  fail "findmnt não encontrou apenas o alvo no fstab gerado"

setup migracao-falha-ativacao
set_lvs
fail_on=$SWAP_FILE
cp "$FSTAB" "$case_dir/original"
run 1 --size 8M --replace-existing
assert_old
assert_no_file
assert_no_fstab_write
! grep -q '^off ' "$trace" || fail "swap antigo foi desativado"

setup migracao-falha-segundo-swapoff
set_lvs two
fail_off=$lv2
cp "$FSTAB" "$case_dir/original"
run 1 --size 8M --replace-existing
assert_old
grep -qF "on --priority 7 -- $lv" "$trace" || fail "prioridade do LV não restaurada"
grep -qF "$lv2 " "$active" || fail "segundo LV não está ativo"
assert_no_file
assert_no_fstab_write

setup migracao-falha-rollback
set_lvs two
fail_off=$lv2
fail_restore=$lv
cp "$FSTAB" "$case_dir/original"
run 1 --size 8M --replace-existing
grep -qF "$SWAP_FILE 8384512 " "$active" || fail "novo swap deveria permanecer ativo"
assert_no_fstab_write
grep -qi 'rollback incompleto' "$case_dir/output" || fail "falta aviso de recuperação"

setup migracao-falha-gravacao-do-fstab
set_lvs
fail_fstab_move=true
cp "$FSTAB" "$case_dir/original"
run 1 --size 8M --replace-existing
assert_old
assert_no_file
assert_no_fstab_write

setup migracao-inventario-indisponivel-no-rollback
set_lvs two
fail_off=$lv2
fail_show_after_off=true
cp "$FSTAB" "$case_dir/original"
run 1 --size 8M --replace-existing
grep -qF "$SWAP_FILE 8384512 " "$active" || fail "não deve remover swap de estado não verificável"
assert_no_fstab_write
grep -qi 'rollback incompleto' "$case_dir/output" || fail "falta aviso de recuperação"

setup inventario-falha
set_lvs
fail_show=true
cp "$FSTAB" "$case_dir/original"
run 1 --size 8M --replace-existing
assert_no_swap_commands
assert_no_fstab_write

setup migracao-criptografada
set_lvs
fake_crypt=true
run 1 --size 8M --replace-existing
assert_no_swap_commands

setup migracao-com-hibernacao
set_lvs
mkdir -p "$INITRAMFS_DIR/conf.d"
printf 'RESUME=UUID=lv\n' > "$INITRAMFS_DIR/conf.d/resume"
run 1 --size 8M --replace-existing
assert_no_swap_commands

setup migracao-unidade-independente
set_lvs
mkdir -p "$SYSTEMD_DIR"
fake_units='dev-vg-swap.swap enabled enabled'
run 1 --size 8M --replace-existing
assert_no_swap_commands

setup migracao-unidade-do-fstab
set_lvs
mkdir -p "$SYSTEMD_DIR"
fake_units='dev-vg-swap.swap generated -'
fake_native_path=$FSTAB
run 0 --size 8M --replace-existing
grep -qx 'systemctl daemon-reload' "$trace" || fail "faltou recarregar o systemd"

setup sem-espaco-reutiliza-mesmo-tamanho
set_existing_file
cp "$FSTAB" "$case_dir/original"
alloc=0
run 0 --size 8M
assert_no_swap_commands
assert_no_fstab_write

setup sem-espaco-preserva-tamanho-automatico
set_existing_file
alloc=0
run 0
assert_no_swap_commands

setup swapfile-redimensionado
set_existing_file
run 0 --size 16M
grep -qF "$SWAP_FILE 16773120 5" "$active" || fail "swap maior não foi ativado com prioridade original"

setup swapfile-rollback
set_existing_file
fail_on=$SWAP_FILE
cp "$FSTAB" "$case_dir/original"
run 1 --size 16M
grep -qF "$SWAP_FILE 8384512 5" "$active" || fail "arquivo anterior não voltou"
assert_no_fstab_write

setup arquivo-sem-assinatura-preservado
printf DADO > "$SWAP_FILE"
chmod 600 "$SWAP_FILE"
run 1 --size 8M
[[ "$(cat "$SWAP_FILE")" == DADO ]] || fail "arquivo original foi alterado"

setup btrfs-nocow
filesystem=btrfs
run 0 --size 8M
grep -q '^btrfs filesystem mkswapfile' "$trace" || fail "não chamou mkswapfile"
grep -q '^btrfs inspect-internal map-swapfile' "$trace" || fail "não verificou mapeamento"
! grep -q '^fallocate' "$trace" || fail "não pode usar fallocate genérico em btrfs"

setup fallback-holes
holes=true
run 0 --size 8M
grep -q '^dd ' "$trace" || fail "fallback não usado"

setup btrfs-falha-no-mapeamento
set_lvs
cp "$FSTAB" "$case_dir/original"
filesystem=btrfs
fail_btrfs_map=true
run 1 --size 8M --replace-existing
assert_old
assert_no_file
assert_no_fstab_write
assert_no_swap_commands

setup sysctl-falha-no-kernel
fail_apply=true
run 0 --size 8M
grep -q 'nem todos os ajustes' "$case_dir/output" || fail "sucesso parcial não reportado"

setup sysctl-admin-preservado
mkdir -p "${SYSCTL_FILE%/*}"
printf 'vm.swappiness=99\n' > "$SYSCTL_FILE"
run 0 --size 8M
grep -qx 'vm.swappiness=99' "$SYSCTL_FILE" || fail "configuração do administrador foi sobrescrita"
! grep -q '^sysctl ' "$trace" || fail "arquivo do administrador não deve ser aplicado automaticamente"

setup zfs-colisao
filesystem=zfs
touch "$case_dir/collision"
run 1 --size 8M
! grep -q '^zfs destroy ' "$trace" || fail "tentou destruir dataset preexistente"

setup zfs-falha-no-create
filesystem=zfs
create_race=true
run 1 --size 8M
[[ -e "$zvol" ]] || fail "removeu volume incerto"
! grep -q '^zfs destroy ' "$trace" || fail "tentou destruir volume não confirmado"

setup zfs-cria-e-ativa
filesystem=zfs
run 0 --size 8M
grep -qF "$zvol 8384512 " "$active" || fail "não ativou zvol"
grep -qF "$zvol none swap" "$FSTAB" || fail "não persistiu zvol"

setup zfs-limpeza-so-do-zvol-novo
filesystem=zfs
fail_zvol_format=true
run 1 --size 8M
grep -qx 'zfs destroy rpool/swap' "$trace" || fail "limpeza do volume próprio não ocorreu"
[[ ! -e "$zvol" ]] || fail "zvol incompleto persistiu"

setup zfs-nao-redimensiona
filesystem=zfs
truncate -s 8M "$zvol"
printf '%s 8384512 5\n' "$zvol" > "$active"
run 1 --size 16M
! grep -Eq '^(off |zfs destroy )' "$trace" || fail "tocou no zvol ativo"

setup zfs-identidade-alterada
filesystem=zfs
fail_zvol_format=true
change_guid=true
run 1 --size 8M
[[ -e "$zvol" ]] || fail "removeu volume com identidade diferente"
! grep -q '^zfs destroy ' "$trace" || fail "tentou destruir volume com identidade diferente"

for size in 0G 99999999999999999999999M '1;reboot' 8; do
  setup "argumento-invalido-${size//[^[:alnum:]]/}"
  run 1 --size "$size"
  [[ ! -s "$trace" ]] || fail "argumento inválido chegou a executar comandos"
done
setup argumento-ausente
run 1 --size
[[ ! -s "$trace" ]] || fail "argumento ausente chegou a executar comandos"
printf '\nTodos os cenários de regressão passaram.\n'
