#!/bin/bash
# ─────────────────────────────────────────────────────────────
# Checkpoint System — VPS Initial Setup (Podman Quadlets)
# ─────────────────────────────────────────────────────────────
#
# Поддерживаемые ОС:
#   - Ubuntu 22.04+ / Debian 12+
#   - AlmaLinux 9+ / Rocky Linux 9+
#   - Fedora 39+
#
# Минимальные требования VPS:
#   - 1 vCPU
#   - 512 MB RAM (рекомендовано 1 GB)
#   - 5 GB disk (рекомендовано 10 GB)
#
# Использование:
#   chmod +x setup-vps.sh
#   ./setup-vps.sh
#
# ─────────────────────────────────────────────────────────────

set -euo pipefail

# ─── Цвета ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; }

# ─── Проверки ───
check_root() {
    if [[ $EUID -eq 0 ]]; then
        err "Не запускайте от root. Скрипт сам вызовет sudo где нужно."
        exit 1
    fi
}

check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        log "ОС: $PRETTY_NAME"
    else
        err "Не удалось определить ОС"
        exit 1
    fi
}

check_resources() {
    local cpus mem_mb disk_gb
    cpus=$(nproc)
    mem_mb=$(free -m | awk '/Mem:/{print $2}')
    disk_gb=$(df -BG / | awk 'NR==2{gsub("G",""); print $4}')

    log "Ресурсы: ${cpus} vCPU, ${mem_mb} MB RAM, ${disk_gb} GB disk"

    if [[ $mem_mb -lt 400 ]]; then
        err "Недостаточно RAM: ${mem_mb} MB (минимум 512 MB)"
        exit 1
    fi
    if [[ $disk_gb -lt 3 ]]; then
        err "Недостаточно диска: ${disk_gb} GB (минимум 5 GB)"
        exit 1
    fi
    ok "Ресурсы достаточны"
}

# ─── Определение пакетного менеджера ───
detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        PKG_MGR="apt"
    elif command -v dnf &>/dev/null; then
        PKG_MGR="dnf"
    elif command -v yum &>/dev/null; then
        PKG_MGR="yum"
    else
        err "Не найден пакетный менеджер (apt/dnf/yum)"
        exit 1
    fi
    log "Пакетный менеджер: $PKG_MGR"
}

# ─── Установка Podman ───
install_podman() {
    if command -v podman &>/dev/null; then
        ok "Podman уже установлен: $(podman --version)"
        return
    fi

    log "Устанавливаю Podman..."
    case $PKG_MGR in
        apt)
            sudo apt-get update -qq
            sudo apt-get install -y -qq podman podman-compose slirp4netns uidmap fuse-overlayfs
            ;;
        dnf|yum)
            sudo $PKG_MGR install -y podman podman-compose slirp4netns fuse-overlayfs
            ;;
    esac
    ok "Podman установлен: $(podman --version)"
}

# ─── Установка дополнительных утилит ───
install_tools() {
    log "Устанавливаю утилиты (make, curl, git, python3)..."
    case $PKG_MGR in
        apt)
            sudo apt-get install -y -qq make curl git python3 jq
            ;;
        dnf|yum)
            sudo $PKG_MGR install -y make curl git python3 jq
            ;;
    esac
    ok "Утилиты установлены"
}

# ─── Настройка rootless ───
setup_rootless() {
    local user=$(whoami)

    # subuid/subgid
    if grep -q "^${user}:" /etc/subuid 2>/dev/null; then
        ok "subuid/subgid уже настроены для $user"
    else
        log "Настраиваю subuid/subgid для $user..."
        sudo usermod --add-subuids 100000-165535 "$user"
        sudo usermod --add-subgids 100000-165535 "$user"
        ok "subuid/subgid настроены"
    fi

    # loginctl enable-linger (чтобы сервисы работали без SSH)
    if loginctl show-user "$user" 2>/dev/null | grep -q "Linger=yes"; then
        ok "Linger уже включён для $user"
    else
        log "Включаю linger для $user..."
        sudo loginctl enable-linger "$user"
        ok "Linger включён — сервисы будут работать после logout"
    fi
}

# ─── Проверка cgroups v2 ───
check_cgroups() {
    local cg_type
    cg_type=$(stat -fc %T /sys/fs/cgroup/ 2>/dev/null || echo "unknown")
    if [[ "$cg_type" == "cgroup2fs" ]]; then
        ok "cgroups v2 — resource limits будут работать"
    else
        warn "cgroups v1 ($cg_type) — resource limits могут не работать"
        warn "Для cgroups v2 добавьте в GRUB: systemd.unified_cgroup_hierarchy=1"
    fi
}

# ─── Настройка Podman socket (для совместимости с docker CLI) ───
setup_podman_socket() {
    log "Настраиваю Podman socket..."
    systemctl --user enable --now podman.socket 2>/dev/null || true
    ok "Podman socket: $XDG_RUNTIME_DIR/podman/podman.sock"
}

# ─── Настройка private registry (Angie) ───
setup_registry() {
    local registries_conf="$HOME/.config/containers/registries.conf"
    if [[ -f "$registries_conf" ]] && grep -q "docker.angie.software" "$registries_conf" 2>/dev/null; then
        ok "Registry docker.angie.software уже настроен"
        return
    fi

    log "Настраиваю docker.angie.software registry..."
    mkdir -p "$(dirname "$registries_conf")"
    cat >> "$registries_conf" << 'EOF'

[[registry]]
location = "docker.angie.software"
insecure = false
EOF
    ok "Registry настроен"
}

# ─── Создание директории systemd для Quadlets ───
setup_quadlet_dir() {
    local quadlet_dir="$HOME/.config/containers/systemd"
    mkdir -p "$quadlet_dir"
    ok "Quadlet directory: $quadlet_dir"
}

# ─── Тестирование Podman ───
test_podman() {
    log "Тестирую Podman..."
    if podman run --rm docker.io/library/alpine:latest echo "podman works" 2>/dev/null | grep -q "podman works"; then
        ok "Podman rootless работает"
    else
        err "Podman не работает. Проверьте: podman info"
        exit 1
    fi
}

# ─── Проверка портов ───
check_ports() {
    local port80 port443
    port80=$(ss -tlnp | grep ":80 " | head -1 || true)
    port443=$(ss -tlnp | grep ":443 " | head -1 || true)

    if [[ -n "$port80" ]]; then
        warn "Порт 80 занят: $port80"
        warn "Освободите перед запуском: sudo systemctl stop nginx/apache2"
    else
        ok "Порт 80 свободен"
    fi

    if [[ -n "$port443" ]]; then
        warn "Порт 443 занят: $port443"
    else
        ok "Порт 443 свободен"
    fi
}

# ─── Firewall ───
setup_firewall() {
    if command -v ufw &>/dev/null; then
        log "Настраиваю UFW firewall..."
        sudo ufw allow 80/tcp comment "Checkpoint HTTP" 2>/dev/null || true
        sudo ufw allow 443/tcp comment "Checkpoint HTTPS" 2>/dev/null || true
        ok "UFW: порты 80, 443 открыты"
    elif command -v firewall-cmd &>/dev/null; then
        log "Настраиваю firewalld..."
        sudo firewall-cmd --permanent --add-service=http 2>/dev/null || true
        sudo firewall-cmd --permanent --add-service=https 2>/dev/null || true
        sudo firewall-cmd --reload 2>/dev/null || true
        ok "Firewalld: HTTP/HTTPS разрешены"
    else
        warn "Firewall не найден — убедитесь, что порты 80/443 открыты"
    fi
}

# ─── Git clone проекта ───
setup_project() {
    local project_dir="$HOME/checkpoint-system"

    if [[ -d "$project_dir" ]]; then
        ok "Проект уже клонирован: $project_dir"
    else
        log "Клонирую проект..."
        echo ""
        echo "  Укажите Git URL проекта (или Enter для пропуска):"
        read -r git_url
        if [[ -n "$git_url" ]]; then
            git clone "$git_url" "$project_dir"
            ok "Проект клонирован в $project_dir"
        else
            warn "Пропуск клонирования. Скопируйте проект в $project_dir вручную"
        fi
    fi
}

# ─── Итоговый отчёт ───
print_summary() {
    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ VPS Setup Complete${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Podman:    $(podman --version 2>/dev/null || echo 'not installed')"
    echo "  User:      $(whoami)"
    echo "  Linger:    $(loginctl show-user $(whoami) 2>/dev/null | grep Linger= || echo 'unknown')"
    echo "  cgroups:   $(stat -fc %T /sys/fs/cgroup/ 2>/dev/null)"
    echo "  Quadlets:  $HOME/.config/containers/systemd/"
    echo ""
    echo "  Следующие шаги:"
    echo "  ────────────────"
    echo "  1. cd ~/checkpoint-system   (или ваш путь к проекту)"
    echo "  2. git checkout feature/podman-quadlets"
    echo "  3. make install             # Установить Quadlet файлы"
    echo "  4. make build               # Собрать образы API и Parser"
    echo "  5. make start               # Запустить систему"
    echo "  6. make health              # Проверить здоровье"
    echo "  7. make test                # Тест API"
    echo ""
    echo "  Полезные команды:"
    echo "  ────────────────"
    echo "  make status                 # Статус сервисов"
    echo "  make logs                   # Логи (все)"
    echo "  make stats                  # Потребление ресурсов"
    echo "  make auto-update            # Включить авто-обновление"
    echo ""
}

# ─── Main ───
main() {
    echo ""
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║  Checkpoint System — VPS Setup (Podman Quadlets) ║"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo ""

    check_root
    check_os
    check_resources
    detect_pkg_manager

    install_podman
    install_tools
    setup_rootless
    check_cgroups
    setup_podman_socket
    setup_registry
    setup_quadlet_dir
    check_ports
    setup_firewall
    test_podman
    setup_project

    print_summary
}

main "$@"
