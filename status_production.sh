#!/bin/bash

# Скрипт для проверки статуса Checkpoint System
# Использование: ./status_production.sh

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

PROJECT_NAME="checkpoint-full"
COMPOSE_FILE="docker-compose.full.yml"

log "🔍 Проверка статуса Checkpoint System"
echo "================================================"

# Проверка git статуса
log "📋 Git статус:"
echo "Текущая ветка: $(git branch --show-current)"
echo "Последний коммит: $(git log -1 --oneline)"
echo "Статус репозитория:"
git status --porcelain

echo ""

# Проверка Docker
log "🐳 Docker статус:"
if command -v docker &> /dev/null; then
    echo "Docker версия: $(docker --version)"
    echo "Docker Compose версия: $(docker-compose --version)"
else
    error "Docker не установлен!"
    exit 1
fi

echo ""

# Проверка контейнеров
log "📦 Статус контейнеров:"
if [ -f "$COMPOSE_FILE" ]; then
    docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME ps
else
    error "Файл $COMPOSE_FILE не найден!"
    exit 1
fi

echo ""

# Проверка ресурсов
log "💾 Использование ресурсов:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" checkpoint-keydb-full checkpoint-api-full checkpoint-parser-full checkpoint-nginx-full 2>/dev/null || warning "Некоторые контейнеры не запущены"

echo ""

# Проверка здоровья API
log "🏥 Проверка здоровья API:"
HEALTH_URL="http://localhost/health"
if curl -s -f "$HEALTH_URL" > /dev/null 2>&1; then
    success "✅ API доступен"
    echo "Ответ health check:"
    curl -s "$HEALTH_URL" | jq . 2>/dev/null || curl -s "$HEALTH_URL"
else
    error "❌ API недоступен"
fi

echo ""

# Проверка KeyDB
log "🗄️  Проверка KeyDB:"
if docker exec checkpoint-keydb-full keydb-cli ping > /dev/null 2>&1; then
    success "✅ KeyDB доступен"
    echo "Информация о KeyDB:"
    docker exec checkpoint-keydb-full keydb-cli info memory | grep used_memory_human
    docker exec checkpoint-keydb-full keydb-cli info keyspace
else
    error "❌ KeyDB недоступен"
fi

echo ""

# Проверка логов на ошибки
log "📋 Проверка логов на ошибки (последние 10 строк):"
docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME logs --tail=10 2>/dev/null | grep -i error || echo "Ошибок не найдено"

echo ""

# Проверка дискового пространства
log "💽 Дисковое пространство:"
df -h / | tail -1 | awk '{print "Root partition: " $3 " used of " $2 " (" $5 ")"}'

echo ""

# Проверка сетевых портов
log "🌐 Проверка портов:"
netstat -tlnp | grep -E ':(80|443|6379|8080)' || echo "Порты не найдены"

echo ""

# Проверка истории обновлений
log "📚 История обновлений:"
if [ -f "update_history.log" ]; then
    echo "Последние 5 обновлений:"
    tail -5 update_history.log
else
    echo "Файл истории обновлений не найден"
fi

echo ""

# Проверка истории откатов
log "🔄 История откатов:"
if [ -f "rollback_history.log" ]; then
    echo "Последние 5 откатов:"
    tail -5 rollback_history.log
else
    echo "Файл истории откатов не найден"
fi

echo ""
log "✅ Проверка статуса завершена"
