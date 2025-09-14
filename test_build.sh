#!/bin/bash

# Скрипт для тестирования сборки с Go 1.23

echo "=== ТЕСТИРОВАНИЕ СБОРКИ С GO 1.23 ==="
echo "Дата: $(date)"
echo ""

# Переходим в директорию API
cd api

echo "📦 Проверка версии Go в Docker..."
docker run --rm golang:1.23-alpine go version

echo ""
echo "🔨 Тестирование сборки API..."
docker build -f Dockerfile.prod -t checkpoint-api-test .

if [ $? -eq 0 ]; then
    echo "✅ Сборка успешна!"
    
    echo ""
    echo "📊 Размер образа:"
    docker images checkpoint-api-test --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
    
    echo ""
    echo "🧹 Очистка тестового образа..."
    docker rmi checkpoint-api-test
    
else
    echo "❌ Ошибка сборки!"
    exit 1
fi

echo ""
echo "✅ Тестирование завершено успешно!"
