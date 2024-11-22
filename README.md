# Script para configur automáticamente o Swap no Linux

📄 Descrição

Este script foi projetado para automatiza a configuração/criação de memória swap em sistemas Linux. Ele verifica a memória RAM disponível, define o tamanho ideal de swap, realiza verificações importantes (como espaço disponível em disco) e ajusta parâmetros de desempenho do sistema.

Além disso, o script realiza backups automáticos de arquivos críticos antes de qualquer alteração, garantindo segurança nas operações.


⚙️ Recursos
   - Verifica conectividade com a internet antes de atualizar o sistema.
   - Atualiza pacotes e realiza limpeza automática do sistema.
   - Detecta a quantidade de RAM e ajusta o tamanho do swap de forma dinâmica.
   - Verifica espaço em disco antes de criar o arquivo de swap.
   - Cria ou recria arquivos de swap conforme necessário.
   - Realiza backups dos arquivos:
        - /etc/fstab
        - /etc/sysctl.conf
      
   - Adiciona configurações de desempenho no sistema:
        - vm.swappiness=10: Reduz o uso excessivo do swap.
        - vm.vfs_cache_pressure=50: Melhora o balanceamento entre cache e memória de arquivos.
   
   - Contagem regressiva interativa antes de reiniciar o sistema.

🛠️ Pré-requisitos

  - Sistema operacional baseado em Linux.
  - Acesso root ou permissões administrativas.
  - Espaço disponível suficiente para criar o arquivo de swap.

📥 Como Usar

1. Baixe o script ou clone o repositorio

2. Para rodar o script você pode conceder permissão de execução:

   ```bash
    chmod +x swap.sh

4. Execute o script:

   ```Bash
   sudo ./swap.sh

6. Aguarde o script executar, ele irá informa-lo durante todo o processo e alertá-lo caso algo esteja errado (como falta de espaço em disco).


📂 Backups Gerados

   /etc/fstab: Backup no formato /etc/fstab.backup.<data+hora>.
   /etc/sysctl.conf: Backup no formato /etc/sysctl.conf.backup.<data+hora>.

Esses backups garantem que você possa restaurar os arquivos originais em caso de necessidade.

⚠️ Avisos

   Espaço em disco:
        O script verificará o espaço antes de criar o arquivo de swap. Se não houver espaço suficiente, ele abortará a operação.
    Reinicialização:
        Algumas alterações requerem reinicialização. O script inclui uma contagem regressiva interativa para reiniciar automaticamente ou cancelar a operação.

🛡️ Licença

Este projeto está licenciado sob a licença MIT License, permitindo uso, modificação e distribuição livre, desde que sejam mantidos os créditos ao autor.

🤝 Contribuição

Contribuições são bem-vindas! Sinta-se à vontade para abrir issues ou enviar pull requests com melhorias e sugestões.
