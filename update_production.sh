#!/bin/bash

# Скрипт для обновления Checkpoint System на продакшн сервере
# Использование: ./update_production.sh [branch_name]

set -e  # Остановка при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для логирования
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

# Проверка аргументов
BRANCH=${1:-main}
PROJECT_NAME="checkpoint-full"
COMPOSE_FILE="docker-compose.full.yml"

log "🚀 Начинаем обновление Checkpoint System"
log "📋 Ветка: $BRANCH"
log "📦 Проект: $PROJECT_NAME"

# Проверка, что мы в правильной директории
if [ ! -f "$COMPOSE_FILE" ]; then
    error "Файл $COMPOSE_FILE не найден! Запустите скрипт из директории release/"
    exit 1
fi

# Проверка статуса git
if [ ! -d ".git" ]; then
    error "Это не git репозиторий! Инициализируйте git или перейдите в правильную директорию"
    exit 1
fi

# Сохранение текущего состояния
log "💾 Сохранение текущего состояния..."
CURRENT_COMMIT=$(git rev-parse HEAD)
CURRENT_BRANCH=$(git branch --show-current)

# Проверка изменений в рабочей директории
if ! git diff --quiet; then
    warning "Обнаружены несохраненные изменения в рабочей директории"
    read -p "Продолжить? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "❌ Обновление отменено"
        exit 1
    fi
fi

# Получение обновлений
log "📥 Получение обновлений из git..."
git fetch origin

# Проверка существования ветки
if ! git show-ref --verify --quiet refs/remotes/origin/$BRANCH; then
    error "Ветка origin/$BRANCH не найдена!"
    exit 1
fi

# Переключение на ветку
log "🔄 Переключение на ветку $BRANCH..."
git checkout $BRANCH
git pull origin $BRANCH

NEW_COMMIT=$(git rev-parse HEAD)

if [ "$CURRENT_COMMIT" = "$NEW_COMMIT" ]; then
    success "✅ Уже на последней версии ($NEW_COMMIT)"
    exit 0
fi

log "📊 Изменения:"
git log --oneline $CURRENT_COMMIT..$NEW_COMMIT

# Создание бэкапа
BACKUP_DIR="../backups/$(date +%Y%m%d_%H%M%S)"
log "💾 Создание бэкапа в $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"

# Сохранение текущих данных KeyDB
log "🗄️  Создание бэкапа данных KeyDB..."
docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME exec -T keydb keydb-cli --rdb /tmp/dump.rdb BGSAVE
docker cp checkpoint-keydb-full:/tmp/dump.rdb "$BACKUP_DIR/keydb_dump.rdb" 2>/dev/null || warning "Не удалось создать бэкап KeyDB"

# Остановка сервисов
log "⏹️  Остановка сервисов..."
docker-compose -f $COMPOSE_FILE -p $PROJECT_NAME down

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

# Финальная проверка
log "🔍 Финальная проверка системы..."
./monitor_resources.sh

success "🎉 Обновление завершено успешно!"
log "📊 Статистика:"
log "   Старый коммит: $CURRENT_COMMIT"
log "   Новый коммит:  $NEW_COMMIT"
log "   Бэкап:         $BACKUP_DIR"

# Сохранение информации об обновлении
echo "Обновление $(date): $CURRENT_COMMIT -> $NEW_COMMIT" >> update_history.log

log "✅ Система готова к работе!"
