# Checkpoint System

Система мониторинга загруженности пунктов пропуска Казахстана. Автоматический сбор данных с [cgr.qoldau.kz](https://cgr.qoldau.kz) и REST API для доступа.

## Архитектура

```
Client → Angie (TLS 1.3, HTTP/2, brotli/zstd/gzip) → Go API → KeyDB ← Python Parser
```

| Компонент | Описание | Образ |
|-----------|----------|:-----:|
| **Angie** | Reverse proxy, TLS termination, compression | 32 MB RAM |
| **Go API** | REST API (Go 1.25, Gin, slog JSON logging) | 45 MB image |
| **Python Parser** | Сбор данных каждые 7 мин (logging JSON) | 148 MB image |
| **KeyDB** | In-memory хранилище (48 checkpoints, ~193 ключа) | 64 MB RAM |

**Target VPS**: 1 CPU / 512 MB RAM / 6 GB SSD

## Быстрый старт

### 1. Клонирование и настройка

```bash
git clone https://github.com/eugene-kotov/border_posts_ext.git
cd border_posts_ext

# Создать .env из шаблона и настроить
make env-init
nano .env  # задать DOMAIN, AUTH_USERNAME, AUTH_PASSWORD
```

### 2. Установка и запуск (Podman Quadlets)

```bash
# Установить Quadlet-файлы в systemd
make install

# Собрать образы API и Parser
make build

# Запустить все сервисы
make start
```

### 3. Проверка

```bash
make status   # статус всех сервисов
make health   # проверка health endpoints
make test     # тест API endpoints
```

## Управление

Все операции через `make`:

```bash
make help         # список команд
make start        # запуск
make stop         # остановка
make restart      # перезапуск
make status       # статус сервисов
make logs         # логи всех сервисов (journalctl)
make logs-api     # логи API
make logs-parser  # логи парсера
make stats        # потребление ресурсов
make health       # health checks
make test         # тест API endpoints
make build        # пересборка образов
make update       # обновление образов + перезапуск
make shell-keydb  # KeyDB CLI
make shell-api    # shell в API контейнер
make clean        # остановка + удаление quadlet-файлов
make uninstall    # полная очистка (+ образы + volumes)
```

## TLS Сертификат

```bash
# Генерация Angie конфига с TLS для домена из .env
make tls-init

# Проверка сертификата
make tls-status
make tls-test
```

Сертификат выдаётся автоматически через Let's Encrypt ACME. Требования:
- DNS A-запись домена → IP сервера
- Порты 80 и 443 открыты

## API Endpoints

| Метод | Путь | Auth | Описание |
|-------|------|:----:|----------|
| GET | `/health` | нет | Health check |
| GET | `/api/v1/checkpoints` | Basic | Все пункты пропуска |
| GET | `/api/v1/checkpoints/:id` | Basic | Данные одного пункта |
| GET | `/api/v1/checkpoints/ids` | Basic | Список ID |
| GET | `/api/v1/stats` | Basic | Сводная статистика |

```bash
# Health
curl https://checkpoint.truck.kz/health

# Данные (с авторизацией)
curl -u admin:password https://checkpoint.truck.kz/api/v1/checkpoints
curl -u admin:password https://checkpoint.truck.kz/api/v1/stats
```

## Конфигурация (.env)

```bash
DOMAIN=checkpoint.truck.kz    # Домен для TLS
KEYDB_PASSWORD=               # Пароль KeyDB (опционально)
AUTH_USERNAME=admin            # Логин API
AUTH_PASSWORD=<secret>         # Пароль API
RATE_LIMIT=3000               # Лимит запросов/мин
```

## Ресурсы

| Контейнер | CPU | RAM | Реальное потребление |
|-----------|:---:|:---:|:--------------------:|
| KeyDB | 20% | 64M | ~9 MB |
| API | 30% | 64M | ~5 MB |
| Parser | 30% | 80M | ~41 MB |
| Angie | 10% | 32M | ~3 MB |
| **Итого** | **90%** | **240M** | **~58 MB** |

## Структура проекта

```
├── api/
│   ├── main.go              # Go API (515 LOC, slog, graceful shutdown)
│   ├── Dockerfile.prod      # Multi-stage build (Go 1.25 → Alpine)
│   ├── go.mod / go.sum
│   └── keydb.conf
├── parser/
│   ├── new_checkpoint_data.py  # Parser (644 LOC, logging JSON)
│   ├── links.txt               # 48 URLs для парсинга
│   ├── Dockerfile
│   └── requirements.txt
├── quadlets/                 # Podman Quadlet (systemd units)
│   ├── checkpoint-keydb.container
│   ├── checkpoint-api.container
│   ├── checkpoint-parser.container
│   ├── checkpoint-angie.container
│   ├── checkpoint-keydb.volume
│   ├── checkpoint-angie-logs.volume
│   ├── checkpoint-acme.volume
│   └── checkpoint.network
├── angie.loadbalancer.conf          # Angie config (TLS 1.3, HTTP/2)
├── angie.loadbalancer.conf.template # Template для make tls-init
├── docker-compose.full.yml          # Compose для dev/testing
├── Makefile                         # Все операции
├── setup-vps.sh                     # Bootstrap VPS
├── .env.example                     # Шаблон конфигурации
└── examples/                        # Примеры использования API
```

## Безопасность

- ✅ TLS 1.3 + ACME auto-renewal
- ✅ HTTP/2
- ✅ HSTS (2 years)
- ✅ Security headers (X-Frame-Options, X-Content-Type-Options)
- ✅ Basic Auth для API
- ✅ Rate limiting (10 req/s per IP)
- ✅ Non-root контейнеры
- ✅ Пароли только из .env (0 хардкодов)
- ✅ Graceful shutdown (5s drain)
- ✅ Structured JSON logging

## Производительность

- **1,700+ rps** при 500 VUs (k6 load test)
- **0% ошибок** под нагрузкой
- **p95 latency**: 102ms (health), 414ms (checkpoints)
- **Brotli/zstd/gzip** compression
- **Pipeline batching** для KeyDB (N+1 fix)

## Требования

- **VPS**: 1 CPU / 512 MB RAM / 6 GB SSD
- **OS**: Ubuntu/Debian с systemd
- **Podman**: 4.4+ (Quadlets)
- **Make**: GNU Make
