# Script de Configuração Automática de SWAP
<p align="center">
  <img src="https://img.shields.io/badge/version-1.5.2-blue.svg" alt="Versão">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="Licença">
  <img src="https://img.shields.io/badge/platform-Linux-lightgrey.svg" alt="Plataforma">
  <img src="https://img.shields.io/badge/shell-Bash-yellow.svg" alt="Shell">
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/2f461774-a954-4084-9c88-da893a326e8f" alt="Banner do Script" width="600">
</p>

## 📄 Descrição

Este script automatiza a configuração da memória **SWAP** em sistemas Linux baseados em **Debian/Ubuntu**. Ele detecta a RAM disponível, define um tamanho de SWAP ideal, verifica o espaço em disco e ajusta parâmetros de desempenho do sistema para otimizar o uso da memória de forma segura e eficiente.

[swap](https://github.com/user-attachments/assets/2f461774-a954-4084-9c88-da893a326e8f)

---

## 📜 Sumário

- [Recursos Principais](#-recursos-principais)
- [Pré-requisitos](#-pré-requisitos)
- [Como Usar](#-como-usar)
- [Arquivos Gerados](#-arquivos-gerados)
- [Licença](#-licença)
- [Autor](#-autor)

---

## ✨ Recursos Principais

-   **Configuração Inteligente:** Detecta a RAM e ajusta o tamanho do SWAP de acordo com as boas práticas.
-   **Flexibilidade de Tamanho:** Permite definir um tamanho de SWAP personalizado com a flag `--size`, aceitando unidades em **Gigabytes (G)** e **Megabytes (M)**.
-   **Log de Execução:** Salva um registro detalhado de todas as operações em `/var/log/swap_script.log` para fácil auditoria e depuração.
-   **Verificação de Espaço:** Garante que há espaço em disco suficiente antes de criar o arquivo de SWAP.
-   **Gerenciamento de SWAP Antigo:** Desativa partições de SWAP existentes e remove suas entradas do `/etc/fstab`.
-   **Otimização de Performance:** Ajusta `vm.swappiness` e `vm.vfs_cache_pressure` para um uso mais eficiente da memória.
-   **Segurança:** Cria backups automáticos de `/etc/fstab` e `/etc/sysctl.conf` **antes** de qualquer modificação.
-   **Robustez:** Utiliza `dd` como alternativa caso `fallocate` não seja suportado pelo sistema de arquivos.
-   **Interativo:** Solicita confirmação do usuário antes de reiniciar o sistema.

---

## 🛠️ Pré-requisitos

-   Sistema operacional baseado em **Debian** ou **Ubuntu**.
-   Acesso **root** ou permissões de superusuário (`sudo`).
-   Espaço em disco suficiente para a criação do arquivo de SWAP.

---

## 📥 Como Usar

1.  **Clone o repositório:**
    ```bash
    git clone https://github.com/PauloNRocha/swap.git
    cd swap
    ```

2.  **Conceda permissão de execução:**
    ```bash
    chmod +x swap.sh
    ```

3.  **Execute com permissões de root:**

    *   Para **configuração automática**:
        ```bash
        sudo ./swap.sh
        ```

    *   Para definir um **tamanho específico**:
        ```bash
        # Exemplo com Gigabytes
        sudo ./swap.sh --size 4G

        # Exemplo com Megabytes
        sudo ./swap.sh --size 512M
        ```

    *   Para ver as **opções de ajuda**:
        ```bash
        sudo ./swap.sh --help
        ```

---

## 📂 Arquivos Gerados

-   **Backups:**
    -   `/etc/fstab` é salvo como `/etc/fstab.backup.<data+hora>`.
    -   `/etc/sysctl.conf` é salvo como `/etc/sysctl.conf.backup.<data+hora>`.
-   **Log de Execução:**
    -   Um log detalhado de todas as operações é salvo em `/var/log/swap_script.log`.

---

## 🛡️ Licença

Este projeto está licenciado sob a **[MIT License](LICENSE)**, permitindo uso, modificação e distribuição livre.

---

## 👨‍💻 Autor

Desenvolvido por **Paulo Rocha + IA** — 2025