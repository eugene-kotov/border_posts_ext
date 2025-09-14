#!/bin/bash

# Скрипт для быстрого перезапуска Checkpoint System
# Использование: ./restart_production.sh

set -e

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

log "🔄 Быстрый перезапуск Checkpoint System"

# Проверка файла
if [ ! -f "$COMPOSE_FILE" ]; then
    error "Файл $COMPOSE_FILE не найден!"
    exit 1
fi

# Показать текущий статус
log "📊 Текущий статус:"
docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME ps

# Остановка сервисов
log "⏹️  Остановка сервисов..."
docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME down

# Очистка неиспользуемых образов (опционально)
read -p "Очистить неиспользуемые образы? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "🧹 Очистка неиспользуемых образов..."
    docker image prune -f
fi

# Запуск сервисов
log "▶️  Запуск сервисов..."
docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME up -d

# Ожидание готовности
log "⏳ Ожидание готовности сервисов..."
sleep 20

# Проверка статуса
log "🔍 Проверка статуса:"
docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME ps

# Проверка здоровья
log "🏥 Проверка здоровья..."
if curl -s -f "http://localhost/health" > /dev/null 2>&1; then
    success "✅ Система готова к работе!"
else
    warning "⚠️  Система может быть еще не готова, проверьте логи:"
    docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME logs --tail=10
fi

success "🎉 Перезапуск завершен!"
