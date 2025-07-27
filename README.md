# Script para Configuração Automática de SWAP no Linux

📄 ## Descrição

Este script foi projetado para automatizar a configuração e criação da memória SWAP em sistemas Linux baseados em Debian/Ubuntu. Ele detecta a memória RAM disponível, define um tamanho de SWAP ideal, verifica o espaço em disco e ajusta parâmetros de desempenho do sistema para otimizar o uso da memória.

O script realiza backups automáticos de arquivos críticos, gera um log detalhado das operações e é capaz de desativar partições de SWAP antigas, gerenciando o arquivo `/swapfile` de forma inteligente e segura.

---

⚙️ ## Recursos Principais

-   **Configuração Inteligente:** Detecta a RAM e ajusta o tamanho do SWAP de acordo com as boas práticas.
-   **Flexibilidade de Tamanho:** Permite definir um tamanho de SWAP personalizado com a flag `--size`, aceitando unidades em **Gigabytes (G)** e **Megabytes (M)**.
-   **Log de Execução:** Salva um registro detalhado de todas as operações em `/var/log/swap_script.log` para fácil auditoria e depuração.
-   **Verificação de Espaço:** Garante que há espaço em disco suficiente antes de criar o arquivo de SWAP.
-   **Gerenciamento de SWAP Antigo:** Desativa partições de SWAP existentes e remove suas entradas do `/etc/fstab`.
-   **Otimização de Performance:** Ajusta `vm.swappiness` e `vm.vfs_cache_pressure` para um uso mais eficiente da memória.
-   **Segurança:** Cria backups automáticos de `/etc/fstab` e `/etc/sysctl.conf` antes de modificá-los.
-   **Robustez:** Utiliza `dd` como alternativa caso `fallocate` não seja suportado pelo sistema de arquivos.
-   **Interativo:** Solicita confirmação antes de reiniciar o sistema.

---

🛠️ ## Pré-requisitos

-   Sistema operacional baseado em **Debian** ou **Ubuntu**.
-   Acesso **root** ou permissões de superusuário (`sudo`).
-   Espaço em disco suficiente para a criação do arquivo de SWAP.

---

📥 ## Como Usar

1.  **Clone o repositório ou baixe o script:**
    ```bash
    git clone https://github.com/PauloNRocha/swap.git
    cd swap
    # O script principal está localizado no arquivo swap.sh
    ```

2.  **Conceda permissão de execução ao script:**
    ```bash
    chmod +x swap.sh
    ```

3.  **Execute com permissões de root:**

    *   **Para configuração automática:**
        ```bash
        sudo ./swap.sh
        ```

    *   **Para definir um tamanho de SWAP específico:**
        ```bash
        # Exemplo com Gigabytes
        sudo ./swap.sh --size 4G

        # Exemplo com Megabytes
        sudo ./swap.sh --size 512M
        ```

    *   **Para ver as opções de ajuda:**
        ```bash
        sudo ./swap.sh --help
        ```

---

📂 ## Arquivos Gerados

-   **Backups:**
    -   `/etc/fstab` é salvo como `/etc/fstab.backup.<data+hora>`.
    -   `/etc/sysctl.conf` é salvo como `/etc/sysctl.conf.backup.<data+hora>`.
-   **Log de Execução:**
    -   Um log detalhado de todas as operações é salvo em `/var/log/swap_script.log`.

---

⚠️ ## Avisos Importantes

-   **Ambiente de Teste:** É altamente recomendável executar este script em um ambiente de teste (como uma Máquina Virtual) antes de aplicá-lo em um sistema de produção.
-   **Reinicialização:** Algumas configurações exigem a reinicialização do sistema para serem totalmente aplicadas. O script oferecerá essa opção ao final da execução.

---

🛡️ ## Licença

Este projeto está licenciado sob a [MIT License](LICENSE), permitindo uso, modificação e distribuição livre.

---

🤝 ## Contribuição

Contribuições são muito bem-vindas! Sinta-se à vontade para abrir *issues* ou enviar *pull requests* com melhorias, correções e sugestões.
