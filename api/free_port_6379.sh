#!/bin/bash

# Скрипт для освобождения порта 6379
# Usage: ./free_port_6379.sh

set -e

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

log "Checking what's using port 6379..."

# Check Docker containers using port 6379
log "Checking Docker containers..."
local docker_containers=$(docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}" | grep ":6379" || true)
if [ -n "$docker_containers" ]; then
    echo "Docker containers using port 6379:"
    echo "$docker_containers"
    echo ""
    
    # Stop containers
    log "Stopping Docker containers using port 6379..."
    docker ps --format "{{.Names}}" | grep -E "(keydb|redis)" | xargs -r docker stop
    success "Docker containers stopped"
else
    log "No Docker containers using port 6379"
fi

# Check system processes using port 6379
log "Checking system processes..."
if command -v netstat &> /dev/null; then
    local system_processes=$(netstat -tlnp 2>/dev/null | grep ":6379" || true)
    if [ -n "$system_processes" ]; then
        echo "System processes using port 6379:"
        echo "$system_processes"
        echo ""
        warning "You need to stop these processes manually"
        echo "Example commands:"
        echo "  sudo systemctl stop redis"
        echo "  sudo systemctl stop keydb"
        echo "  sudo pkill -f redis"
        echo "  sudo pkill -f keydb"
    else
        log "No system processes using port 6379"
    fi
elif command -v ss &> /dev/null; then
    local system_processes=$(ss -tlnp | grep ":6379" || true)
    if [ -n "$system_processes" ]; then
        echo "System processes using port 6379:"
        echo "$system_processes"
        echo ""
        warning "You need to stop these processes manually"
    else
        log "No system processes using port 6379"
    fi
else
    warning "netstat and ss not available, cannot check system processes"
fi

# Final check
log "Final port 6379 check..."
if command -v netstat &> /dev/null; then
    local final_check=$(netstat -tln 2>/dev/null | grep ":6379" || true)
elif command -v ss &> /dev/null; then
    local final_check=$(ss -tln | grep ":6379" || true)
else
    local final_check=""
fi

if [ -z "$final_check" ]; then
    success "Port 6379 is now free!"
else
    warning "Port 6379 is still in use:"
    echo "$final_check"
    echo ""
    echo "Try these commands to free the port:"
    echo "  sudo systemctl stop redis keydb"
    echo "  sudo pkill -f 'redis|keydb'"
    echo "  sudo fuser -k 6379/tcp"
fi


