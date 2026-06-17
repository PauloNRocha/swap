# Changelog

## [Não lançado]

## [1.5.8] - 2026-06-16

### Corrigido

- Corrige permissões indevidas em `/etc/fstab` após a normalização das entradas de swap.
- Garante que `/etc/fstab` permaneça com dono `root:root` e modo `0644`, padrão esperado em Debian/Ubuntu e necessário para componentes como Snap lerem a configuração do sistema.
- Corrige o caso em que o conteúdo do `/etc/fstab` já estava correto, mas as permissões continuavam restritivas.

## [1.5.7] - 2026-06-16

### Corrigido

- Evita recriação desnecessária do swap quando o tamanho ativo difere do alvo apenas por overhead operacional do `mkswap`.
- Torna a normalização do `/etc/fstab` idempotente, evitando reescrita e mensagens de remoção quando a entrada existente já está correta.
- Remove o aviso de log sem permissão antes do erro de execução sem `sudo`.
- Interrompe a exibição de mensagens de limpeza após execuções bem-sucedidas.

### Alterado

- Melhora o resumo final com backend, caminho alvo, tamanho alvo e comandos rápidos de validação.
- Atualiza os créditos do projeto.

## [1.5.6] - 2026-06-16

### Corrigido

- Corrige a mensagem exibida quando o swap existente é maior que o tamanho alvo.

### Alterado

- Normaliza o `/etc/fstab` para manter apenas uma entrada persistente de swap.
- Desativa qualquer swap ativo fora do alvo selecionado, não apenas partições de swap.

## [1.5.5] - 2026-02-20

### Corrigido

- Corrige a falha de ativação de swap em ZFS causada por `swapon: ... appears to have holes`.

### Alterado

- Usa `zvol` do ZFS (`/dev/zvol/<pool>/swap`) em vez de `swapfile` em sistemas com raiz em ZFS.
- Detecta o filesystem raiz e seleciona automaticamente o backend adequado.
- Melhora a detecção do dispositivo zvol, incluindo aliases como `/dev/zvol/...` e `/dev/zdX`.
- Persiste o alvo de swap selecionado no `/etc/fstab`.
- Remove recursos ZFS incompletos quando a criação do zvol falha.

## [1.5.4] - 2026-02-20

### Corrigido

- Adiciona tratamento inicial para falhas de swapfile em ZFS causadas por arquivos com holes.
- Adiciona fallback para recriar o swapfile com `dd` quando o `swapon` detecta holes após `fallocate`.

### Alterado

- Torna `fallocate` opcional.
- Melhora mensagens de erro em falhas de ativação do swap.
- Ajusta a qualidade do script com base no retorno do ShellCheck.

## [1.5.3] - 2025-08-19

### Corrigido

- Garante que `--size` redimensione o swap para o alvo solicitado mesmo quando o swap existente é maior.

## [1.5.2] - 2025-07-27

### Corrigido

- Move os backups de `/etc/fstab` e `/etc/sysctl.conf` para o início da execução, antes de qualquer modificação no sistema.
- Evita que backups sejam criados depois de uma alteração de configuração.

### Alterado

- Adiciona `blkid` às verificações iniciais de dependências.
- Melhora a confiabilidade na limpeza de partições antigas de swap.

## [1.5.1] - 2025-07-04

### Corrigido

- Reorganiza o script para que as funções sejam definidas antes do uso.
- Corrige um erro persistente de sintaxe da versão `1.5.0`.
- Marca arquivos de swap incompletos durante a criação para que a limpeza possa removê-los com segurança em caso de falha.

### Alterado

- Remove a dependência não utilizada de `ping`.

## [1.5.0] - 2025-07-04

### Adicionado

- Adiciona suporte a valores de `--size` em megabytes (`M`) e gigabytes (`G`).
- Adiciona log de execução em `/var/log/swap_script.log` quando as permissões permitem.

### Alterado

- Refatora a estrutura do script para suportar os novos recursos de tamanho e log.

## [1.4.3] - 2025-07-04

### Corrigido

- Evita execução duplicada de `cleanup` em erros.
- Valida `--size` mais cedo e interrompe a execução quando o formato é inválido.

## [1.4.2] - 2025-07-04

### Corrigido

- Corrige a ordem das funções para que opções inválidas de CLI não acionem mais `error_exit: command not found`.
- Melhora a validação da entrada `--size`.

## [1.4.1] - 2025-07-04

### Removido

- Remove a atualização automática do sistema (`apt update` e `apt upgrade`) do fluxo do script.

### Alterado

- Revisa o `README.md` para refletir opções atuais como `--size` e `--help`.

## [1.4.0] - 2025-07-04

### Adicionado

- Adiciona a opção `--size <tamanho>`.
- Adiciona a opção `--help`.
- Adiciona fallback com `dd` quando `fallocate` não é suportado.
- Adiciona manipulador `cleanup` via `trap`.
- Adiciona helper centralizado de backup para `/etc/fstab` e `/etc/sysctl.conf`.
- Adiciona variável de versão do script usada pelo banner.

### Alterado

- Simplifica o fluxo de confirmação de reinício.

## [1.3.1] - 2025-06-26

### Corrigido

- Corrige a verificação de conectividade com a internet.
- Corrige erro de sintaxe ao comparar `total_ram_mb` indefinida.
- Corrige problemas de expansão de variáveis.
- Corrige falha na exibição do banner.
- Melhora a validação de `total_ram_kb`.

### Alterado

- Torna as verificações de conectividade mais seguras.
- Melhora as mensagens no terminal e o uso de cores.
- Melhora a segurança da execução.

### Observações

- A versão publicada também documenta `1.3.0`, incluindo limpeza de partições de swap, backup do `/etc/fstab`, ajustes em `sysctl.conf`, mensagens coloridas e reorganização do script.

## [1.2.0] - 2025-06-26

### Adicionado

- Adiciona tratamento para falha imediata.
- Adiciona validação de dependências.
- Adiciona tratamento dedicado de erros.
- Adiciona timeouts nas verificações de conectividade.
- Adiciona validação da detecção de RAM.
- Adiciona cálculo mais seguro do tamanho do swap.
- Adiciona margem de segurança para espaço em disco.
- Adiciona backups antes das modificações.
- Adiciona parâmetros de kernel `dirty_ratio` e `dirty_background_ratio`.
- Adiciona mensagens mais claras no terminal.
- Adiciona resumo da configuração antes do reinício.
- Adiciona validação do prompt de reinício.
- Adiciona banner.
- Adiciona remoção de `/swapfile` órfão.
- Adiciona aplicação imediata de `sysctl`.
- Adiciona arrays associativos e funções auxiliares.

### Alterado

- Reduz a contagem regressiva de reinício para 10 segundos.
- Melhora o parsing de dispositivos.
- Melhora os comentários do código.

## [1.1.4] - 2025-06-23

### Adicionado

- Detecta partições de swap ativas.
- Desativa partições de swap ativas antes de criar o novo swapfile.
- Remove entradas antigas de partições de swap do `/etc/fstab` usando UUID quando disponível.

### Alterado

- Garante que apenas o swapfile gerenciado pelo script permaneça ativo após a execução.

### Observações

- A versão publicada também documenta `1.1.3`, incluindo refatoração da lógica de seleção do tamanho do swap.

## [1.1.2] - 2025-06-23

### Corrigido

- Suprime a saída de `mkswap` para manter a interface limpa.
- Corrige a seleção do tamanho do swap com base na RAM.

### Observações

- A versão publicada também documenta `1.1.1` e `1.1.0`, incluindo mensagens coloridas, verificações de compatibilidade com `apt`, simplificação do reinício e consolidação dos parâmetros de `sysctl`.

## [1.0.0] - 2025-06-23

### Adicionado

- Versão inicial.
