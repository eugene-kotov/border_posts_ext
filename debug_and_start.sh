#!/bin/bash

# Диагностика и запуск системы
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

log "🔍 Диагностика и запуск Checkpoint системы..."

# Проверка Docker
log "Проверка Docker..."
if command -v docker &> /dev/null; then
    success "Docker установлен: $(docker --version)"
else
    error "Docker не установлен"
    exit 1
fi

# Проверка Docker Compose
log "Проверка Docker Compose..."
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
    success "Docker Compose v2: $(docker compose version --short)"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
    success "Docker Compose v1: $(docker-compose --version)"
else
    error "Docker Compose не установлен"
    exit 1
fi

# Проверка файлов
log "Проверка конфигурационных файлов..."
if [ -f "docker-compose.full.yml" ]; then
    success "docker-compose.full.yml найден"
else
    error "docker-compose.full.yml не найден"
    exit 1
fi

if [ -f "nginx.loadbalancer.conf" ]; then
    success "nginx.loadbalancer.conf найден"
else
    error "nginx.loadbalancer.conf не найден"
fi

# Остановка существующих контейнеров
log "Остановка существующих контейнеров..."
$DOCKER_COMPOSE -f api/docker-compose.prod.yml -p checkpoint-prod down 2>/dev/null || true
$DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full down 2>/dev/null || true

# Очистка неиспользуемых ресурсов
log "Очистка неиспользуемых ресурсов..."
docker system prune -f

# Запуск системы
log "Запуск полной системы..."
$DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full up -d --build

# Ожидание запуска
log "Ожидание запуска сервисов (60 секунд)..."
sleep 60

# Проверка статуса
log "Проверка статуса контейнеров..."
$DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full ps

# Проверка портов
log "Проверка портов..."
if netstat -tlnp 2>/dev/null | grep -q ":80 "; then
    success "Порт 80 открыт"
else
    warning "Порт 80 не открыт"
fi

if netstat -tlnp 2>/dev/null | grep -q ":6379 "; then
    success "Порт 6379 (KeyDB) открыт"
else
    warning "Порт 6379 не открыт"
fi

# Тест сервисов
log "Тестирование сервисов..."

# Тест KeyDB
if $DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full exec -T keydb keydb-cli ping | grep -q "PONG"; then
    success "KeyDB работает"
else
    error "KeyDB не работает"
fi

# Тест API инстансов
for i in {1..3}; do
    if $DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full exec -T api$i wget --quiet --tries=1 --spider http://localhost:8080/health 2>/dev/null; then
        success "API$i работает"
    else
        error "API$i не работает"
    fi
done

# Тест Nginx
if curl -s --connect-timeout 5 http://localhost/health > /dev/null 2>&1; then
    success "Nginx и API работают"
else
    error "Nginx или API не работают"
    
    # Показать логи для диагностики
    log "Логи Nginx:"
    $DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full logs nginx | tail -10
    
    log "Логи API1:"
    $DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full logs api1 | tail -10
fi

# Финальный тест
log "Финальный тест API..."
response=$(curl -s -w "%{http_code}" -o /dev/null http://localhost/health 2>/dev/null || echo "000")
if [ "$response" = "200" ]; then
    success "API полностью работает (HTTP $response)"
elif [ "$response" = "000" ]; then
    error "API недоступен"
else
    warning "API ответил с кодом $response"
fi

echo ""
log "📋 Полезные команды:"
echo "• Статус: $DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full ps"
echo "• Логи: $DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full logs -f"
echo "• Остановка: $DOCKER_COMPOSE -f docker-compose.full.yml -p checkpoint-full down"
echo "• Тест API: curl http://localhost/health"
echo "• Тест с авторизацией: curl -H 'Authorization: Basic YWRtaW46Y2hlY2twb2ludDIwMjU=' http://localhost/api/v1/checkpoints"
