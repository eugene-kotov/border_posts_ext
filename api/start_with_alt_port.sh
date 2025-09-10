#!/bin/bash

# Скрипт для запуска с альтернативным портом 6380
# Usage: ./start_with_alt_port.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.prod-alt.yml"
PROJECT_NAME="checkpoint-prod"

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

log "Starting Checkpoint API with alternative port 6380..."

# Check dependencies
check_docker_compose

# Stop any existing containers
log "Stopping existing containers..."
$DOCKER_COMPOSE -f docker-compose.prod.yml -p $PROJECT_NAME down 2>/dev/null || true

# Start with alternative port
log "Starting services with port 6380..."
$DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME up -d

# Wait for services
log "Waiting for services to be healthy..."
sleep 15

# Check status
log "Service status:"
$DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps

# Test KeyDB connection
log "Testing KeyDB connection on port 6380..."
if command -v keydb-cli &> /dev/null; then
    if keydb-cli -p 6380 ping | grep -q "PONG"; then
        success "KeyDB is responding on port 6380"
    else
        warning "KeyDB connection test failed"
    fi
else
    warning "keydb-cli not available for connection test"
fi

# Test API
log "Testing API health..."
if command -v curl &> /dev/null; then
    if curl -s http://localhost/health > /dev/null; then
        success "API is responding"
    else
        warning "API health check failed"
    fi
else
    warning "curl not available for API test"
fi

echo ""
success "Services started with alternative port configuration!"
echo ""
echo -e "${YELLOW}Important notes:${NC}"
echo "• KeyDB is now accessible on port 6380 (instead of 6379)"
echo "• API still connects to KeyDB internally on port 6379"
echo "• External connections to KeyDB should use port 6380"
echo ""
echo -e "${BLUE}Useful commands:${NC}"
echo "• Check status: $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps"
echo "• View logs: $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME logs"
echo "• Stop services: $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME down"
echo "• Connect to KeyDB: keydb-cli -p 6380"
