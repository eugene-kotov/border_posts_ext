#!/bin/bash

# Скрипт для запуска полной системы с парсером
# Usage: ./start_full_system.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.full.yml"
PROJECT_NAME="checkpoint-full"

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

log "🚀 Запуск полной системы Checkpoint (API + Parser + KeyDB + Nginx)..."

# Check dependencies
check_docker_compose

# Stop existing containers
log "1️⃣ Остановка существующих контейнеров..."
$DOCKER_COMPOSE -f docker-compose.prod.yml -p checkpoint-prod down 2>/dev/null || true
$DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME down 2>/dev/null || true

# Remove obsolete version warning by creating a clean compose file
log "2️⃣ Создание чистого docker-compose файла..."
if [ -f "$COMPOSE_FILE" ]; then
    # Remove version line to avoid warning
    sed '/^version:/d' $COMPOSE_FILE > ${COMPOSE_FILE}.tmp
    mv ${COMPOSE_FILE}.tmp $COMPOSE_FILE
fi

# Start full system
log "3️⃣ Запуск полной системы..."
$DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME up -d --build

# Wait for services
log "4️⃣ Ожидание запуска сервисов..."
sleep 30

# Check status
log "5️⃣ Проверка статуса сервисов..."
$DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps

# Test services
log "6️⃣ Тестирование сервисов..."

# Test KeyDB
if $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME exec -T keydb keydb-cli ping | grep -q "PONG"; then
    success "✅ KeyDB работает"
else
    error "❌ KeyDB не отвечает"
fi

# Test API instances
log "6️⃣ Тестирование API инстансов..."
api_instances=("api1" "api2" "api3")
for api in "${api_instances[@]}"; do
    if $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME exec -T $api wget --quiet --tries=1 --spider http://localhost:8080/health; then
        success "✅ $api работает"
    else
        warning "⚠️ $api не отвечает"
    fi
done

# Test load balancer
if command -v curl &> /dev/null; then
    log "7️⃣ Тестирование балансировщика нагрузки..."
    for i in {1..5}; do
        response=$(curl -s http://localhost/health 2>/dev/null || echo "ERROR")
        if [[ "$response" == *"healthy"* ]] || [[ "$response" == *"UP"* ]]; then
            success "✅ Запрос $i через балансировщик успешен"
        else
            warning "⚠️ Запрос $i через балансировщик не удался"
        fi
        sleep 1
    done
else
    warning "⚠️ curl недоступен для тестирования балансировщика"
fi

# Test Parser
log "8️⃣ Проверка парсера..."
parser_logs=$($DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME logs parser | tail -10)
if echo "$parser_logs" | grep -q "✅\|🔄\|📊\|started\|running"; then
    success "✅ Парсер работает"
    echo "Последние логи парсера:"
    echo "$parser_logs"
else
    warning "⚠️ Парсер может не работать правильно"
    echo "Логи парсера:"
    echo "$parser_logs"
fi

# Check KeyDB data
log "9️⃣ Проверка данных в KeyDB..."
checkpoint_count=$($DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME exec -T keydb keydb-cli scard checkpoints:all 2>/dev/null || echo "0")
echo "Количество чекпоинтов в KeyDB: $checkpoint_count"

if [ "$checkpoint_count" -gt 0 ]; then
    success "✅ Парсер заполнил KeyDB данными"
else
    warning "⚠️ В KeyDB нет данных чекпоинтов"
fi

echo ""
success "🎉 Полная система Checkpoint запущена!"
echo ""
echo -e "${BLUE}📊 Статус сервисов:${NC}"
$DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps
echo ""
echo -e "${YELLOW}📝 Полезные команды:${NC}"
echo "• Просмотр логов: $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME logs -f"
echo "• Логи парсера: $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME logs -f parser"
echo "• Логи API: $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME logs -f api"
echo "• Логи KeyDB: $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME logs -f keydb"
echo "• Остановка: $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME down"
echo "• Подключение к KeyDB: keydb-cli -h localhost -p 6379"
echo "• Проверка API: curl http://localhost/health"
echo ""
echo -e "${GREEN}🌐 Доступные сервисы:${NC}"
echo "• API: http://localhost/health"
echo "• Nginx: http://localhost/"
echo "• KeyDB: localhost:6379"
