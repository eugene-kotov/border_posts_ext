#!/bin/bash

# Быстрый запуск системы с проверкой
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

log "Быстрый запуск Checkpoint системы..."

# Остановить все существующие контейнеры
log "Остановка существующих контейнеров..."
docker-compose -f api/docker-compose.prod.yml -p checkpoint-prod down 2>/dev/null || true
docker-compose -f docker-compose.full.yml -p checkpoint-full down 2>/dev/null || true

# Запустить полную систему
log "Запуск полной системы..."
docker-compose -f docker-compose.full.yml -p checkpoint-full up -d --build

# Ждать запуска
log "Ожидание запуска сервисов..."
sleep 30

# Проверить статус
log "Проверка статуса контейнеров..."
docker-compose -f docker-compose.full.yml -p checkpoint-full ps

# Проверить порты
log "Проверка портов..."
if netstat -an 2>/dev/null | grep -q ":80 "; then
    success "Порт 80 открыт"
else
    warning "Порт 80 не открыт"
fi

if netstat -an 2>/dev/null | grep -q ":6379 "; then
    success "Порт 6379 (KeyDB) открыт"
else
    warning "Порт 6379 не открыт"
fi

# Тест API
log "Тестирование API..."
if curl -s http://localhost/health > /dev/null 2>&1; then
    success "API отвечает на /health"
else
    error "API не отвечает на /health"
fi

# Тест с авторизацией
log "Тестирование API с авторизацией..."
response=$(curl -s -w "%{http_code}" -o /dev/null \
    --location 'http://localhost/api/v1/checkpoints' \
    --header 'Authorization: Basic dHJ1Y2tkcml2ZXI6Y2hlY2twb2ludEAyMDI1' 2>/dev/null || echo "000")

if [ "$response" = "200" ]; then
    success "API с авторизацией работает (HTTP $response)"
elif [ "$response" = "401" ]; then
    warning "API работает, но авторизация неверная (HTTP $response)"
elif [ "$response" = "000" ]; then
    error "API недоступен (нет соединения)"
else
    warning "API ответил с кодом $response"
fi

echo ""
log "Полезные команды:"
echo "• Статус: docker-compose -f docker-compose.full.yml -p checkpoint-full ps"
echo "• Логи: docker-compose -f docker-compose.full.yml -p checkpoint-full logs -f"
echo "• Остановка: docker-compose -f docker-compose.full.yml -p checkpoint-full down"
echo "• Тест API: curl http://localhost/health"
echo "• Тест с авторизацией: curl -H 'Authorization: Basic dHJ1Y2tkcml2ZXI6Y2hlY2twb2ludEAyMDI1' http://localhost/api/v1/checkpoints"


