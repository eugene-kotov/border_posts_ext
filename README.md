# Checkpoint System - Полная система мониторинга пунктов пропуска

Высокопроизводительная система для автоматического сбора, хранения и предоставления данных о загруженности пунктов пропуска через REST API.

## 🏗️ Архитектура системы

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Python Parser │    │     Nginx       │    │   Go API 1.23   │    │     KeyDB       │
│   (Container)   │───▶│   (Port 80/443) │───▶│   (Port 8080)   │───▶│   (Port 6379)   │
│   Data Collector│    │   Proxy Server  │    │   Application   │    │   Database      │
│   Every 7 min   │    │   Static Files  │    │   Auth & Logic  │    │   Persistence   │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Компоненты системы:
- **Python Parser** - Автоматический сбор данных каждые 7 минут
- **Nginx** - Прокси-сервер и статические файлы
- **Go API 1.23** - Высокопроизводительный REST API
- **KeyDB** - In-memory база данных для быстрого доступа

## 📁 Структура проекта

```
release/
├── api/                           # Go API сервис (Go 1.23)
│   ├── main.go                   # Основной код API
│   ├── go.mod                    # Go зависимости
│   ├── go.sum                    # Go зависимости (checksums)
│   ├── Dockerfile.prod           # Docker образ для API
│   ├── docker-compose.prod.yml   # Конфигурация API + KeyDB + Nginx
│   ├── keydb.conf                # Конфигурация KeyDB (оптимизированная)
│   ├── nginx.prod.conf           # Конфигурация Nginx
│   └── env.prod.example          # Пример переменных окружения
├── parser/                       # Python парсер
│   ├── new_checkpoint_data.py    # Основной код парсера
│   ├── links.txt                 # Список URL для парсинга
│   ├── test_keydb.py             # Тест подключения к KeyDB
│   ├── requirements.txt          # Python зависимости
│   ├── Dockerfile                # Docker образ для парсера
│   └── docker-compose.yml        # Конфигурация парсера + KeyDB
├── docker-compose.full.yml       # Полная конфигурация всех сервисов
├── nginx.loadbalancer.conf       # Конфигурация Nginx (оптимизированная)
├── manage_production.sh          # 🚀 Главный скрипт управления
├── update_production.sh          # 🔄 Обновление через git
├── restart_production.sh         # ⏹️ Быстрый перезапуск
├── rollback_production.sh        # 🔙 Откат к предыдущей версии
├── status_production.sh          # 📊 Проверка статуса системы
├── monitor_resources.sh          # 📈 Мониторинг ресурсов
├── test_build.sh                 # 🧪 Тестирование сборки
├── PRODUCTION_MANAGEMENT.md      # 📚 Полная документация управления
├── QUICK_START.md                # ⚡ Быстрый старт
├── RESOURCE_CONFIGURATION.md     # ⚙️ Конфигурация ресурсов
└── README.md                     # Этот файл
```

## 🚀 Быстрый старт

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

## 🔧 Управление системой

### Основные команды

```bash
# Главное меню управления
./manage_production.sh help

# Обновление системы из git
./manage_production.sh update main

# Быстрый перезапуск
./manage_production.sh restart

# Откат к предыдущей версии
./manage_production.sh rollback

# Проверка статуса
./manage_production.sh status

# Мониторинг ресурсов
./manage_production.sh monitor

# Просмотр логов
./manage_production.sh logs

# Создание бэкапа
./manage_production.sh backup

# Очистка Docker
./manage_production.sh clean
```

## ⚙️ Конфигурация ресурсов

Система оптимизирована для сервера с ограниченными ресурсами:

### Требования к серверу
- **CPU**: 2 ядра
- **RAM**: 768 MB
- **OS**: Ubuntu 24.04
- **Go Version**: 1.23

### Распределение ресурсов
- **KeyDB**: 0.5 CPU, 150MB RAM (128MB max memory)
- **API**: 0.8 CPU, 200MB RAM
- **Parser**: 0.4 CPU, 150MB RAM
- **Nginx**: 0.3 CPU, 100MB RAM

**Итого**: 2.0 CPU, 600MB RAM (78% от доступных ресурсов)

## 📊 API Endpoints

### Публичные endpoints

- `GET /health` - Проверка здоровья (без авторизации)

### Защищенные endpoints (требуют Basic Auth)

- `GET /api/v1/checkpoints` - Список всех пунктов пропуска
- `GET /api/v1/checkpoints/:id` - Данные конкретного пункта пропуска
- `GET /api/v1/checkpoints/ids` - Список ID пунктов пропуска
- `GET /api/v1/stats` - Статистика

### Примеры использования

```bash
# Health check
curl http://localhost/health

# Получение данных (с авторизацией)
curl -u admin:your_password http://localhost/api/v1/checkpoints

# Получение конкретного пункта пропуска
curl -u admin:your_password http://localhost/api/v1/checkpoints/checkpoint_id

# Получение статистики
curl -u admin:your_password http://localhost/api/v1/stats
```

## 🔄 Парсер данных

### Автоматический режим
Парсер автоматически:
- Запускается при старте системы
- Обновляет данные каждые 7 минут
- Сохраняет данные в KeyDB
- Логирует свою работу

### Ручное управление парсером

```bash
# Проверка статуса парсера
./scripts/monitor.sh parser

# Просмотр логов парсера
./scripts/deploy.sh logs parser

# Перезапуск только парсера
docker-compose -f docker-compose.full.yml restart parser
```

## 🛡️ Безопасность

### Реализованные меры
- ✅ **Basic Authentication** для API endpoints
- ✅ **Health Check** без авторизации
- ✅ **Non-root пользователи** в Docker контейнерах
- ✅ **Сетевая изоляция** через Docker networks
- ✅ **Логирование** всех запросов
- ✅ **Автоматические бэкапы** при обновлениях
- ✅ **Откат к предыдущим версиям**

### Рекомендации для продакшена
1. **Измените пароли** в переменных окружения
2. **Настроите HTTPS** с SSL сертификатами
3. **Ограничьте доступ** к портам 6379 и 8080
4. **Настройте файрвол**
5. **Регулярно обновляйте** Docker образы
6. **Мониторьте ресурсы** системы

## 📈 Производительность

### Оптимизированная производительность
- **Response Time**: < 100ms для health check
- **Memory Usage**: 600MB общее (78% от 768MB)
- **CPU Usage**: 2.0 ядра максимум (100% от доступных)
- **Data Update**: каждые 7 минут
- **Go 1.23**: Улучшенная производительность на 5-10%
- **Статическая линковка**: Быстрый запуск и минимальный размер

## 🔍 Мониторинг и логирование

### Доступные метрики
- ✅ **Health Status** - статус всех сервисов
- ✅ **Resource Usage** - CPU, память, сеть
- ✅ **KeyDB Metrics** - память, клиенты, операции
- ✅ **API Response Times** - время ответа endpoints
- ✅ **Parser Status** - статус парсера и количество данных
- ✅ **Error Rates** - количество ошибок
- ✅ **Git History** - история обновлений и откатов

### Мониторинг
```bash
# Полная проверка системы
./manage_production.sh status

# Мониторинг ресурсов
./manage_production.sh monitor

# Просмотр логов
./manage_production.sh logs

# Тестирование сборки
./test_build.sh
```

## 🚨 Устранение неполадок

### Частые проблемы

1. **Система не запускается**
   ```bash
   # Проверьте статус
   ./manage_production.sh status
   
   # Проверьте логи
   ./manage_production.sh logs
   
   # Перезапустите систему
   ./manage_production.sh restart
   ```

2. **API недоступен**
   ```bash
   # Проверьте статус
   ./manage_production.sh status
   
   # Проверьте KeyDB
   docker exec checkpoint-keydb-full keydb-cli ping
   
   # Перезапустите API
   docker-compose -f docker-compose.full.yml -p checkpoint-full restart api
   ```

3. **Высокое использование ресурсов**
   ```bash
   # Мониторинг ресурсов
   ./manage_production.sh monitor
   
   # Очистка Docker
   ./manage_production.sh clean
   ```

4. **Проблемы с обновлением**
   ```bash
   # Откат к предыдущей версии
   ./manage_production.sh rollback
   
   # Проверка git статуса
   git status
   ```

## 🔄 Обновление системы

### Безопасное обновление через git

```bash
# Обновление с main ветки
./manage_production.sh update main

# Обновление с feature ветки
./manage_production.sh update feature/new-feature

# Проверка статуса после обновления
./manage_production.sh status
```

### Откат к предыдущей версии

```bash
# Показать доступные коммиты
./manage_production.sh rollback

# Откат к конкретному коммиту
./manage_production.sh rollback abc123def
```

### Ручное обновление

```bash
# Остановка системы
docker-compose -f docker-compose.full.yml -p checkpoint-full down

# Обновление кода
git pull origin main

# Пересборка и запуск
docker-compose -f docker-compose.full.yml -p checkpoint-full up -d --build
```

## 📚 Дополнительная документация

- **`PRODUCTION_MANAGEMENT.md`** - Полная документация по управлению системой
- **`QUICK_START.md`** - Краткая инструкция по быстрому старту
- **`RESOURCE_CONFIGURATION.md`** - Подробная конфигурация ресурсов
- **`examples/`** - Примеры использования API

## 🎯 Заключение

Эта система предоставляет:
- ✅ **Автоматический сбор данных** о пунктах пропуска каждые 7 минут
- ✅ **Высокопроизводительный REST API** на Go 1.23
- ✅ **Оптимизацию для малых ресурсов** (2 CPU, 768MB RAM)
- ✅ **Безопасное управление** через git обновления
- ✅ **Автоматические бэкапы** и откат к предыдущим версиям
- ✅ **Комплексный мониторинг** ресурсов и состояния
- ✅ **Простое развертывание** через Docker
- ✅ **Безопасность** и аутентификацию

**Система готова к продакшену на серверах с ограниченными ресурсами!** 🚀

### Ключевые особенности:
- **Go 1.23** с улучшенной производительностью
- **KeyDB** для быстрого доступа к данным
- **Nginx** как прокси-сервер
- **Python парсер** для автоматического сбора данных
- **Полный набор скриптов** для управления через git




