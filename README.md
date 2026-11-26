# Provisionamento de SWAP para Debian e Ubuntu
<p align="center">
  <img src="https://img.shields.io/badge/version-1.5.9-blue.svg" alt="Versão">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="Licença">
  <img src="https://img.shields.io/badge/platform-Linux-lightgrey.svg" alt="Plataforma">
  <img src="https://img.shields.io/badge/shell-Bash-yellow.svg" alt="Shell">
</p>

Script em Bash para provisionar e ajustar SWAP em hosts Debian e Ubuntu. O fluxo detecta o backend compatível com o filesystem em uso, aplica a configuração persistente no sistema e registra a execução em log.

## Sumário

- [Visão geral](#visão-geral)
- [Compatibilidade](#compatibilidade)
- [Escopo operacional](#escopo-operacional)
- [Lógica de tamanho automático](#lógica-de-tamanho-automático)
- [Pré-requisitos](#pré-requisitos)
- [Operação](#operação)
- [Fluxo de execução](#fluxo-de-execução)
- [Artefatos e alterações](#artefatos-e-alterações)
- [Validação pós-execução](#validação-pós-execução)
- [Testes de regressão](#testes-de-regressão)
- [Limitações](#limitações)
- [Observações operacionais](#observações-operacionais)
- [Changelog](#changelog)
- [Licença](#licença)
- [Créditos](#créditos)

## Visão geral

O `swap.sh` provisiona swap com persistência no boot. Por padrão, preserva áreas de swap já existentes em outros dispositivos ou arquivos.

- Raiz em ext2, ext3, ext4 ou XFS: usa `/swapfile`. Se a raiz estiver em um LV, o arquivo ocupa espaço dentro do filesystem desse LV; o script não altera a estrutura do LVM.
- Raiz em Btrfs: usa `/swapfile` com NOCOW e verifica se o arquivo atende às restrições de mapeamento do Btrfs.
- Raiz em ZFS: usa `/dev/zvol/<pool>/swap`. Um volume existente só é reutilizado se tiver uma assinatura de swap válida; não é redimensionado pelo script.

Além da criação do swap, o script:

- cria backup do `/etc/fstab` antes de alterá-lo;
- atualiza o `/etc/fstab`;
- grava os ajustes de memória virtual em `/etc/sysctl.d/90-swap-script.conf` e tenta aplicá-los imediatamente;
- registra mensagens de provisionamento em `/var/log/swap_script.log`.

## Compatibilidade

- Debian e Ubuntu. A persistência dos ajustes usa `sysctl.d`, pois o Debian 13 não carrega mais `/etc/sysctl.conf` no boot padrão.
- Execução como `root` ou com `sudo`.
- Suporte a ZFS no sistema raiz com criação de swap via `zvol`.
- Tamanhos personalizados em MiB (`M`) ou GiB (`G`), com sufixo em maiúsculas ou minúsculas.

## Escopo operacional

- Detecta a quantidade de RAM instalada.
- Inventaria swaps ativos e persistentes antes de decidir o que fazer. Se o inventário falhar, não altera o swap.
- Usa o tamanho automático para novas áreas de swap sem `--size`. Reaproveita o alvo existente por padrão.
- Verifica espaço disponível apenas se precisar alocar um novo arquivo ou volume.
- Com `--replace-existing`, migra swaps compatíveis registrados no `fstab`: confirma o novo swap antes de desativar os antigos e tenta reativá-los se a troca falhar.
- Persiste o alvo no `fstab` sem modificar a configuração de outras montagens e sem alterar as permissões existentes do arquivo.
- Configura `vm.swappiness=10`, `vm.vfs_cache_pressure=50`, `vm.dirty_ratio=15` e `vm.dirty_background_ratio=5` no arquivo dedicado em `sysctl.d`, sem editar `/etc/sysctl.conf`.

## Lógica de tamanho automático

Quando precisa criar swap e `--size` não é informado, o script calcula um tamanho com base na RAM total detectada no host. Se o alvo já existir, seu tamanho é preservado.

A escolha não segue a regra antiga de "swap = 2x RAM", porque essa regra costuma gerar valores exagerados em servidores modernos. Em vez disso, o script usa faixas conservadoras: hosts com pouca RAM recebem proporcionalmente mais swap, enquanto hosts com mais RAM recebem um limite mais controlado.

| RAM detectada | Swap automático |
|---:|---:|
| até `512 MiB` | `1G` |
| até `1 GiB` | `2G` |
| até `2 GiB` | `3G` |
| até `4 GiB` | `4G` |
| até `8 GiB` | `6G` |
| até `16 GiB` | `8G` |
| acima de `16 GiB` | `16G` |

Essa lógica atende bem a uso geral em Debian/Ubuntu, especialmente em servidores pequenos, VPS e hosts onde o objetivo é evitar ausência total de swap.

O cálculo automático não tenta dimensionar swap para hibernação, banco de dados, virtualização pesada ou políticas específicas de produção. Nesses casos, defina o valor manualmente:

```bash
sudo ./swap.sh --size 4G
```

## Pré-requisitos

- Sistema baseado em Debian ou Ubuntu.
- Permissões administrativas.
- Espaço em disco suficiente para o tamanho de swap desejado.
- Em ambientes Btrfs, pacote `btrfs-progs` com os subcomandos `filesystem mkswapfile` e `inspect-internal map-swapfile`.
- Em ambientes ZFS, utilitário `zfs` disponível no sistema.

## Operação

Clone o repositório, entre no diretório do projeto e dê permissão de execução ao script:

```bash
git clone https://github.com/PauloNRocha/swap.git
cd swap
chmod +x swap.sh
```

Execução com tamanho automático:

```bash
sudo ./swap.sh
```

Execução com tamanho definido manualmente:

```bash
sudo ./swap.sh --size 4G
sudo ./swap.sh --size 512M
sudo ./swap.sh --size 2g
```

Quando há um swap em LV, partição ou arquivo diferente do alvo, inclusive se estiver inativo mas constar no `fstab`, a execução normal não altera a configuração. `--size` por si só não autoriza a troca; ele pode redimensionar apenas o `/swapfile` que já for o alvo.

Para verificar antes de decidir, execute estes comandos de leitura:

```bash
findmnt --noheadings --output SOURCE,FSTYPE --mountpoint /
swapon --show=NAME,TYPE,SIZE,USED,PRIO
findmnt --fstab --types swap --output SOURCE,OPTIONS
sudo lvs -o vg_name,lv_name,lv_size,lv_attr  # Apenas se o host usa LVM
```

Se a troca for intencional, execute em janela de manutenção. O exemplo abaixo troca um swap compatível do `fstab` por um alvo de `4 GiB` e **não apaga nem redimensiona o LV antigo**:

```bash
sudo ./swap.sh --replace-existing --size 4G
```

O modo de migração não é um redimensionador de LVM. Ele recusa swaps ativos sem entrada correspondente no `fstab`, unidades independentes do systemd e configurações detectadas de hibernação ou swap criptografado. Nesses casos, planeje a troca manualmente.

Ajuda:

```bash
sudo ./swap.sh --help
```

## Fluxo de execução

Durante a execução, o script segue esta ordem:

1. Valida argumentos, privilégios e dependências e bloqueia execuções simultâneas.
2. Identifica o backend, lê o `fstab` e lista os swaps ativos.
3. Preserva swaps fora do alvo, salvo quando uma migração explícita é solicitada e passa pelas verificações.
4. Reaproveita o alvo válido ou verifica o espaço e prepara uma nova área. Faz backup do `fstab` se houver mudança.
5. Ativa e verifica o alvo. Na migração, desativa os swaps anteriores só depois dessa verificação.
6. Atualiza o `fstab` e recarrega as unidades do systemd quando aplicável.
7. Persiste e tenta aplicar os ajustes de memória virtual. Não solicita reinício.

## Artefatos e alterações

Arquivos modificados pelo script:

- `/etc/fstab`
- `/etc/sysctl.d/90-swap-script.conf`

O script preserva dono e permissões existentes do `fstab`. Se o arquivo dedicado de sysctl já contiver configuração diferente, não o sobrescreve.

Artefatos criados pelo script:

- `/var/log/swap_script.log`
- `/swapfile` em sistemas sem ZFS, quando esse for o backend escolhido
- `/dev/zvol/<pool>/swap` em sistemas com ZFS

Backup criado quando o `fstab` muda: `/etc/fstab.backup.<data_hora>.<sufixo>`.

## Validação pós-execução

Após a aplicação, valide o estado final com:

```bash
swapon --show=NAME,TYPE,SIZE,USED,PRIO
free -h
findmnt --fstab --types swap --output SOURCE,OPTIONS
sysctl vm.swappiness vm.vfs_cache_pressure vm.dirty_ratio vm.dirty_background_ratio
sudo tail -n 50 /var/log/swap_script.log
```

Resultado esperado:

- Se o script preservou um swap existente, a lista de dispositivos ativos e o `fstab` devem estar como antes.
- Se houve provisionamento ou migração, o alvo deve constar nos swaps ativos e no `fstab`. O kernel pode mostrar o dispositivo real do zvol (por exemplo, `/dev/zd0`) em vez do alias em `/dev/zvol/`.
- Se os ajustes foram aplicados, os valores lidos com `sysctl` devem ser os do arquivo dedicado. Para validar persistência, confira novamente após um reboot planejado. Outros arquivos de sysctl com maior precedência podem sobrescrevê-los no boot.

## Testes de regressão

```bash
bash -n swap.sh
shellcheck -x swap.sh tests/swap-regression.sh
bash tests/swap-regression.sh
```

Execute sem `sudo`. Os testes usam fixtures e comandos simulados. Não ativam swaps reais nem alteram o `fstab` ou os parâmetros do host. A validação de boot e armazenamento real exige uma VM descartável.

## Limitações

- O foco é criação e ajuste inicial de swap, não gerenciamento avançado de múltiplos dispositivos.
- Redimensionar um `/swapfile` existente exige espaço para manter o antigo e preparar o novo. O caminho final é o mesmo: há uma breve desativação do arquivo anterior, que é preservado para rollback. Se qualquer interrupção de swap for inaceitável, planeje a troca manualmente.
- O script não redimensiona zvols. Em Btrfs, um arquivo ativo restringe snapshots do subvolume que o contém.
- O script altera parâmetros de memória virtual com valores definidos no próprio código; se o seu ambiente tiver política própria de tuning, revise esses valores antes de usar em produção.

## Observações operacionais

- Em hosts com ZFS, o backend de swap é `zvol`; não é usado `swapfile`.
- Durante uma migração, se algum swap antigo não puder ser reativado no rollback, o script preserva o novo para manter capacidade de swap. Nessa situação, revise `swapon --show`, o `fstab` e os caminhos informados no erro antes de repetir a operação ou reiniciar.
- O fluxo foi pensado para operação individual no host. Para automação em lote, o ideal é complementar com uma camada de orquestração e validação externa.

## Changelog

O histórico oficial de mudanças fica em [CHANGELOG.md](CHANGELOG.md). As notas de release publicadas no GitHub devem ser derivadas desse arquivo.

## Licença

Este projeto está licenciado sob a [MIT License](LICENSE).

## Créditos

- Desenvolvimento técnico: Codex (OpenAI).
- Direção do projeto, validação prática e testes em ambiente real: Paulo Rocha.
- Base técnica: `swapon(8)` do util-linux, documentação do OpenZFS e práticas operacionais comuns em Debian/Ubuntu.
- Validação estática: ShellCheck.
