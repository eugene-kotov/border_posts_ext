# 🚀 Быстрый старт - Checkpoint System

## Установка на продакшн сервер

### 1. Клонирование и настройка

```bash
# Клонирование репозитория
git clone <your-repo-url> checkpoint-system
cd checkpoint-system/release

# Установка прав на выполнение
chmod +x *.sh

# Проверка готовности
./manage_production.sh status
```

### 2. Первый запуск

```bash
# Запуск системы
./manage_production.sh restart

# Проверка статуса
./manage_production.sh status
```

### 3. Проверка работы

```bash
# Проверка API
curl http://localhost/health

# Мониторинг ресурсов
./manage_production.sh monitor
```

## Основные команды

### 🔄 Обновление системы
```bash
# Обновление с main ветки
./manage_production.sh update main

# Обновление с feature ветки
./manage_production.sh update feature/new-feature
```

### ⏹️ Перезапуск
```bash
# Быстрый перезапуск
./manage_production.sh restart
```

### 🔙 Откат
```bash
# Показать доступные коммиты
./manage_production.sh rollback

# Откат к конкретному коммиту
./manage_production.sh rollback abc123def
```

### 📊 Мониторинг
```bash
# Полный статус системы
./manage_production.sh status

# Мониторинг ресурсов
./manage_production.sh monitor

# Просмотр логов
./manage_production.sh logs
```

## Конфигурация ресурсов

Система оптимизирована для сервера:
- **CPU**: 2 ядра
- **RAM**: 768 MB
- **OS**: Ubuntu 24.04

### Распределение ресурсов:
- **KeyDB**: 0.5 CPU, 150MB RAM
- **API**: 0.8 CPU, 200MB RAM  
- **Parser**: 0.4 CPU, 150MB RAM
- **Nginx**: 0.3 CPU, 100MB RAM

## Безопасность

### Автоматические бэкапы
- Создаются при каждом обновлении
- Сохраняются в `../backups/`
- Включают данные KeyDB и конфигурацию

### Восстановление
```bash
# Создание ручного бэкапа
./manage_production.sh backup

# Восстановление из бэкапа (ручное)
# См. PRODUCTION_MANAGEMENT.md
```

## Устранение неполадок

### Система не запускается
```bash
# Проверка статуса
./manage_production.sh status

# Просмотр логов
./manage_production.sh logs

# Перезапуск
./manage_production.sh restart
```

### Высокое использование ресурсов
```bash
# Мониторинг ресурсов
./manage_production.sh monitor

# Очистка Docker
./manage_production.sh clean
```

### API недоступен
```bash
# Проверка контейнеров
docker-compose -f docker-compose.full.yml -p checkpoint-full ps

# Перезапуск API
docker-compose -f docker-compose.full.yml -p checkpoint-full restart api
```

## Полезные ссылки

- **Полная документация**: `PRODUCTION_MANAGEMENT.md`
- **Конфигурация ресурсов**: `RESOURCE_CONFIGURATION.md`
- **Управление**: `manage_production.sh --help`

## Поддержка

При проблемах:
1. Проверьте `./manage_production.sh status`
2. Посмотрите логи: `./manage_production.sh logs`
3. Создайте issue с подробным описанием
