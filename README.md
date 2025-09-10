# Checkpoint API + Parser - Полная система

Этот релиз содержит полную систему для сбора и предоставления данных о пунктах пропуска через API.

## 🏗️ Архитектура системы

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Python Parser │    │     Nginx       │    │   Go API        │    │     KeyDB       │
│   (Container)   │───▶│   (Port 80/443) │───▶│   (Port 8080)   │───▶│   (Port 6379)   │
│   Data Collector│    │   Load Balancer │    │   Application   │    │   Database      │
│   Every 7 min   │    │   Rate Limiting │    │   Auth & Logic  │    │   Persistence   │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 📁 Структура проекта

```
release/
├── api/                    # Go API сервис
│   ├── main.go            # Основной код API
│   ├── go.mod             # Go зависимости
│   ├── go.sum             # Go зависимости (checksums)
│   ├── Dockerfile.prod    # Docker образ для API
│   ├── docker-compose.prod.yml  # Конфигурация API + KeyDB + Nginx
│   ├── keydb.conf         # Конфигурация KeyDB
│   ├── nginx.prod.conf    # Конфигурация Nginx
│   └── env.prod.example   # Пример переменных окружения
├── parser/                # Python парсер
│   ├── new_checkpoint_data.py  # Основной код парсера
│   ├── links.txt          # Список URL для парсинга
│   ├── test_keydb.py      # Тест подключения к KeyDB
│   ├── requirements.txt   # Python зависимости
│   ├── Dockerfile         # Docker образ для парсера
│   └── docker-compose.yml # Конфигурация парсера + KeyDB
├── scripts/               # Скрипты управления
│   ├── deploy.sh          # Развертывание системы
│   └── monitor.sh         # Мониторинг системы
├── docs/                  # Документация
├── examples/              # Примеры использования
├── docker-compose.full.yml # Полная конфигурация всех сервисов
└── README.md              # Этот файл
```

## 🚀 Быстрый старт

### 1. Подготовка

```bash
# Клонируйте или скачайте релиз
cd release

# Скопируйте файл с переменными окружения
cp api/env.prod.example .env

# Отредактируйте переменные окружения
nano .env
```

### 2. Настройка переменных окружения

Отредактируйте `.env`:

```bash
# KeyDB Configuration
KEYDB_PASSWORD=your_very_strong_password_here

# API Authentication
AUTH_USERNAME=admin
AUTH_PASSWORD=your_very_strong_api_password_here

# Rate Limiting
RATE_LIMIT=3000
```

### 3. Запуск полной системы

```bash
# Сделайте скрипты исполняемыми (Linux/Mac)
chmod +x scripts/*.sh

# Запустите все сервисы
./scripts/deploy.sh start
```

### 4. Проверка работоспособности

```bash
# Проверьте статус
./scripts/deploy.sh status

# Проверьте здоровье системы
./scripts/monitor.sh health

# Проверьте парсер
./scripts/monitor.sh parser
```

## 🔧 Управление системой

### Основные команды

```bash
# Запуск всех сервисов
./scripts/deploy.sh start

# Остановка всех сервисов
./scripts/deploy.sh stop

# Перезапуск всех сервисов
./scripts/deploy.sh restart

# Статус всех сервисов
./scripts/deploy.sh status

# Логи всех сервисов
./scripts/deploy.sh logs

# Логи конкретного сервиса
./scripts/deploy.sh logs parser
./scripts/deploy.sh logs api
./scripts/deploy.sh logs keydb
./scripts/deploy.sh logs nginx

# Обновление всех сервисов
./scripts/deploy.sh update

# Резервное копирование
./scripts/deploy.sh backup
```

### Мониторинг

```bash
# Проверка здоровья
./scripts/monitor.sh health

# Метрики системы
./scripts/monitor.sh metrics

# Проверка алертов
./scripts/monitor.sh alerts

# Проверка парсера
./scripts/monitor.sh parser

# Непрерывный мониторинг
./scripts/monitor.sh monitor
```

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
- ✅ **Rate Limiting** на уровне Nginx и API
- ✅ **Health Check** без авторизации
- ✅ **Non-root пользователи** в Docker контейнерах
- ✅ **Сетевая изоляция** через Docker networks
- ✅ **Логирование** всех запросов

### Рекомендации для продакшена
1. **Измените пароли** в `.env`
2. **Настроите HTTPS** с SSL сертификатами
3. **Ограничьте доступ** к портам 6379 и 8080
4. **Настройте файрвол**
5. **Регулярно обновляйте** Docker образы

## 📈 Производительность

### Ожидаемая производительность
- **Rate Limit**: 3000 запросов/минуту
- **Response Time**: < 100ms для health check
- **Memory Usage**: ~200MB для API, ~100MB для KeyDB, ~150MB для парсера
- **CPU Usage**: < 10% в обычном режиме
- **Data Update**: каждые 7 минут

## 🔍 Мониторинг и логирование

### Доступные метрики
- ✅ **Health Status** - статус всех сервисов
- ✅ **Resource Usage** - CPU, память, сеть
- ✅ **KeyDB Metrics** - память, клиенты, операции
- ✅ **API Response Times** - время ответа endpoints
- ✅ **Parser Status** - статус парсера и количество данных
- ✅ **Error Rates** - количество ошибок

### Логи
```bash
# Все сервисы
./scripts/deploy.sh logs

# Конкретный сервис
./scripts/deploy.sh logs api
./scripts/deploy.sh logs parser
./scripts/deploy.sh logs keydb
./scripts/deploy.sh logs nginx
```

## 🚨 Устранение неполадок

### Частые проблемы

1. **Сервисы не запускаются**
   ```bash
   # Проверьте логи
   ./scripts/deploy.sh logs
   
   # Проверьте переменные окружения
   cat .env
   ```

2. **API не отвечает**
   ```bash
   # Проверьте здоровье
   ./scripts/monitor.sh health
   
   # Проверьте подключение к KeyDB
   docker-compose -f docker-compose.full.yml exec keydb keydb-cli ping
   ```

3. **Парсер не работает**
   ```bash
   # Проверьте парсер
   ./scripts/monitor.sh parser
   
   # Проверьте логи парсера
   ./scripts/deploy.sh logs parser
   ```

4. **Высокое использование ресурсов**
   ```bash
   # Проверьте метрики
   ./scripts/monitor.sh metrics
   
   # Проверьте алерты
   ./scripts/monitor.sh alerts
   ```

## 🔄 Обновление

### Обновление системы

```bash
# Остановите сервисы
./scripts/deploy.sh stop

# Обновите код
git pull  # или замените файлы

# Пересоберите и запустите
./scripts/deploy.sh update
```

### Обновление Docker образов

```bash
# Обновите все образы
docker-compose -f docker-compose.full.yml pull

# Перезапустите с новыми образами
./scripts/deploy.sh restart
```

## 📚 Дополнительная документация

- `docs/API.md` - Подробная документация API
- `docs/PARSER.md` - Документация парсера
- `docs/DEPLOYMENT.md` - Инструкции по развертыванию
- `examples/` - Примеры использования API

## 🎯 Заключение

Эта система предоставляет:
- ✅ **Автоматический сбор данных** о пунктах пропуска
- ✅ **REST API** для доступа к данным
- ✅ **Высокую производительность** и надежность
- ✅ **Простое развертывание** через Docker
- ✅ **Мониторинг и логирование**
- ✅ **Безопасность** и аутентификацию

**Система готова к продакшену!** 🚀


