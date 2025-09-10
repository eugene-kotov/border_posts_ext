#!/bin/bash

# Full System Monitoring Script for Checkpoint API + Parser
# Usage: ./monitor.sh [health|metrics|alerts|parser]

set -e

COMPOSE_FILE="docker-compose.full.yml"
PROJECT_NAME="checkpoint-full"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Health check
check_health() {
    log "Performing health checks..."
    check_docker_compose
    
    # Check if services are running
    if ! $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps | grep -q "Up"; then
        error "Some services are not running"
        return 1
    fi
    
    # Check API health endpoint
    if command -v curl &> /dev/null; then
        local health_response=$(curl -s http://localhost/health 2>/dev/null || echo "ERROR")
        if [[ "$health_response" == *"healthy"* ]] || [[ "$health_response" == *"UP"* ]]; then
            success "API health check passed"
            echo "Response: $health_response"
        else
            error "API health check failed"
            return 1
        fi
    else
        warning "curl not available for health check"
    fi
    
    # Check KeyDB connection
    if $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME exec -T keydb keydb-cli ping | grep -q "PONG"; then
        success "KeyDB is responding"
    else
        error "KeyDB is not responding"
        return 1
    fi
    
    # Check parser status
    local parser_logs=$($DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME logs parser | tail -10)
    if echo "$parser_logs" | grep -q "✅\|🔄\|📊"; then
        success "Parser is active"
    else
        warning "Parser may not be running properly"
    fi
    
    return 0
}

# Show metrics
show_metrics() {
    log "Collecting metrics..."
    check_docker_compose
    
    echo ""
    echo "=== Container Status ==="
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps
    
    echo ""
    echo "=== Resource Usage ==="
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" \
        $($DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps -q)
    
    echo ""
    echo "=== KeyDB Info ==="
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME exec -T keydb keydb-cli info memory | head -10
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME exec -T keydb keydb-cli info clients | head -5
    
    echo ""
    echo "=== Parser Status ==="
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME logs parser | tail -5
    
    echo ""
    echo "=== API Metrics ==="
    if command -v curl &> /dev/null; then
        echo "Health endpoint response time:"
        time curl -s http://localhost/health > /dev/null
    fi
}

# Check parser specifically
check_parser() {
    log "Checking parser status..."
    check_docker_compose
    
    echo ""
    echo "=== Parser Container Status ==="
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps parser
    
    echo ""
    echo "=== Recent Parser Logs ==="
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME logs parser | tail -20
    
    echo ""
    echo "=== Parser Health Check ==="
    if $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps parser | grep -q "Up"; then
        success "Parser container is running"
    else
        error "Parser container is not running"
    fi
    
    echo ""
    echo "=== KeyDB Data Check ==="
    local checkpoint_count=$($DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME exec -T keydb keydb-cli scard checkpoints:all 2>/dev/null || echo "0")
    echo "Total checkpoints in KeyDB: $checkpoint_count"
    
    if [ "$checkpoint_count" -gt 0 ]; then
        success "Parser has populated KeyDB with data"
    else
        warning "No checkpoint data found in KeyDB"
    fi
}

# Check for alerts
check_alerts() {
    log "Checking for alerts..."
    check_docker_compose
    
    local alerts=0
    
    # Check disk space
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 80 ]; then
        warning "Disk usage is high: ${disk_usage}%"
        ((alerts++))
    fi
    
    # Check memory usage
    local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [ "$mem_usage" -gt 80 ]; then
        warning "Memory usage is high: ${mem_usage}%"
        ((alerts++))
    fi
    
    # Check if services are healthy
    if ! check_health > /dev/null 2>&1; then
        error "Service health check failed"
        ((alerts++))
    fi
    
    # Check container restart count
    local restart_count=$($DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps | grep -c "Restarting" || true)
    if [ "$restart_count" -gt 0 ]; then
        warning "Some containers are restarting"
        ((alerts++))
    fi
    
    # Check parser data freshness
    local checkpoint_count=$($DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME exec -T keydb keydb-cli scard checkpoints:all 2>/dev/null || echo "0")
    if [ "$checkpoint_count" -eq 0 ]; then
        warning "No checkpoint data in KeyDB - parser may not be working"
        ((alerts++))
    fi
    
    if [ "$alerts" -eq 0 ]; then
        success "No alerts detected"
    else
        error "$alerts alert(s) detected"
        return 1
    fi
}

# Continuous monitoring
monitor_continuous() {
    log "Starting continuous monitoring (press Ctrl+C to stop)..."
    
    while true; do
        clear
        echo "=== Checkpoint System Monitor - $(date) ==="
        echo ""
        
        if check_health; then
            echo ""
            show_metrics
        else
            error "Health check failed"
        fi
        
        echo ""
        echo "Next check in 30 seconds..."
        sleep 30
    done
}

# Main script logic
case "${1:-health}" in
    health)
        check_health
        ;;
    metrics)
        show_metrics
        ;;
    alerts)
        check_alerts
        ;;
    parser)
        check_parser
        ;;
    monitor)
        monitor_continuous
        ;;
    *)
        echo "Usage: $0 {health|metrics|alerts|parser|monitor}"
        echo ""
        echo "Commands:"
        echo "  health   - Perform health checks"
        echo "  metrics  - Show system metrics"
        echo "  alerts   - Check for alerts"
        echo "  parser   - Check parser status specifically"
        echo "  monitor  - Continuous monitoring"
        exit 1
        ;;
esac