#!/bin/bash

# Скрипт мониторинга ресурсов для системы checkpoint
# Оптимизирован для конфигурации: 2 CPU, 768 MB RAM

echo "=== МОНИТОРИНГ РЕСУРСОВ CHECKPOINT SYSTEM ==="
echo "Дата: $(date)"
echo ""

# Проверка использования ресурсов контейнерами
echo "📊 ИСПОЛЬЗОВАНИЕ РЕСУРСОВ КОНТЕЙНЕРАМИ:"
echo "----------------------------------------"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" checkpoint-keydb-full checkpoint-api-full checkpoint-parser-full checkpoint-nginx-full 2>/dev/null || echo "Некоторые контейнеры не запущены"

echo ""
echo "💾 ОБЩЕЕ ИСПОЛЬЗОВАНИЕ ПАМЯТИ СИСТЕМЫ:"
echo "------------------------------------"
free -h

echo ""
echo "🖥️  ИСПОЛЬЗОВАНИЕ CPU:"
echo "---------------------"
top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print "CPU Usage: " 100 - $1 "%"}'

echo ""
echo "📈 ДИСКОВОЕ ПРОСТРАНСТВО:"
echo "------------------------"
df -h / | tail -1 | awk '{print "Root partition: " $3 " used of " $2 " (" $5 ")"}'

echo ""
echo "🔍 СТАТУС КОНТЕЙНЕРОВ:"
echo "---------------------"
docker-compose -f docker-compose.full.yml -p checkpoint-full ps

echo ""
echo "📋 ЛОГИ СИСТЕМЫ (последние 5 строк):"
echo "------------------------------------"
docker-compose -f docker-compose.full.yml -p checkpoint-full logs --tail=5 2>/dev/null || echo "Логи недоступны"

echo ""
echo "✅ Мониторинг завершен"
