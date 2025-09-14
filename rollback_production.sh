#!/bin/bash

# Скрипт для отката Checkpoint System к предыдущей версии
# Использование: ./rollback_production.sh [commit_hash]

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

# Проверка аргументов
if [ $# -eq 0 ]; then
    log "📋 Доступные коммиты для отката:"
    git log --oneline -10
    echo
    read -p "Введите хеш коммита для отката: " ROLLBACK_COMMIT
else
    ROLLBACK_COMMIT=$1
fi

log "🔄 Откат Checkpoint System к коммиту: $ROLLBACK_COMMIT"

# Проверка существования коммита
if ! git cat-file -e "$ROLLBACK_COMMIT^{commit}" 2>/dev/null; then
    error "Коммит $ROLLBACK_COMMIT не найден!"
    exit 1
fi

# Показать информацию о коммите
log "📊 Информация о коммите:"
git show --stat $ROLLBACK_COMMIT

# Подтверждение
read -p "Продолжить откат? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "❌ Откат отменен"
    exit 0
fi

# Сохранение текущего состояния
CURRENT_COMMIT=$(git rev-parse HEAD)
log "💾 Текущий коммит: $CURRENT_COMMIT"

# Создание бэкапа текущего состояния
BACKUP_DIR="../backups/rollback_$(date +%Y%m%d_%H%M%S)"
log "💾 Создание бэкапа текущего состояния в $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"

# Сохранение данных KeyDB
log "🗄️  Создание бэкапа данных KeyDB..."
docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME exec -T keydb keydb-cli --rdb /tmp/dump.rdb BGSAVE
docker cp checkpoint-keydb-full:/tmp/dump.rdb "$BACKUP_DIR/keydb_dump.rdb" 2>/dev/null || warning "Не удалось создать бэкап KeyDB"

# Остановка сервисов
log "⏹️  Остановка сервисов..."
docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME down

# Откат к указанному коммиту
log "🔄 Откат к коммиту $ROLLBACK_COMMIT..."
git checkout $ROLLBACK_COMMIT

# Пересборка образов
log "🔨 Пересборка образов..."
docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME build --no-cache

# Запуск сервисов
log "▶️  Запуск сервисов..."
docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME up -d

# Ожидание готовности
log "⏳ Ожидание готовности сервисов..."
sleep 30

# Проверка статуса
log "🔍 Проверка статуса сервисов..."
docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME ps

# Проверка здоровья
log "🏥 Проверка здоровья сервисов..."
HEALTH_CHECK_URL="http://localhost/health"
MAX_RETRIES=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s -f "$HEALTH_CHECK_URL" > /dev/null 2>&1; then
        success "✅ Сервисы готовы к работе!"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        warning "Попытка $RETRY_COUNT/$MAX_RETRIES: сервисы еще не готовы, ждем..."
        sleep 10
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    error "❌ Сервисы не готовы после $MAX_RETRIES попыток!"
    log "📋 Логи для диагностики:"
    docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME logs --tail=20
    exit 1
fi

# Сохранение информации об откате
echo "Откат $(date): $CURRENT_COMMIT -> $ROLLBACK_COMMIT" >> rollback_history.log

success "🎉 Откат завершен успешно!"
log "📊 Статистика:"
log "   Предыдущий коммит: $CURRENT_COMMIT"
log "   Текущий коммит:    $ROLLBACK_COMMIT"
log "   Бэкап:             $BACKUP_DIR"

log "✅ Система откачена и готова к работе!"
