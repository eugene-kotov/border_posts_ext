#!/bin/bash

# Скрипт для исправления проблемы с KeyDB RDB файлами
# Usage: ./fix_keydb.sh [--force] [--backup]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.prod.yml"
PROJECT_NAME="checkpoint-prod"
BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
ALTERNATIVE_PORT="6380"

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

# Create backup
create_backup() {
    log "Creating backup..."
    mkdir -p $BACKUP_DIR
    
    # Backup KeyDB data if container is running
    if $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps keydb | grep -q "Up"; then
        log "Backing up KeyDB data..."
        $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME exec -T keydb keydb-cli --rdb /data/backup.rdb 2>/dev/null || true
        docker cp $($DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps -q keydb):/data/backup.rdb $BACKUP_DIR/ 2>/dev/null || true
    fi
    
    # Backup configuration files
    cp keydb.conf $BACKUP_DIR/ 2>/dev/null || true
    cp docker-compose.prod.yml $BACKUP_DIR/ 2>/dev/null || true
    
    success "Backup created in $BACKUP_DIR"
}

# Check if KeyDB is having RDB issues
check_keydb_issues() {
    log "Checking KeyDB for RDB issues..."
    
    if ! $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps keydb | grep -q "Up"; then
        warning "KeyDB container is not running"
        return 0
    fi
    
    local logs=$($DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME logs keydb | tail -50)
    if echo "$logs" | grep -q "Permission denied\|Failed opening the RDB file"; then
        error "KeyDB RDB issues detected"
        return 1
    else
        success "No KeyDB RDB issues detected"
        return 0
    fi
}

# Check and free port 6379
check_and_free_port() {
    log "Checking port 6379 availability..."
    
    # Check if port is in use by Docker containers
    local port_containers=$(docker ps --format "table {{.Names}}\t{{.Ports}}" | grep ":6379" || true)
    if [ -n "$port_containers" ]; then
        log "Port 6379 is in use by Docker containers:"
        echo "$port_containers"
        
        # Stop all containers using port 6379
        log "Stopping containers using port 6379..."
        docker ps --format "{{.Names}}" | grep -E "(keydb|redis)" | xargs -r docker stop
        sleep 5
    fi
    
    # Check if port is in use by system processes
    if command -v netstat &> /dev/null; then
        local port_processes=$(netstat -tlnp 2>/dev/null | grep ":6379" || true)
        if [ -n "$port_processes" ]; then
            warning "Port 6379 is in use by system processes:"
            echo "$port_processes"
            warning "You may need to stop these processes manually"
        fi
    elif command -v ss &> /dev/null; then
        local port_processes=$(ss -tlnp | grep ":6379" || true)
        if [ -n "$port_processes" ]; then
            warning "Port 6379 is in use by system processes:"
            echo "$port_processes"
            warning "You may need to stop these processes manually"
        fi
    fi
}

# Create temporary docker-compose with alternative port
create_temp_compose() {
    log "Creating temporary docker-compose with port $ALTERNATIVE_PORT..."
    
    # Backup original compose file
    cp $COMPOSE_FILE ${COMPOSE_FILE}.backup
    
    # Create temporary compose file with alternative port
    sed "s/6379:6379/${ALTERNATIVE_PORT}:6379/g" $COMPOSE_FILE > ${COMPOSE_FILE}.tmp
    COMPOSE_FILE="${COMPOSE_FILE}.tmp"
    
    warning "Using alternative port $ALTERNATIVE_PORT instead of 6379"
    warning "Remember to update your API configuration to use port $ALTERNATIVE_PORT"
}

# Restore original docker-compose
restore_compose() {
    if [ -f "${COMPOSE_FILE}.backup" ]; then
        log "Restoring original docker-compose file..."
        mv ${COMPOSE_FILE}.backup $COMPOSE_FILE
        rm -f ${COMPOSE_FILE}.tmp
    fi
}

# Fix KeyDB configuration
fix_keydb() {
    log "Fixing KeyDB RDB file issues..."
    check_docker_compose
    
    # Check if backup is needed
    if [[ "$1" == "--backup" ]] || [[ "$2" == "--backup" ]]; then
        create_backup
    fi
    
    # Check and free port 6379
    check_and_free_port
    
    # Stop containers
    log "Stopping containers..."
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME down
    
    # Remove problematic volume if force flag is set
    if [[ "$1" == "--force" ]] || [[ "$2" == "--force" ]]; then
        log "Force removing KeyDB volume..."
        docker volume rm ${PROJECT_NAME}_keydb_data 2>/dev/null || true
    fi
    
    # Create local data directory
    log "Creating local data directory..."
    mkdir -p ./keydb_data
    chmod 755 ./keydb_data
    
    # Verify configuration files
    log "Verifying configuration files..."
    if [ ! -f "keydb.conf" ]; then
        error "keydb.conf not found"
        exit 1
    fi
    
    if [ ! -f "docker-compose.prod.yml" ]; then
        error "docker-compose.prod.yml not found"
        exit 1
    fi
    
    # Start containers
    log "Starting containers with fixed configuration..."
    if ! $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME up -d; then
        error "Failed to start containers. Port 6379 might be in use."
        
        # Try with alternative port
        log "Attempting to start with alternative port $ALTERNATIVE_PORT..."
        create_temp_compose
        
        if ! $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME up -d; then
            error "Failed to start containers even with alternative port"
            restore_compose
            exit 1
        fi
        
        success "Containers started with alternative port $ALTERNATIVE_PORT"
    fi
    
    # Wait for services to be healthy
    log "Waiting for services to be healthy..."
    sleep 15
    
    # Check status
    log "Checking service status..."
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME ps
    
    # Check KeyDB logs
    log "Checking KeyDB logs (last 20 lines)..."
    $DOCKER_COMPOSE -f $COMPOSE_FILE -p $PROJECT_NAME logs --tail=20 keydb
    
    # Verify fix
    if check_keydb_issues; then
        success "KeyDB RDB issues have been resolved!"
    else
        error "KeyDB RDB issues persist. Check logs for more details."
        restore_compose
        exit 1
    fi
    
    # Clean up temporary files
    restore_compose
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force   Force remove KeyDB volume (will lose data)"
    echo "  --backup  Create backup before fixing"
    echo "  --check   Only check for issues without fixing"
    echo "  --help    Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                    # Fix with backup"
    echo "  $0 --force           # Force fix (lose data)"
    echo "  $0 --check           # Only check for issues"
}

# Main script logic
case "${1:-fix}" in
    --help|-h)
        show_usage
        ;;
    --check)
        check_keydb_issues
        ;;
    fix|--force|--backup)
        fix_keydb "$@"
        ;;
    *)
        error "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac
