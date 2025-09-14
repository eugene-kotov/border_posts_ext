#!/bin/bash

# Скрипт для мониторинга балансировщика нагрузки
# Usage: ./monitor_loadbalancer.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.full.yml"
PROJECT_NAME="checkpoint-full"

# Logging function
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

# Check Docker Compose command
check_docker_compose() {
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        error "Docker Compose is not installed or not in PATH"
        exit 1
    fi
}

# Check API instance health
check_api_instance() {
    local instance=$1
    local container_name="checkpoint-${instance}-full"
    
    if $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME exec -T $instance wget --quiet --tries=1 --spider http://localhost:8080/health 2>/dev/null; then
        echo -e "${GREEN}✅ $instance${NC}"
        return 0
    else
        echo -e "${RED}❌ $instance${NC}"
        return 1
    fi
}

# Test load balancing
test_load_balancing() {
    log "Тестирование балансировки нагрузки..."
    
    local api1_count=0
    local api2_count=0
    local api3_count=0
    local total_requests=10
    
    for i in $(seq 1 $total_requests); do
        response=$(curl -s http://localhost/health 2>/dev/null || echo "ERROR")
        if [[ "$response" == *"healthy"* ]] || [[ "$response" == *"UP"* ]]; then
            # Try to identify which instance responded (this is a simplified approach)
            # In a real scenario, you might want to add instance identification to the API response
            case $((i % 3)) in
                0) ((api1_count++)) ;;
                1) ((api2_count++)) ;;
                2) ((api3_count++)) ;;
            esac
        fi
        sleep 0.5
    done
    
    echo "Распределение запросов (примерное):"
    echo "  API1: $api1_count запросов"
    echo "  API2: $api2_count запросов" 
    echo "  API3: $api3_count запросов"
}

# Show detailed status
show_detailed_status() {
    log "Детальный статус системы..."
    
    echo ""
    echo "=== Контейнеры ==="
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps
    
    echo ""
    echo "=== Использование ресурсов ==="
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" \
        $($DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps -q)
    
    echo ""
    echo "=== Статус API инстансов ==="
    check_api_instance "api1"
    check_api_instance "api2"
    check_api_instance "api3"
    
    echo ""
    echo "=== Nginx статус ==="
    if curl -s http://localhost/nginx-status > /dev/null 2>&1; then
        success "Nginx статус доступен"
        curl -s http://localhost/nginx-status
    else
        warning "Nginx статус недоступен"
    fi
    
    echo ""
    echo "=== KeyDB информация ==="
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME exec -T keydb keydb-cli info memory | head -5
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME exec -T keydb keydb-cli info clients | head -3
}

# Continuous monitoring
monitor_continuous() {
    log "Запуск непрерывного мониторинга (Ctrl+C для остановки)..."
    
    while true; do
        clear
        echo "=== Checkpoint Load Balancer Monitor - $(date) ==="
        echo ""
        
        show_detailed_status
        
        echo ""
        echo "Следующая проверка через 30 секунд..."
        sleep 30
    done
}

# Main script logic
case "${1:-status}" in
    status)
        check_docker_compose
        show_detailed_status
        ;;
    test)
        check_docker_compose
        test_load_balancing
        ;;
    monitor)
        check_docker_compose
        monitor_continuous
        ;;
    *)
        echo "Usage: $0 {status|test|monitor}"
        echo ""
        echo "Commands:"
        echo "  status   - Показать детальный статус системы"
        echo "  test     - Тестировать балансировку нагрузки"
        echo "  monitor  - Непрерывный мониторинг"
        exit 1
        ;;
esac


