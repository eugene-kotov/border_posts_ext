#!/bin/bash

# Скрипт для тестирования API
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅${NC} $1"
}

error() {
    echo -e "${RED}❌${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

# Проверка доступности сервиса
check_service() {
    local url=$1
    local name=$2
    
    if curl -s --connect-timeout 5 "$url" > /dev/null 2>&1; then
        success "$name доступен"
        return 0
    else
        error "$name недоступен"
        return 1
    fi
}

# Тест health endpoint
test_health() {
    log "Тестирование health endpoint..."
    
    response=$(curl -s http://localhost/health 2>/dev/null || echo "ERROR")
    if [[ "$response" == *"healthy"* ]] || [[ "$response" == *"UP"* ]]; then
        success "Health endpoint работает"
        echo "Ответ: $response"
    else
        error "Health endpoint не работает"
        echo "Ответ: $response"
    fi
}

# Тест API с разными вариантами авторизации
test_api_auth() {
    log "Тестирование API с авторизацией..."
    
    # Варианты авторизации
    declare -A auth_variants=(
        ["admin:checkpoint2025"]="dHJ1Y2tkcml2ZXI6Y2hlY2twb2ludEAyMDI1"
        ["admin:checkpoint2025"]="YWRtaW46Y2hlY2twb2ludDIwMjU="
        ["truckdriver:checkpoint@2025"]="dHJ1Y2tkcml2ZXI6Y2hlY2twb2ludEAyMDI1"
    )
    
    for auth_desc in "${!auth_variants[@]}"; do
        auth_header="${auth_variants[$auth_desc]}"
        
        log "Тестирование с авторизацией: $auth_desc"
        
        response=$(curl -s -w "%{http_code}" -o /tmp/api_response.json \
            --location 'http://localhost/api/v1/checkpoints' \
            --header "Authorization: Basic $auth_header" 2>/dev/null || echo "000")
        
        case $response in
            200)
                success "Успешный запрос (HTTP $response)"
                echo "Ответ: $(cat /tmp/api_response.json | head -c 200)..."
                ;;
            401)
                warning "Неверная авторизация (HTTP $response)"
                ;;
            404)
                warning "Эндпоинт не найден (HTTP $response)"
                ;;
            000)
                error "Нет соединения"
                ;;
            *)
                warning "Неожиданный ответ (HTTP $response)"
                ;;
        esac
        echo ""
    done
    
    rm -f /tmp/api_response.json
}

# Тест прямого подключения к API инстансам
test_direct_api() {
    log "Тестирование прямого подключения к API инстансам..."
    
    for i in {1..3}; do
        log "Тестирование api$i..."
        
        # Проверяем health каждого инстанса
        if docker exec checkpoint-api${i}-full wget --quiet --tries=1 --spider http://localhost:8080/health 2>/dev/null; then
            success "api$i работает"
        else
            error "api$i не работает"
        fi
    done
}

# Основная функция
main() {
    log "Тестирование Checkpoint API..."
    
    # Проверка доступности сервисов
    check_service "http://localhost" "Nginx (порт 80)"
    check_service "http://localhost/health" "Health endpoint"
    
    # Тесты
    test_health
    echo ""
    test_api_auth
    echo ""
    test_direct_api
    
    echo ""
    log "Полезные команды для отладки:"
    echo "• Логи Nginx: docker logs checkpoint-nginx-full"
    echo "• Логи API: docker logs checkpoint-api1-full"
    echo "• Логи KeyDB: docker logs checkpoint-keydb-full"
    echo "• Статус контейнеров: docker-compose -f docker-compose.full.yml -p checkpoint-full ps"
    echo "• Подключение к KeyDB: docker exec -it checkpoint-keydb-full keydb-cli"
}

main "$@"


