# Управление Checkpoint System на продакшн сервере

## Обзор

Этот набор скриптов предназначен для безопасного управления Checkpoint System на продакшн сервере через git обновления.

## Структура скриптов

### 🚀 Основные скрипты

- **`manage_production.sh`** - Главный скрипт управления
- **`update_production.sh`** - Обновление системы из git
- **`restart_production.sh`** - Быстрый перезапуск
- **`rollback_production.sh`** - Откат к предыдущей версии
- **`status_production.sh`** - Проверка статуса системы
- **`monitor_resources.sh`** - Мониторинг ресурсов

## Быстрый старт

### 1. Первоначальная настройка

```bash
# Клонирование репозитория
git clone <your-repo-url> checkpoint-system
cd checkpoint-system/release

# Установка прав на выполнение
chmod +x *.sh

# Запуск системы
./manage_production.sh restart
```

### 2. Обновление системы

```bash
# Обновление с ветки main
./manage_production.sh update main

# Обновление с конкретной ветки
./manage_production.sh update feature/new-feature
```

### 3. Проверка статуса

```bash
# Полная проверка системы
./manage_production.sh status

# Мониторинг ресурсов
./manage_production.sh monitor
```

## Детальное описание команд

### 🔄 Обновление системы (`update_production.sh`)

**Назначение**: Безопасное обновление системы из git репозитория

**Использование**:
```bash
./update_production.sh [branch_name]
```

**Что делает**:
1. Проверяет git статус
2. Создает бэкап данных KeyDB
3. Останавливает сервисы
4. Получает обновления из git
5. Пересобирает образы
6. Запускает сервисы
7. Проверяет готовность системы

**Пример**:
```bash
./update_production.sh main
```

### ⏹️ Перезапуск (`restart_production.sh`)

**Назначение**: Быстрый перезапуск без обновления кода

**Использование**:
```bash
./restart_production.sh
```

**Что делает**:
1. Останавливает сервисы
2. Опционально очищает неиспользуемые образы
3. Запускает сервисы
4. Проверяет готовность

### 🔙 Откат (`rollback_production.sh`)

**Назначение**: Откат к предыдущей версии

**Использование**:
```bash
./rollback_production.sh [commit_hash]
```

**Что делает**:
1. Показывает доступные коммиты
2. Создает бэкап текущего состояния
3. Откатывается к указанному коммиту
4. Пересобирает и запускает систему

**Пример**:
```bash
# Показать доступные коммиты
./rollback_production.sh

# Откат к конкретному коммиту
./rollback_production.sh abc123def
```

### 📊 Проверка статуса (`status_production.sh`)

**Назначение**: Комплексная проверка состояния системы

**Использование**:
```bash
./status_production.sh
```

**Проверяет**:
- Git статус
- Docker статус
- Контейнеры
- Ресурсы
- API здоровье
- KeyDB доступность
- Логи на ошибки
- Дисковое пространство
- Сетевые порты
- Историю обновлений

### 📈 Мониторинг (`monitor_resources.sh`)

**Назначение**: Мониторинг использования ресурсов

**Использование**:
```bash
./monitor_resources.sh
```

**Показывает**:
- Использование CPU и памяти контейнерами
- Общее использование памяти системы
- Использование CPU
- Дисковое пространство
- Статус контейнеров
- Логи системы

## Управление через главный скрипт

### `manage_production.sh` - Универсальный интерфейс

```bash
# Показать справку
./manage_production.sh help

# Обновить систему
./manage_production.sh update main

# Перезапустить
./manage_production.sh restart

# Откатить
./manage_production.sh rollback abc123

# Проверить статус
./manage_production.sh status

# Показать логи
./manage_production.sh logs

# Мониторинг ресурсов
./manage_production.sh monitor

# Создать бэкап
./manage_production.sh backup

# Очистить Docker
./manage_production.sh clean
```

## Безопасность и бэкапы

### Автоматические бэкапы

Все скрипты создают автоматические бэкапы:
- **При обновлении**: `../backups/YYYYMMDD_HHMMSS/`
- **При откате**: `../backups/rollback_YYYYMMDD_HHMMSS/`
- **Ручной бэкап**: `../backups/manual_YYYYMMDD_HHMMSS/`

### Восстановление из бэкапа

```bash
# Восстановление данных KeyDB
docker cp ../backups/20241201_120000/keydb_dump.rdb checkpoint-keydb-full:/tmp/
docker exec checkpoint-keydb-full keydb-cli --rdb /tmp/keydb_dump.rdb RESTORE
```

## Мониторинг и логирование

### Логи системы

```bash
# Все логи
./manage_production.sh logs

# Логи конкретного сервиса
docker-compose -f docker-compose.full.yml -p checkpoint-full logs keydb
docker-compose -f docker-compose.full.yml -p checkpoint-full logs api
docker-compose -f docker-compose.full.yml -p checkpoint-full logs parser
docker-compose -f docker-compose.full.yml -p checkpoint-full logs nginx
```

### История операций

- **Обновления**: `update_history.log`
- **Откаты**: `rollback_history.log`

## Устранение неполадок

### Система не запускается

1. Проверьте статус:
   ```bash
   ./manage_production.sh status
   ```

2. Проверьте логи:
   ```bash
   ./manage_production.sh logs
   ```

3. Проверьте ресурсы:
   ```bash
   ./manage_production.sh monitor
   ```

### API недоступен

1. Проверьте контейнеры:
   ```bash
   docker-compose -f docker-compose.full.yml -p checkpoint-full ps
   ```

2. Перезапустите API:
   ```bash
   docker-compose -f docker-compose.full.yml -p checkpoint-full restart api
   ```

### KeyDB недоступен

1. Проверьте KeyDB:
   ```bash
   docker exec checkpoint-keydb-full keydb-cli ping
   ```

2. Перезапустите KeyDB:
   ```bash
   docker-compose -f docker-compose.full.yml -p checkpoint-full restart keydb
   ```

## Рекомендации

### Регулярное обслуживание

1. **Еженедельно**: Проверяйте статус системы
2. **При обновлениях**: Всегда создавайте бэкапы
3. **Мониторинг**: Следите за использованием ресурсов
4. **Логи**: Регулярно проверяйте логи на ошибки

### Безопасность

1. **Права доступа**: Ограничьте доступ к скриптам
2. **Бэкапы**: Регулярно создавайте резервные копии
3. **Мониторинг**: Настройте алерты на критические ошибки

### Производительность

1. **Ресурсы**: Следите за использованием CPU и памяти
2. **Диск**: Регулярно очищайте неиспользуемые Docker ресурсы
3. **Логи**: Ограничивайте размер логов

## Контакты и поддержка

При возникновении проблем:
1. Проверьте логи системы
2. Используйте скрипт диагностики
3. Создайте issue в репозитории с подробным описанием
