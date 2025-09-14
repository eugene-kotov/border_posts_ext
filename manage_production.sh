#!/bin/bash

# Главный скрипт управления Checkpoint System
# Использование: ./manage_production.sh [команда]

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
    echo -e "${BLUE}Checkpoint System - Управление продакшн сервером${NC}"
    echo "=================================================="
    echo ""
    echo "Использование: ./manage_production.sh [команда]"
    echo ""
    echo "Доступные команды:"
    echo "  ${GREEN}update${NC}     - Обновить систему из git (./update_production.sh)"
    echo "  ${GREEN}restart${NC}    - Перезапустить систему (./restart_production.sh)"
    echo "  ${GREEN}rollback${NC}   - Откатить к предыдущей версии (./rollback_production.sh)"
    echo "  ${GREEN}status${NC}     - Проверить статус системы (./status_production.sh)"
    echo "  ${GREEN}logs${NC}       - Показать логи системы"
    echo "  ${GREEN}monitor${NC}    - Мониторинг ресурсов (./monitor_resources.sh)"
    echo "  ${GREEN}backup${NC}     - Создать бэкап данных"
    echo "  ${GREEN}clean${NC}      - Очистить неиспользуемые Docker ресурсы"
    echo "  ${GREEN}help${NC}       - Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  ./manage_production.sh update main"
    echo "  ./manage_production.sh rollback abc123"
    echo "  ./manage_production.sh status"
}

# Проверка, что мы в правильной директории
if [ ! -f "docker-compose.full.yml" ]; then
    echo -e "${RED}Ошибка: Запустите скрипт из директории release/${NC}"
    exit 1
fi

# Обработка команд
case "${1:-help}" in
    "update")
        shift
        ./update_production.sh "$@"
        ;;
    "restart")
        ./restart_production.sh
        ;;
    "rollback")
        shift
        ./rollback_production.sh "$@"
        ;;
    "status")
        ./status_production.sh
        ;;
    "logs")
        echo -e "${BLUE}📋 Логи системы:${NC}"
        docker-compose -f docker-compose.full.yml -p checkpoint-full logs --tail=50 -f
        ;;
    "monitor")
        ./monitor_resources.sh
        ;;
    "backup")
        echo -e "${BLUE}💾 Создание бэкапа...${NC}"
        BACKUP_DIR="../backups/manual_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        # Бэкап KeyDB
        docker-compose -f docker-compose.full.yml -p checkpoint-full exec -T keydb keydb-cli --rdb /tmp/dump.rdb BGSAVE
        docker cp checkpoint-keydb-full:/tmp/dump.rdb "$BACKUP_DIR/keydb_dump.rdb" 2>/dev/null || echo "Не удалось создать бэкап KeyDB"
        
        # Бэкап конфигурации
        cp -r . "$BACKUP_DIR/config"
        
        echo -e "${GREEN}✅ Бэкап создан в $BACKUP_DIR${NC}"
        ;;
    "clean")
        echo -e "${BLUE}🧹 Очистка Docker ресурсов...${NC}"
        read -p "Удалить неиспользуемые образы? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker image prune -f
        fi
        
        read -p "Удалить неиспользуемые контейнеры? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker container prune -f
        fi
        
        read -p "Удалить неиспользуемые тома? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker volume prune -f
        fi
        
        echo -e "${GREEN}✅ Очистка завершена${NC}"
        ;;
    "help"|*)
        show_help
        ;;
esac
