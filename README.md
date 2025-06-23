# Script para configurar automáticamente o Swap no Linux


📄 Descrição

Este script foi projetado para automatizar a configuração/criação da memória swap em sistemas Linux. Ele detecta a memória RAM disponível, define o tamanho ideal de swap, verifica o espaço disponível em disco, e ajusta parâmetros de desempenho do sistema.

Além disso, o script realiza backups automáticos de arquivos críticos antes de qualquer alteração, garantindo segurança nas operações. A partir da versão 1.1.4, também detecta e desativa partições de swap antigas, removendo suas entradas do /etc/fstab.



⚙️ Recursos

  ✅ Verifica conectividade com a internet antes de atualizar o sistema.
  
  🔄 Atualiza pacotes e realiza limpeza automática do sistema.
  
  🧠 Detecta a quantidade de RAM e ajusta dinamicamente o tamanho ideal do swap.
  
  💾 Verifica espaço em disco antes de criar ou recriar o arquivo de swap.
  
  🧹 Desativa partições de swap criadas na instalação e remove entradas antigas do /etc/fstab.
  
  🛡️ Cria ou recria arquivos de swap conforme necessário.
  
  📦 Realiza backups automáticos dos arquivos:
  
   - /etc/fstab
  
   - /etc/sysctl.conf
  
  ⚙️ Adiciona configurações de desempenho no sistema:
   
  - vm.swappiness=10 – Reduz o uso excessivo de swap.

  - vm.vfs_cache_pressure=50 – Melhora o balanceamento entre cache e arquivos.

  ⏲️ Contagem regressiva interativa antes de reiniciar o sistema.



🛠️ Pré-requisitos

 -  Sistema operacional baseado em Linux (Debian/Ubuntu).
 -  Acesso root ou permissões administrativas.
 -  Espaço disponível suficiente para criação do arquivo de swap.



📥 Como Usar

1. Baixe o script ou clone o repositorio
2. Para rodar o script você pode conceder permissão de execução:

   ```bash
    chmod +x swap.sh

3. Execute com permissões de root:

   ```Bash
   sudo ./swap.sh
   
Durante a execução, o script informará todas as ações realizadas e alertará em caso de problemas (como falta de espaço em disco).



📂 Backups Gerados

  - /etc/fstab: Backup no formato /etc/fstab.backup.<data+hora>.
  - /etc/sysctl.conf: Backup no formato /etc/sysctl.conf.backup.<data+hora>.

Esses backups garantem que você possa restaurar os arquivos originais em caso de necessidade.



⚠️ Avisos

   💽 Espaço em disco: o script checa antes de criar o swap. Caso não haja espaço suficiente, a operação será abortada.
   🔁 Reinicialização: algumas configurações exigem reinício. O script oferece contagem regressiva e opção para cancelar.



🛡️ Licença

Este projeto está licenciado sob a licença MIT License, permitindo uso, modificação e distribuição livre, desde que sejam mantidos os créditos ao autor.



🤝 Contribuição

Contribuições são bem-vindas! Sinta-se à vontade para abrir issues ou enviar pull requests com melhorias e sugestões.
