# Руководство по развертыванию Checkpoint API + Parser

## 🎯 Обзор

Это руководство описывает процесс развертывания полной системы Checkpoint API с парсером данных в продакшен среде.

## 📋 Требования

### Системные требования
- **ОС**: Linux (Ubuntu 20.04+, CentOS 8+, Debian 11+)
- **RAM**: Минимум 2GB, рекомендуется 4GB+
- **CPU**: Минимум 2 ядра
- **Диск**: Минимум 10GB свободного места
- **Сеть**: Доступ к интернету для загрузки Docker образов

### Программное обеспечение
- **Docker**: 20.10+
- **Docker Compose**: 2.0+
- **Git**: для клонирования репозитория (опционально)

## 🚀 Установка

### 1. Подготовка системы

```bash
# Обновление системы (Ubuntu/Debian)
sudo apt update && sudo apt upgrade -y

# Установка Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Установка Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Перезагрузка для применения изменений группы
sudo reboot
```

### 2. Получение релиза

```bash
# Создание рабочей директории
mkdir -p /opt/checkpoint-system
cd /opt/checkpoint-system

# Клонирование репозитория (если доступен)
# git clone <repository-url> .

# Или копирование файлов релиза
# scp -r release/ user@server:/opt/checkpoint-system/
```

### 3. Настройка окружения

```bash
# Копирование файла с переменными окружения
cp api/env.prod.example .env

# Редактирование переменных окружения
nano .env
```

**Важно**: Измените следующие значения в `.env`:

```bash
# KeyDB Configuration
KEYDB_PASSWORD=your_very_strong_password_here

# API Authentication
AUTH_USERNAME=admin
AUTH_PASSWORD=your_very_strong_api_password_here

# Rate Limiting
RATE_LIMIT=3000
```

### 4. Настройка прав доступа

```bash
# Сделать скрипты исполняемыми
chmod +x scripts/*.sh

# Создать директории для логов
mkdir -p parser/logs
mkdir -p ssl
```

## 🔧 Развертывание

### 1. Запуск системы

```bash
# Запуск всех сервисов
./scripts/deploy.sh start
```

### 2. Проверка развертывания

```bash
# Проверка статуса
./scripts/deploy.sh status

# Проверка здоровья
./scripts/monitor.sh health

# Проверка парсера
./scripts/monitor.sh parser
```

### 3. Тестирование API

```bash
# Health check
curl http://localhost/health

# Тест с авторизацией
curl -u admin:your_password http://localhost/api/v1/checkpoints

# Запуск полного теста
python examples/test_api.py
```

## 🔒 Безопасность

### 1. Настройка файрвола

```bash
# UFW (Ubuntu)
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable

# iptables (CentOS/RHEL)
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

### 2. Настройка HTTPS (рекомендуется)

```bash
# Получение SSL сертификата (Let's Encrypt)
sudo apt install certbot
sudo certbot certonly --standalone -d your-domain.com

# Копирование сертификатов
sudo cp /etc/letsencrypt/live/your-domain.com/fullchain.pem ssl/cert.pem
sudo cp /etc/letsencrypt/live/your-domain.com/privkey.pem ssl/key.pem
sudo chown $USER:$USER ssl/*.pem

# Раскомментирование HTTPS секции в nginx.prod.conf
# Перезапуск сервисов
./scripts/deploy.sh restart
```

### 3. Ограничение доступа к KeyDB

```bash
# Редактирование keydb.conf
nano api/keydb.conf

# Раскомментировать и установить пароль
requirepass your_very_strong_keydb_password

# Обновить .env
KEYDB_PASSWORD=your_very_strong_keydb_password

# Перезапуск
./scripts/deploy.sh restart
```

## 📊 Мониторинг

### 1. Настройка мониторинга

```bash
# Создание cron задачи для мониторинга
crontab -e

# Добавить строку для проверки каждые 5 минут
*/5 * * * * /opt/checkpoint-system/scripts/monitor.sh alerts > /dev/null 2>&1
```

### 2. Настройка алертов

```bash
# Создание скрипта для отправки алертов
nano scripts/send_alert.sh

#!/bin/bash
# Скрипт для отправки алертов (email, Slack, etc.)
# Реализуйте по необходимости

chmod +x scripts/send_alert.sh
```

### 3. Логирование

```bash
# Настройка ротации логов
sudo nano /etc/logrotate.d/checkpoint-system

/opt/checkpoint-system/parser/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 $USER $USER
}
```

## 🔄 Обслуживание

### 1. Регулярные задачи

```bash
# Создание скрипта обслуживания
nano scripts/maintenance.sh

#!/bin/bash
# Еженедельное обслуживание
./scripts/deploy.sh backup
docker system prune -f
./scripts/monitor.sh alerts

chmod +x scripts/maintenance.sh

# Добавление в cron (еженедельно по воскресеньям в 2:00)
0 2 * * 0 /opt/checkpoint-system/scripts/maintenance.sh
```

### 2. Обновление системы

```bash
# Обновление кода
git pull  # или замена файлов

# Обновление сервисов
./scripts/deploy.sh update

# Проверка работоспособности
./scripts/monitor.sh health
```

### 3. Резервное копирование

```bash
# Создание резервной копии
./scripts/deploy.sh backup

# Восстановление из резервной копии
# 1. Остановить сервисы
./scripts/deploy.sh stop

# 2. Восстановить данные KeyDB
docker run --rm -v checkpoint-full_keydb_data:/data -v $(pwd)/backups/latest:/backup alpine sh -c "cp /backup/backup.rdb /data/"

# 3. Запустить сервисы
./scripts/deploy.sh start
```

## 🚨 Устранение неполадок

### 1. Частые проблемы

**Сервисы не запускаются:**
```bash
# Проверка логов
./scripts/deploy.sh logs

# Проверка переменных окружения
cat .env

# Проверка доступности портов
netstat -tlnp | grep -E ':(80|443|8080|6379)'
```

**API не отвечает:**
```bash
# Проверка здоровья
./scripts/monitor.sh health

# Проверка подключения к KeyDB
docker-compose -f docker-compose.full.yml exec keydb keydb-cli ping

# Проверка логов API
./scripts/deploy.sh logs api
```

**Парсер не работает:**
```bash
# Проверка парсера
./scripts/monitor.sh parser

# Проверка логов парсера
./scripts/deploy.sh logs parser

# Проверка подключения к интернету
docker-compose -f docker-compose.full.yml exec parser ping -c 3 8.8.8.8
```

### 2. Диагностика

```bash
# Проверка ресурсов
./scripts/monitor.sh metrics

# Проверка алертов
./scripts/monitor.sh alerts

# Проверка состояния контейнеров
docker-compose -f docker-compose.full.yml ps

# Проверка использования диска
df -h
docker system df
```

### 3. Восстановление

```bash
# Полный перезапуск
./scripts/deploy.sh stop
sleep 10
./scripts/deploy.sh start

# Очистка и пересборка
docker-compose -f docker-compose.full.yml down -v
docker system prune -f
./scripts/deploy.sh start
```

## 📈 Оптимизация производительности

### 1. Настройка KeyDB

```bash
# Редактирование keydb.conf
nano api/keydb.conf

# Увеличение лимита памяти
maxmemory 512mb
maxmemory-policy allkeys-lru

# Оптимизация персистентности
save 900 1
save 300 10
save 60 10000
```

### 2. Настройка Nginx

```bash
# Редактирование nginx.prod.conf
nano api/nginx.prod.conf

# Увеличение worker процессов
worker_processes auto;

# Оптимизация буферов
client_body_buffer_size 128k;
client_max_body_size 10m;
client_header_buffer_size 1k;
large_client_header_buffers 4 4k;
```

### 3. Мониторинг производительности

```bash
# Создание скрипта мониторинга производительности
nano scripts/performance_monitor.sh

#!/bin/bash
# Мониторинг производительности
./scripts/monitor.sh metrics
docker stats --no-stream

chmod +x scripts/performance_monitor.sh
```

## 🎯 Заключение

Следуя этому руководству, вы сможете:

1. ✅ **Развернуть** полную систему Checkpoint API + Parser
2. ✅ **Настроить** безопасность и мониторинг
3. ✅ **Обеспечить** высокую доступность и производительность
4. ✅ **Поддерживать** систему в рабочем состоянии

**Система готова к продакшену!** 🚀

