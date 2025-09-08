#!/bin/bash

# Full System Deployment Script for Checkpoint API + Parser
# Usage: ./deploy.sh [start|stop|restart|status|logs|update]

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

# Check if Docker and Docker Compose are installed
check_dependencies() {
    log "Checking dependencies..."
    
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check for Docker Compose v2 (docker compose) or v1 (docker-compose)
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
        log "Using Docker Compose v2"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
        log "Using Docker Compose v1"
    else
        error "Docker Compose is not installed or not in PATH"
        exit 1
    fi
    
    success "Dependencies check passed"
}

# Check if .env exists
check_env_file() {
    if [ ! -f ".env" ]; then
        warning ".env file not found"
        if [ -f "api/env.prod.example" ]; then
            log "Copying env.prod.example to .env"
            cp api/env.prod.example .env
            warning "Please edit .env with your production values"
        else
            error "No environment file found. Please create .env"
            exit 1
        fi
    fi
}

# Start services
start_services() {
    log "Starting full system (API + Parser + KeyDB + Nginx)..."
    check_dependencies
    check_env_file
    
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME up -d
    
    log "Waiting for services to be healthy..."
    sleep 15
    
    # Check health
    if $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps | grep -q "Up (healthy)"; then
        success "Services started successfully"
        show_status
    else
        error "Some services failed to start properly"
        show_logs
        exit 1
    fi
}

# Stop services
stop_services() {
    log "Stopping all services..."
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME down
    success "Services stopped"
}

# Restart services
restart_services() {
    log "Restarting all services..."
    stop_services
    sleep 5
    start_services
}

# Show status
show_status() {
    log "Service status:"
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps
    
    echo ""
    log "Health check:"
    if command -v curl &> /dev/null; then
        if curl -s http://localhost/health > /dev/null; then
            success "API is responding"
        else
            warning "API health check failed"
        fi
    else
        warning "curl not available for health check"
    fi
    
    echo ""
    log "Parser status:"
    if $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME logs parser | tail -5 | grep -q "✅"; then
        success "Parser is running"
    else
        warning "Parser may not be running properly"
    fi
}

# Show logs
show_logs() {
    log "Showing recent logs..."
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME logs --tail=50
}

# Show logs for specific service
show_service_logs() {
    local service=${1:-"all"}
    if [ "$service" = "all" ]; then
        show_logs
    else
        log "Showing logs for $service..."
        $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME logs --tail=50 $service
    fi
}

# Update services
update_services() {
    log "Updating all services..."
    
    # Pull latest images
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME pull
    
    # Rebuild and restart
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME up -d --build
    
    # Clean up old images
    docker image prune -f
    
    success "Services updated"
}

# Backup data
backup_data() {
    log "Creating backup..."
    
    BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p $BACKUP_DIR
    
    # Backup KeyDB data
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME exec -T keydb keydb-cli --rdb /data/backup.rdb
    docker cp $($DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps -q keydb):/data/backup.rdb $BACKUP_DIR/
    
    # Backup parser logs
    if [ -d "parser/logs" ]; then
        cp -r parser/logs $BACKUP_DIR/
    fi
    
    success "Backup created in $BACKUP_DIR"
}

# Main script logic
case "${1:-start}" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        restart_services
        ;;
    status)
        show_status
        ;;
    logs)
        show_service_logs $2
        ;;
    update)
        update_services
        ;;
    backup)
        backup_data
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|update|backup}"
        echo ""
        echo "Commands:"
        echo "  start   - Start all services (API + Parser + KeyDB + Nginx)"
        echo "  stop    - Stop all services"
        echo "  restart - Restart all services"
        echo "  status  - Show service status"
        echo "  logs    - Show logs (optionally specify service: api|parser|keydb|nginx)"
        echo "  update  - Update and restart services"
        echo "  backup  - Create data backup"
        echo ""
        echo "Examples:"
        echo "  $0 start"
        echo "  $0 logs parser"
        echo "  $0 status"
        exit 1
        ;;
esac