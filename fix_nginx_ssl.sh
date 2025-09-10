#!/bin/bash

# Исправление проблем с Nginx SSL
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

log "🔧 Исправление проблем с Nginx SSL..."

# Остановить Nginx
log "Остановка Nginx..."
docker stop checkpoint-nginx-full 2>/dev/null || true

# Перезапустить Nginx с исправленной конфигурацией
log "Перезапуск Nginx..."

# Определить команду Docker Compose
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    error "Docker Compose не найден"
    exit 1
fi

$DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full up -d nginx

# Ждать запуска
sleep 10

# Проверить статус
log "Проверка статуса Nginx..."
if docker ps | grep checkpoint-nginx-full | grep -q "Up"; then
    success "Nginx запущен"
else
    error "Nginx не запустился"
    log "Логи Nginx:"
    docker logs checkpoint-nginx-full --tail 10
fi

# Проверить API инстансы
log "Проверка API инстансов..."
for i in {1..3}; do
    if docker exec checkpoint-api${i}-full wget --quiet --tries=1 --spider http://localhost:8080/health 2>/dev/null; then
        success "API$i работает"
    else
        error "API$i не работает"
        log "Логи API$i:"
        docker logs checkpoint-api${i}-full --tail 5
    fi
done

# Тест HTTP
log "Тестирование HTTP..."
if curl -s --connect-timeout 5 http://localhost/health > /dev/null 2>&1; then
    success "HTTP API работает"
else
    error "HTTP API не работает"
fi

echo ""
log "📋 Команды для диагностики:"
echo "• Логи Nginx: docker logs checkpoint-nginx-full"
echo "• Логи API1: docker logs checkpoint-api1-full"
echo "• Логи API2: docker logs checkpoint-api2-full"
echo "• Логи API3: docker logs checkpoint-api3-full"
echo "• Статус: $DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full ps"
echo "• Тест API: curl http://localhost/health"
