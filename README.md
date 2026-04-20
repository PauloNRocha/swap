# Provisionamento de SWAP para Debian e Ubuntu
<p align="center">
  <img src="https://img.shields.io/badge/version-1.5.5-blue.svg" alt="Versão">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="Licença">
  <img src="https://img.shields.io/badge/platform-Linux-lightgrey.svg" alt="Plataforma">
  <img src="https://img.shields.io/badge/shell-Bash-yellow.svg" alt="Shell">
</p>

Script em Bash para provisionar e ajustar SWAP em hosts Debian e Ubuntu. O fluxo detecta o backend compatível com o filesystem em uso, aplica a configuração persistente no sistema e registra a execução em log.

## Sumário

- [Visão geral](#visão-geral)
- [Compatibilidade](#compatibilidade)
- [Escopo operacional](#escopo-operacional)
- [Pré-requisitos](#pré-requisitos)
- [Operação](#operação)
- [Fluxo de execução](#fluxo-de-execução)
- [Artefatos e alterações](#artefatos-e-alterações)
- [Validação pós-execução](#validação-pós-execução)
- [Limitações](#limitações)
- [Observações operacionais](#observações-operacionais)
- [Licença](#licença)
- [Autor](#autor)

## Visão geral

O `swap.sh` automatiza uma rotina operacional comum em servidores: criar ou ajustar a área de swap com persistência no boot e com validações mínimas antes da aplicação. O comportamento atual cobre dois cenários:

- Filesystems convencionais: usa `swapfile` em `/swapfile`.
- Sistema raiz em ZFS: usa `zvol` em `/dev/zvol/<pool>/swap`.

Além da criação do swap, o script:

- cria backup dos arquivos de configuração alterados;
- atualiza o `/etc/fstab`;
- ajusta parâmetros básicos de memória virtual em `/etc/sysctl.conf`;
- registra a execução em `/var/log/swap_script.log`.

## Compatibilidade

- Debian e Ubuntu, ou distribuições compatíveis com `apt`.
- Execução como `root` ou com `sudo`.
- Suporte a ZFS no sistema raiz com criação de swap via `zvol`.
- Suporte a tamanhos personalizados em megabytes (`M`) ou gigabytes (`G`), com sufixo em maiúsculas ou minúsculas.

## Escopo operacional

- Detecta a quantidade de RAM instalada.
- Define um tamanho sugerido de swap quando `--size` não é informado.
- Verifica espaço disponível antes de tentar criar o swap.
- Identifica se o sistema está em ZFS para usar `zvol` em vez de `swapfile`.
- Desativa partições de swap antigas e remove entradas antigas do `/etc/fstab` quando necessário.
- Cria e ativa o swap.
- Adiciona a persistência no `/etc/fstab`.
- Ajusta os parâmetros abaixo em `/etc/sysctl.conf`: `vm.swappiness=10`, `vm.vfs_cache_pressure=50`, `vm.dirty_ratio=15`, `vm.dirty_background_ratio=5`.
- Cria backup de arquivos sensíveis antes de modificar a configuração.

## Pré-requisitos

- Sistema baseado em Debian ou Ubuntu.
- Permissões administrativas.
- Espaço em disco suficiente para o tamanho de swap desejado.
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

Ajuda:

```bash
sudo ./swap.sh --help
```

## Fluxo de execução

Durante a execução, o script segue esta ordem:

1. Valida privilégios administrativos.
2. Verifica dependências necessárias.
3. Cria backups de `/etc/fstab` e `/etc/sysctl.conf`.
4. Detecta a RAM total e calcula ou valida o tamanho do swap.
5. Verifica espaço disponível em disco.
6. Define a estratégia de swap.
   `swapfile` em `/swapfile` para filesystems comuns.
   `zvol` em `/dev/zvol/<pool>/swap` quando `/` está em ZFS.
7. Desativa swaps antigos que não correspondem ao alvo escolhido.
8. Cria e ativa o novo swap.
9. Atualiza o `/etc/fstab`.
10. Ajusta parâmetros de desempenho em `/etc/sysctl.conf`.
11. Exibe um resumo final e oferece a opção de reiniciar o sistema.

## Artefatos e alterações

Arquivos modificados pelo script:

- `/etc/fstab`
- `/etc/sysctl.conf`

Artefatos criados pelo script:

- `/var/log/swap_script.log`
- `/swapfile` em sistemas sem ZFS, quando esse for o backend escolhido
- `/dev/zvol/<pool>/swap` em sistemas com ZFS

Backups gerados automaticamente:

- `/etc/fstab.backup.<data_hora>`
- `/etc/sysctl.conf.backup.<data_hora>`

## Validação pós-execução

Após a aplicação, valide o estado final com:

```bash
swapon --show
free -mh
grep -E 'swapfile|/dev/zvol/.*/swap' /etc/fstab
tail -n 50 /var/log/swap_script.log
```

Resultado esperado:

- `swapon --show` deve listar o swap ativo.
- `free -mh` deve exibir swap total maior que zero.
- O `/etc/fstab` deve conter apenas a entrada compatível com o backend em uso.

## Limitações

- O projeto é direcionado a ambientes com `apt`; outras distribuições não são alvo do script.
- O foco é criação e ajuste inicial de swap, não gerenciamento avançado de múltiplos dispositivos.
- O script altera parâmetros de memória virtual com valores definidos no próprio código; se o seu ambiente tiver política própria de tuning, revise esses valores antes de usar em produção.

## Observações operacionais

- Em hosts com ZFS, o backend de swap é `zvol`; não é usado `swapfile`.
- O script altera configuração persistente do sistema. Revise o conteúdo de `/etc/fstab` e `/etc/sysctl.conf` se o host já possuir política própria de baseline.
- O fluxo foi pensado para operação individual no host. Para automação em lote, o ideal é complementar com uma camada de orquestração e validação externa.

## Licença

Este projeto está licenciado sob a [MIT License](LICENSE).

## Autor

Paulo Rocha
