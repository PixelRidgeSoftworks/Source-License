#!/bin/bash
# Bash Deployment Script for Source License Management System
# Handles updates and configuration changes without overwriting customizations

set -e

# Default values
ACTION="update"
DOMAIN=""
PORT=""
ENVIRONMENT=""
FORCE=false
BACKUP_FIRST=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print functions
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${CYAN}ℹ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

# Show help
show_help() {
    cat << EOF
Source License Management System - Unix Deployment Script

USAGE:
    ./deploy.sh [ACTION] [OPTIONS]

ACTIONS:
    update                    Update application code and dependencies
    config                    Update configuration only
    restart                   Restart services
    backup                    Create backup of current installation
    restore                   Restore from backup
    migrate                   Run database migrations only
    status                    Show deployment status

OPTIONS:
    -d, --domain <domain>     Update domain configuration
    -p, --port <port>         Update port configuration
    -e, --environment <env>   Update environment (development/production)
    -f, --force              Force update even if changes detected
    -b, --backup-first       Create backup before deployment
    -h, --help               Show this help message

EXAMPLES:
    ./deploy.sh update --backup-first
    ./deploy.sh config --domain "new-domain.com"
    ./deploy.sh restart
    ./deploy.sh backup
EOF
}

# Parse command line arguments
parse_args() {
    # First argument is the action if it doesn't start with -
    if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
        ACTION="$1"
        shift
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--domain)
                DOMAIN="$2"
                shift 2
                ;;
            -p|--port)
                PORT="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -b|--backup-first)
                BACKUP_FIRST=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        PLATFORM="linux"
        if command -v systemctl >/dev/null 2>&1; then
            SERVICE_MANAGER="systemd"
        else
            SERVICE_MANAGER="manual"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        PLATFORM="macos"
        SERVICE_MANAGER="launchctl"
    else
        print_error "Unsupported operating system: $OSTYPE"
        exit 1
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Create backup
create_backup() {
    local backup_path="${1:-backups/$(date +%Y%m%d-%H%M%S)}"
    
    print_info "Creating backup at $backup_path..."
    
    mkdir -p "$backup_path"
    
    # Backup configuration files
    local config_files=(".env" "config/customizations.yml" "Gemfile.lock")
    for file in "${config_files[@]}"; do
        if [[ -f "$file" ]]; then
            cp "$file" "$backup_path/$(basename "$file")"
            print_info "Backed up $file"
        fi
    done
    
    # Backup database if SQLite
    if [[ -f "database.db" ]]; then
        cp "database.db" "$backup_path/database.db"
        print_info "Backed up database"
    fi
    
    # Backup logs
    if [[ -d "logs" ]]; then
        cp -r "logs" "$backup_path/logs"
        print_info "Backed up logs"
    fi
    
    # Create manifest
    cat > "$backup_path/manifest.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "version": "$(git describe --tags --always 2>/dev/null || echo 'unknown')",
    "environment": "${RACK_ENV:-unknown}",
    "platform": "$PLATFORM",
    "files": [$(printf '"%s",' "${config_files[@]}" | sed 's/,$//')]
}
EOF
    
    print_success "Backup created successfully at $backup_path"
    echo "$backup_path"
}

# Restore from backup
restore_backup() {
    local backup_path="$1"
    
    if [[ ! -d "$backup_path" ]]; then
        print_error "Backup path not found: $backup_path"
        return 1
    fi
    
    print_info "Restoring from backup: $backup_path..."
    
    # Check manifest
    if [[ -f "$backup_path/manifest.json" ]]; then
        local timestamp=$(grep '"timestamp"' "$backup_path/manifest.json" | cut -d'"' -f4)
        local version=$(grep '"version"' "$backup_path/manifest.json" | cut -d'"' -f4)
        print_info "Backup created: $timestamp"
        print_info "Backup version: $version"
    fi
    
    # Stop services before restore
    stop_services
    
    # Restore files
    for file in "$backup_path"/*; do
        if [[ -f "$file" ]] && [[ "$(basename "$file")" != "manifest.json" ]]; then
            cp "$file" "./$(basename "$file")"
            print_info "Restored $(basename "$file")"
        fi
    done
    
    # Restore directories
    for dir in "$backup_path"/*; do
        if [[ -d "$dir" ]]; then
            local dir_name=$(basename "$dir")
            if [[ -d "./$dir_name" ]]; then
                rm -rf "./$dir_name"
            fi
            cp -r "$dir" "./$dir_name"
            print_info "Restored $dir_name/"
        fi
    done
    
    print_success "Backup restored successfully"
}

# Check for uncommitted changes
check_local_changes() {
    if command_exists git; then
        local status
        status=$(git status --porcelain 2>/dev/null)
        [[ -n "$status" ]]
    else
        false
    fi
}

# Stop services
stop_services() {
    print_info "Stopping services..."
    
    case $SERVICE_MANAGER in
        systemd)
            if systemctl is-active --quiet source-license; then
                sudo systemctl stop source-license
                print_success "Stopped source-license service"
            fi
            ;;
        launchctl)
            if launchctl list | grep -q com.sourcelicense.app; then
                sudo launchctl unload /Library/LaunchDaemons/com.sourcelicense.app.plist 2>/dev/null || true
                print_success "Stopped macOS LaunchDaemon"
            fi
            ;;
        *)
            # Kill ruby processes manually
            local pids
            pids=$(ps aux | grep "ruby.*launch.rb" | grep -v grep | awk '{print $2}')
            if [[ -n "$pids" ]]; then
                echo "$pids" | xargs kill
                print_success "Stopped Ruby processes"
            fi
            ;;
    esac
}

# Start services
start_services() {
    print_info "Starting services..."
    
    case $SERVICE_MANAGER in
        systemd)
            sudo systemctl start source-license
            print_success "Started source-license service"
            ;;
        launchctl)
            sudo launchctl load /Library/LaunchDaemons/com.sourcelicense.app.plist
            print_success "Started macOS LaunchDaemon"
            ;;
        *)
            # Start manually in background
            nohup ruby launch.rb > logs/app.log 2>&1 &
            print_success "Started Ruby application"
            ;;
    esac
}

# Update application code
update_application() {
    print_info "Updating application code..."
    
    # Check for local changes
    if check_local_changes && [[ "$FORCE" != true ]]; then
        print_warning "Local changes detected. Use --force to override or commit changes first."
        git status --short
        return 1
    fi
    
    local backup_path=""
    
    # Create backup if requested
    if [[ "$BACKUP_FIRST" == true ]]; then
        backup_path=$(create_backup)
        if [[ -z "$backup_path" ]]; then
            print_error "Backup failed, aborting update"
            return 1
        fi
    fi
    
    # Stop services
    stop_services
    
    # Pull latest changes
    print_info "Pulling latest changes..."
    if command_exists git; then
        git pull origin main
    else
        print_warning "Git not available, skipping code update"
    fi
    
    # Update dependencies
    print_info "Updating dependencies..."
    bundle install
    
    # Run migrations
    print_info "Running database migrations..."
    ruby lib/migrations.rb
    
    # Start services
    start_services
    
    print_success "Application updated successfully"
}

# Update configuration
update_configuration() {
    print_info "Updating configuration..."
    
    # Backup configuration
    if [[ -f ".env" ]]; then
        cp ".env" ".env.backup"
        print_info "Backed up current .env file"
    fi
    
    # Update domain if provided
    if [[ -n "$DOMAIN" ]]; then
        if [[ -f ".env" ]]; then
            sed -i.bak "s/^APP_HOST=.*/APP_HOST=$DOMAIN/" .env
            print_success "Updated APP_HOST to $DOMAIN"
        fi
        
        # Update Nginx config if exists
        local nginx_configs=("/etc/nginx/sites-available/source-license" "/usr/local/etc/nginx/servers/source-license.conf")
        for config in "${nginx_configs[@]}"; do
            if [[ -f "$config" ]]; then
                sudo sed -i.bak "s/server_name .*/server_name $DOMAIN;/" "$config"
                print_success "Updated Nginx server_name to $DOMAIN"
                
                # Restart Nginx
                if [[ "$PLATFORM" == "linux" ]]; then
                    sudo systemctl reload nginx 2>/dev/null || true
                elif [[ "$PLATFORM" == "macos" ]]; then
                    sudo brew services restart nginx 2>/dev/null || true
                fi
                break
            fi
        done
    fi
    
    # Update port if provided
    if [[ -n "$PORT" ]]; then
        if [[ -f ".env" ]]; then
            sed -i.bak "s/^PORT=.*/PORT=$PORT/" .env
            print_success "Updated PORT to $PORT"
        fi
    fi
    
    # Update environment if provided
    if [[ -n "$ENVIRONMENT" ]]; then
        if [[ -f ".env" ]]; then
            sed -i.bak "s/^RACK_ENV=.*/RACK_ENV=$ENVIRONMENT/" .env
            sed -i.bak "s/^APP_ENV=.*/APP_ENV=$ENVIRONMENT/" .env
            print_success "Updated environment to $ENVIRONMENT"
        fi
    fi
    
    print_success "Configuration updated successfully"
}

# Restart services
restart_services() {
    print_info "Restarting services..."
    
    stop_services
    sleep 2
    start_services
    
    # Restart Nginx if running
    if [[ "$PLATFORM" == "linux" ]] && systemctl is-active --quiet nginx; then
        sudo systemctl reload nginx
        print_success "Nginx reloaded"
    elif [[ "$PLATFORM" == "macos" ]] && command_exists brew; then
        sudo brew services restart nginx 2>/dev/null && print_success "Nginx restarted" || true
    fi
    
    print_success "Services restarted successfully"
}

# Run database migrations only
run_migrations() {
    print_info "Running database migrations..."
    
    ruby lib/migrations.rb
    print_success "Database migrations completed"
}

# Show deployment status
show_deployment_status() {
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Source License Management System                          ║
║                         Deployment Status                                    ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Git status
    if command_exists git && [[ -d ".git" ]]; then
        local git_branch
        local git_commit
        git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        git_commit=$(git rev-parse --short HEAD 2>/dev/null)
        
        print_info "Git Branch: $git_branch"
        print_info "Git Commit: $git_commit"
        
        if check_local_changes; then
            print_warning "Uncommitted changes present:"
            git status --short | sed 's/^/  /'
        else
            print_success "Working directory clean"
        fi
    else
        print_warning "Not a git repository"
    fi
    
    # Environment info
    if [[ -f ".env" ]]; then
        local domain
        local port
        local env
        domain=$(grep "^APP_HOST=" .env | cut -d'=' -f2 2>/dev/null || echo "not set")
        port=$(grep "^PORT=" .env | cut -d'=' -f2 2>/dev/null || echo "not set")
        env=$(grep "^RACK_ENV=" .env | cut -d'=' -f2 2>/dev/null || echo "not set")
        
        print_info "Domain: $domain"
        print_info "Port: $port"
        print_info "Environment: $env"
    fi
    
    # Service status
    case $SERVICE_MANAGER in
        systemd)
            if systemctl is-active --quiet source-license; then
                print_success "systemd service is running"
            else
                print_warning "systemd service is not running"
            fi
            ;;
        launchctl)
            if launchctl list | grep -q com.sourcelicense.app; then
                print_success "macOS LaunchDaemon is loaded"
            else
                print_warning "macOS LaunchDaemon is not loaded"
            fi
            ;;
        *)
            local pids
            pids=$(ps aux | grep "ruby.*launch.rb" | grep -v grep | awk '{print $2}')
            if [[ -n "$pids" ]]; then
                print_success "Ruby application is running (PIDs: $pids)"
            else
                print_warning "Ruby application is not running"
            fi
            ;;
    esac
    
    # Recent backups
    if [[ -d "backups" ]]; then
        local recent_backups
        recent_backups=$(ls -1t backups/ 2>/dev/null | head -5)
        if [[ -n "$recent_backups" ]]; then
            print_info "Recent backups:"
            echo "$recent_backups" | sed 's/^/  /'
        fi
    fi
    
    # Customizations status
    if [[ -f "config/customizations.yml" ]]; then
        local customization_size
        customization_size=$(stat -f%z "config/customizations.yml" 2>/dev/null || stat -c%s "config/customizations.yml" 2>/dev/null)
        print_info "Customizations file: $customization_size bytes"
    else
        print_info "No customizations file found"
    fi
}

# List available backups
list_backups() {
    if [[ ! -d "backups" ]]; then
        print_warning "No backups directory found"
        return
    fi
    
    local backups
    backups=$(ls -1t backups/ 2>/dev/null)
    
    if [[ -z "$backups" ]]; then
        print_warning "No backups found"
        return
    fi
    
    print_info "Available backups:"
    for backup in $backups; do
        local manifest_path="backups/$backup/manifest.json"
        if [[ -f "$manifest_path" ]]; then
            local timestamp
            local version
            timestamp=$(grep '"timestamp"' "$manifest_path" | cut -d'"' -f4)
            version=$(grep '"version"' "$manifest_path" | cut -d'"' -f4)
            echo "  $backup - $timestamp ($version)"
        else
            echo "  $backup"
        fi
    done
}

# Main deployment function
main() {
    # Parse arguments
    parse_args "$@"
    
    # Detect OS
    detect_os
    print_info "Detected platform: $PLATFORM"
    print_info "Service manager: $SERVICE_MANAGER"
    
    # Check if we're in the right directory
    if [[ ! -f "app.rb" ]] || [[ ! -f "Gemfile" ]]; then
        print_error "Please run this script from the project root directory"
        exit 1
    fi
    
    case "$ACTION" in
        update)
            update_application
            ;;
        config)
            update_configuration
            ;;
        restart)
            restart_services
            ;;
        backup)
            create_backup >/dev/null
            ;;
        restore)
            list_backups
            echo
            read -p "Enter backup name to restore: " backup_name
            if [[ -n "$backup_name" ]]; then
                restore_backup "backups/$backup_name"
            fi
            ;;
        migrate)
            run_migrations
            ;;
        status)
            show_deployment_status
            ;;
        *)
            print_error "Unknown action: $ACTION"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
