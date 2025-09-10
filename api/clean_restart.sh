#!/bin/bash

# Скрипт для полной очистки и перезапуска всех контейнеров
# Usage: ./clean_restart.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.prod.yml"
PROJECT_NAME="checkpoint-prod"

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check Docker Compose command
check_docker_compose() {
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        error "Docker Compose is not installed or not in PATH"
        exit 1
    fi
}

log "🧹 Полная очистка и перезапуск Checkpoint API..."

# Check dependencies
check_docker_compose

# Step 1: Stop all checkpoint containers
log "1️⃣ Остановка всех контейнеров Checkpoint..."
$DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME down 2>/dev/null || true

# Step 2: Stop any containers using port 6379
log "2️⃣ Остановка контейнеров, использующих порт 6379..."
docker ps --format "{{.Names}}" | grep -E "(keydb|redis|checkpoint)" | xargs -r docker stop 2>/dev/null || true

# Step 3: Remove all checkpoint containers
log "3️⃣ Удаление всех контейнеров Checkpoint..."
docker ps -a --format "{{.Names}}" | grep -E "(checkpoint|keydb)" | xargs -r docker rm -f 2>/dev/null || true

# Step 4: Remove checkpoint volumes
log "4️⃣ Удаление томов Checkpoint..."
docker volume ls --format "{{.Name}}" | grep -E "(checkpoint|keydb)" | xargs -r docker volume rm 2>/dev/null || true

# Step 5: Remove checkpoint networks
log "5️⃣ Удаление сетей Checkpoint..."
docker network ls --format "{{.Name}}" | grep -E "(checkpoint|bridge)" | xargs -r docker network rm 2>/dev/null || true

# Step 6: Clean up dangling images
log "6️⃣ Очистка неиспользуемых образов..."
docker image prune -f

# Step 7: Clean up dangling volumes
log "7️⃣ Очистка неиспользуемых томов..."
docker volume prune -f

# Step 8: Clean up dangling networks
log "8️⃣ Очистка неиспользуемых сетей..."
docker network prune -f

# Step 9: Verify port 6379 is free
log "9️⃣ Проверка доступности порта 6379..."
if command -v netstat &> /dev/null; then
    local port_check=$(netstat -tln 2>/dev/null | grep ":6379" || true)
elif command -v ss &> /dev/null; then
    local port_check=$(ss -tln | grep ":6379" || true)
else
    local port_check=""
fi

if [ -n "$port_check" ]; then
    warning "Порт 6379 все еще занят:"
    echo "$port_check"
    warning "Попробуем использовать альтернативный порт 6380..."
    COMPOSE_FILE="docker-compose.prod-alt.yml"
fi

# Step 10: Create local data directory
log "🔟 Создание локальной директории для данных..."
mkdir -p ./keydb_data
chmod 755 ./keydb_data

# Step 11: Start fresh containers
log "1️⃣1️⃣ Запуск новых контейнеров..."
$DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME up -d --build

# Step 12: Wait for services
log "1️⃣2️⃣ Ожидание запуска сервисов..."
sleep 20

# Step 13: Check status
log "1️⃣3️⃣ Проверка статуса сервисов..."
$DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps

# Step 14: Test services
log "1️⃣4️⃣ Тестирование сервисов..."

# Test KeyDB
local keydb_port="6379"
if [ "$COMPOSE_FILE" = "docker-compose.prod-alt.yml" ]; then
    keydb_port="6380"
fi

if $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME exec -T keydb keydb-cli ping | grep -q "PONG"; then
    success "✅ KeyDB работает на порту $keydb_port"
else
    error "❌ KeyDB не отвечает"
fi

# Test API
if command -v curl &> /dev/null; then
    if curl -s http://localhost/health > /dev/null; then
        success "✅ API работает"
    else
        warning "⚠️ API не отвечает на /health"
    fi
else
    warning "⚠️ curl недоступен для тестирования API"
fi

# Step 15: Show logs
log "1️⃣5️⃣ Последние логи KeyDB..."
$DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME logs --tail=10 keydb

echo ""
success "🎉 Полная очистка и перезапуск завершены!"
echo ""
echo -e "${BLUE}📊 Статус сервисов:${NC}"
$DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps
echo ""
echo -e "${YELLOW}📝 Полезные команды:${NC}"
echo "• Просмотр логов: $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME logs -f"
echo "• Остановка: $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME down"
echo "• Подключение к KeyDB: keydb-cli -p $keydb_port"
echo "• Проверка API: curl http://localhost/health"
