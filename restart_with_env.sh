#!/bin/bash

# Перезапуск системы с новыми параметрами из .env
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅${NC} $1"
}

error() {
    echo -e "${RED}❌${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

# Определить команду Docker Compose
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    error "Docker Compose не найден"
    exit 1
fi

log "🔄 Перезапуск системы с новыми параметрами из .env..."

# Проверить наличие .env файла
if [ ! -f ".env" ]; then
    warning ".env файл не найден"
    if [ -f "api/env.prod.example" ]; then
        log "Копирование env.prod.example в .env"
        cp api/env.prod.example .env
        warning "Пожалуйста, отредактируйте .env файл с вашими параметрами"
        echo ""
        echo "Содержимое .env файла:"
        cat .env
        echo ""
        read -p "Нажмите Enter для продолжения после редактирования .env файла..."
    else
        error "Нет примера .env файла"
        exit 1
    fi
fi

# Показать текущие параметры
log "Текущие параметры из .env:"
echo "================================"
cat .env
echo "================================"

# Остановить все контейнеры
log "Остановка всех контейнеров..."
$DOCKER_COMPOSE -f api/docker-compose.prod.yml -p checkpoint-prod down 2>/dev/null || true
$DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full down 2>/dev/null || true

# Очистить неиспользуемые ресурсы
log "Очистка неиспользуемых ресурсов..."
docker system prune -f

# Пересобрать и запустить с новыми параметрами
log "Пересборка и запуск с новыми параметрами..."
$DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full up -d --build

# Ждать запуска
log "Ожидание запуска сервисов (60 секунд)..."
sleep 60

# Проверить статус
log "Проверка статуса контейнеров..."
$DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full ps

# Проверить переменные окружения в контейнерах
log "Проверка переменных окружения в API контейнере..."
docker exec checkpoint-api-full env | grep -E "(KEYDB_|AUTH_|RATE_LIMIT|INSTANCE_ID)" || true

# Тест сервисов
log "Тестирование сервисов..."

# Тест KeyDB
if $DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full exec -T keydb keydb-cli ping | grep -q "PONG"; then
    success "KeyDB работает"
else
    error "KeyDB не работает"
fi

# Тест API
if docker exec checkpoint-api-full wget --quiet --tries=1 --spider http://localhost:8080/health 2>/dev/null; then
    success "API работает"
else
    error "API не работает"
    log "Логи API:"
    docker logs checkpoint-api-full --tail 5
fi

# Тест Nginx
if curl -s --connect-timeout 5 http://localhost/health > /dev/null 2>&1; then
    success "Nginx и API работают"
else
    error "Nginx или API не работают"
    log "Логи Nginx:"
    docker logs checkpoint-nginx-full --tail 10
fi

# Тест с авторизацией
log "Тестирование API с авторизацией..."
response=$(curl -s -w "%{http_code}" -o /dev/null \
    -H 'Authorization: Basic YWRtaW46Y2hlY2twb2ludDIwMjU=' \
    http://localhost/api/v1/checkpoints 2>/dev/null || echo "000")

case $response in
    200)
        success "API с авторизацией работает (HTTP $response)"
        ;;
    401)
        warning "API работает, но авторизация неверная (HTTP $response)"
        ;;
    000)
        error "API недоступен (нет соединения)"
        ;;
    *)
        warning "API ответил с кодом $response"
        ;;
esac

echo ""
success "🎉 Система перезапущена с новыми параметрами!"
echo ""
log "📋 Полезные команды:"
echo "• Статус: $DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full ps"
echo "• Логи: $DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full logs -f"
echo "• Остановка: $DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full down"
echo "• Тест API: curl http://localhost/health"
echo "• Тест с авторизацией: curl -H 'Authorization: Basic YWRtaW46Y2hlY2twb2ludDIwMjU=' http://localhost/api/v1/checkpoints"
echo "• Редактировать .env: nano .env"


