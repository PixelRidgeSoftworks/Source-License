#!/bin/bash
# Source-License Unified Deploy Script
# Simplified deployment script for Unix systems (Linux/macOS)

set -e

# Default values
ACTION="help"
ENVIRONMENT="production"
PORT="4567"
BACKUP_FIRST=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
Source-License Deploy Script for Unix Systems

USAGE:
    ./deploy [ACTION] [OPTIONS]

ACTIONS:
    run                      Start the application
    stop                     Stop the application
    restart                  Restart the application
    status                   Show application status
    update                   Update code and restart
    migrate                  Run database migrations only
    install-service          Create systemd service (requires sudo)
    remove-service           Remove systemd service (requires sudo)

OPTIONS:
    -e, --environment ENV    Environment (development/production, default: production)
    -p, --port PORT          Port for the application (default: 4567)
    -b, --backup             Create backup before update
    -h, --help               Show this help message

EXAMPLES:
    ./deploy run
    ./deploy stop
    ./deploy update --backup
    ./deploy run --environment development --port 3000
    sudo ./deploy install-service
    sudo ./deploy remove-service

SYSTEMD USAGE:
    sudo systemctl start source-license     # Start service
    sudo systemctl stop source-license      # Stop service
    sudo systemctl status source-license    # Show status
    sudo journalctl -u source-license -f    # Follow logs
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
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -p|--port)
                PORT="$2"
                shift 2
                ;;
            -b|--backup)
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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if systemd is available
has_systemd() {
    command_exists systemctl && [[ -d /etc/systemd/system ]]
}

# Check if port is in use
port_in_use() {
    local port="$1"
    if command_exists ss; then
        ss -tuln | grep -q ":$port "
    elif command_exists netstat; then
        netstat -tuln | grep -q ":$port "
    elif command_exists lsof; then
        lsof -i ":$port" >/dev/null 2>&1
    else
        # Fallback: try to connect to the port
        timeout 1 bash -c "cat < /dev/null > /dev/tcp/localhost/$port" 2>/dev/null
    fi
}

# Get application process
get_app_process() {
    ps aux | grep "ruby.*launch\.rb" | grep -v grep | awk '{print $2}' | head -1
}

# Check if running as root/sudo
is_root() {
    [[ $EUID -eq 0 ]]
}

# Create systemd service file
create_systemd_service() {
    local current_dir=$(pwd)
    local service_name="source-license"
    local service_file="/etc/systemd/system/$service_name.service"
    
    print_info "Creating systemd service..."
    
    # Determine user for service
    local service_user="$USER"
    if [[ "$service_user" == "root" ]]; then
        # Look for a non-root user to run the service
        if id "www-data" &>/dev/null; then
            service_user="www-data"
        elif id "nobody" &>/dev/null; then
            service_user="nobody"
        else
            print_warning "Running service as root is not recommended"
            service_user="root"
        fi
    fi
    
    local service_content="[Unit]
Description=Source-License Management System
After=network.target

[Service]
Type=simple
User=$service_user
WorkingDirectory=$current_dir
ExecStart=/usr/bin/env ruby $current_dir/launch.rb
Restart=always
RestartSec=5
Environment=RACK_ENV=$ENVIRONMENT
Environment=APP_ENV=$ENVIRONMENT
Environment=PORT=$PORT

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=$current_dir

[Install]
WantedBy=multi-user.target"
    
    if ! is_root; then
        print_warning "Root privileges required to create systemd service"
        print_info "Run with sudo to enable systemd service management"
        return 1
    fi
    
    echo "$service_content" | sudo tee "$service_file" > /dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable "$service_name"
    
    # Set permissions for service user
    if [[ "$service_user" != "root" ]] && [[ "$service_user" != "$USER" ]]; then
        sudo chown -R "$service_user:$service_user" "$current_dir" 2>/dev/null || {
            print_warning "Could not change ownership to $service_user"
            print_info "Service may have permission issues"
        }
    fi
    
    print_success "Systemd service created and enabled"
    print_info "Service name: $service_name"
    print_info "Service user: $service_user"
    return 0
}

# Remove systemd service
remove_systemd_service() {
    local service_name="source-license"
    local service_file="/etc/systemd/system/$service_name.service"
    
    if [[ -f "$service_file" ]]; then
        if ! is_root; then
            print_warning "Root privileges required to remove systemd service"
            return 1
        fi
        
        print_info "Removing systemd service..."
        sudo systemctl stop "$service_name" 2>/dev/null || true
        sudo systemctl disable "$service_name" 2>/dev/null || true
        sudo rm -f "$service_file"
        sudo systemctl daemon-reload
        print_success "Systemd service removed"
    fi
}

# Start via systemd or fallback
start_with_systemd() {
    local service_name="source-license"
    
    if has_systemd && systemctl list-unit-files | grep -q "$service_name.service"; then
        print_info "Starting via systemd..."
        if is_root; then
            systemctl start "$service_name"
        else
            sudo systemctl start "$service_name"
        fi
        
        # Wait a moment for startup
        sleep 3
        
        if systemctl is-active --quiet "$service_name"; then
            print_success "Service started successfully via systemd"
            print_info "Status: sudo systemctl status $service_name"
            print_info "Logs: sudo journalctl -u $service_name -f"
            return 0
        else
            print_error "Service failed to start via systemd"
            print_info "Check logs: sudo journalctl -u $service_name"
            return 1
        fi
    else
        return 1  # Fall back to manual start
    fi
}

# Stop via systemd or fallback
stop_with_systemd() {
    local service_name="source-license"
    
    if has_systemd && systemctl list-unit-files | grep -q "$service_name.service"; then
        print_info "Stopping via systemd..."
        if is_root; then
            systemctl stop "$service_name"
        else
            sudo systemctl stop "$service_name"
        fi
        print_success "Service stopped via systemd"
        return 0
    else
        return 1  # Fall back to manual stop
    fi
}

# Get systemd service status
get_systemd_status() {
    local service_name="source-license"
    
    if has_systemd && systemctl list-unit-files | grep -q "$service_name.service"; then
        if systemctl is-active --quiet "$service_name"; then
            print_success "Systemd service is running"
            print_info "Service: $service_name"
            
            # Show service info
            local status_output=$(systemctl status "$service_name" --no-pager -l 2>/dev/null)
            if [[ $? -eq 0 ]]; then
                echo "$status_output" | head -10
            fi
            return 0
        else
            print_warning "Systemd service is not running"
            return 1
        fi
    else
        return 1  # No systemd service available
    fi
}

# Health check
health_check() {
    local port="$1"
    if command_exists curl; then
        curl -s -f "http://localhost:$port/health" >/dev/null 2>&1 || \
        curl -s -f "http://localhost:$port/" >/dev/null 2>&1
    elif command_exists wget; then
        wget -q -O /dev/null "http://localhost:$port/health" 2>/dev/null || \
        wget -q -O /dev/null "http://localhost:$port/" 2>/dev/null
    else
        # Fallback: just check if port is responding
        port_in_use "$port"
    fi
}

# Start application
start_app() {
    print_info "Starting Source-License application..."
    
    if port_in_use "$PORT"; then
        print_warning "Port $PORT is already in use"
        if health_check "$PORT"; then
            print_success "Application appears to be already running"
            return 0
        else
            print_warning "Port is in use but health check failed"
        fi
    fi
    
    # Export environment variables
    export RACK_ENV="$ENVIRONMENT"
    export APP_ENV="$ENVIRONMENT"
    export PORT="$PORT"
    
    # Create logs directory if it doesn't exist
    mkdir -p logs
    
    print_info "Environment: $ENVIRONMENT"
    print_info "Port: $PORT"
    
    # For production, try systemd first, then fallback
    if [[ "$ENVIRONMENT" == "production" ]]; then
        if start_with_systemd; then
            return 0
        fi
        
        print_info "Systemd not available, using manual start..."
        print_info "Starting in production mode (background)..."
        nohup ruby launch.rb > logs/app.log 2>&1 &
        
        # Give it a moment to start
        sleep 3
        
        if health_check "$PORT"; then
            print_success "Application started successfully"
            print_info "PID: $(get_app_process)"
            print_info "Access: http://localhost:$PORT"
            print_info "Admin: http://localhost:$PORT/admin"
            print_info "Logs: tail -f logs/app.log"
        else
            print_error "Application failed to start"
            print_info "Check logs: tail logs/app.log"
            return 1
        fi
    else
        # Development mode always runs in foreground
        print_info "Starting in development mode (foreground)..."
        exec ruby launch.rb
    fi
}

# Stop application
stop_app() {
    print_info "Stopping Source-License application..."
    
    # Try systemd first, then fallback
    if stop_with_systemd; then
        return 0
    fi
    
    # Manual stop
    local pid=$(get_app_process)
    if [[ -n "$pid" ]]; then
        kill "$pid"
        
        # Wait for graceful shutdown
        local count=0
        while [[ $count -lt 10 ]] && kill -0 "$pid" 2>/dev/null; do
            sleep 1
            ((count++))
        done
        
        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            print_warning "Forcing shutdown..."
            kill -9 "$pid"
        fi
        
        print_success "Application stopped"
    else
        print_warning "No running application found"
    fi
}

# Restart application
restart_app() {
    print_info "Restarting Source-License application..."
    
    # Try systemd restart first
    local service_name="source-license"
    if has_systemd && systemctl list-unit-files | grep -q "$service_name.service"; then
        print_info "Restarting via systemd..."
        if is_root; then
            systemctl restart "$service_name"
        else
            sudo systemctl restart "$service_name"
        fi
        
        sleep 3
        if systemctl is-active --quiet "$service_name"; then
            print_success "Service restarted successfully via systemd"
            return 0
        fi
    fi
    
    # Fallback to manual restart
    stop_app
    sleep 2
    start_app
}

# Show status
show_status() {
    print_info "Source-License Application Status"
    echo "=================================="
    
    # Check systemd status first
    if get_systemd_status; then
        echo
        print_info "Access URLs:"
        print_info "  Main: http://localhost:$PORT"
        print_info "  Admin: http://localhost:$PORT/admin"
        return 0
    fi
    
    # Fallback to manual process check
    local pid=$(get_app_process)
    if [[ -n "$pid" ]]; then
        print_success "Application is running (PID: $pid)"
        
        if health_check "$PORT"; then
            print_success "Health check passed"
        else
            print_warning "Health check failed"
        fi
        
        print_info "Port: $PORT"
        print_info "URLs:"
        print_info "  Main: http://localhost:$PORT"
        print_info "  Admin: http://localhost:$PORT/admin"
        
        # Show memory usage if possible
        if command_exists ps; then
            local mem=$(ps -o rss= -p "$pid" 2>/dev/null)
            if [[ -n "$mem" ]]; then
                print_info "Memory: $((mem / 1024)) MB"
            fi
        fi
    else
        print_error "Application is not running"
    fi
    
    # Show systemd service info if available
    local service_name="source-license"
    if has_systemd; then
        if systemctl list-unit-files | grep -q "$service_name.service"; then
            echo
            print_info "Systemd service is available"
            print_info "  Service file: /etc/systemd/system/$service_name.service"
        else
            echo
            print_warning "Systemd service not installed"
            print_info "Run 'sudo ./deploy install-service' to create systemd service"
        fi
    fi
    
    # Show recent logs
    if [[ -f "logs/app.log" ]]; then
        echo
        print_info "Recent log entries:"
        tail -5 logs/app.log 2>/dev/null || print_warning "Could not read log file"
    fi
}

# Update application
update_app() {
    print_info "Updating Source-License application..."
    
    # Create backup if requested
    if [[ "$BACKUP_FIRST" == true ]]; then
        local backup_dir="backups/$(date +%Y%m%d-%H%M%S)"
        print_info "Creating backup at $backup_dir..."
        mkdir -p "$backup_dir"
        
        # Backup important files
        local files=(".env" "Gemfile.lock")
        for file in "${files[@]}"; do
            if [[ -f "$file" ]]; then
                cp "$file" "$backup_dir/"
            fi
        done
        
        # Backup database if SQLite
        if [[ -f "database.db" ]]; then
            cp "database.db" "$backup_dir/"
        fi
        
        print_success "Backup created"
    fi
    
    # Stop application
    stop_app
    
    # Pull latest changes
    if command_exists git && [[ -d ".git" ]]; then
        print_info "Pulling latest changes..."
        git pull origin main || print_warning "Git pull failed, continuing anyway"
    fi
    
    # Update dependencies
    print_info "Updating dependencies..."
    bundle install
    
    # Run migrations
    print_info "Running database migrations..."
    ruby lib/migrations.rb || print_warning "Database migration failed, continuing anyway"
    
    # Start application
    start_app
    
    print_success "Update completed"
}

# Run database migrations
run_migrations() {
    print_info "Running database migrations..."
    
    if ruby lib/migrations.rb; then
        print_success "Database migrations completed"
    else
        print_error "Database migration failed"
        return 1
    fi
}

# Preflight checks
preflight_checks() {
    # Check if we're in the right directory
    if [[ ! -f "app.rb" ]] || [[ ! -f "Gemfile" ]] || [[ ! -f "launch.rb" ]]; then
        print_error "Please run this script from the Source-License project root directory"
        exit 1
    fi
    
    # Check Ruby
    if ! command_exists ruby; then
        print_error "Ruby is not installed. Run ./install first"
        exit 1
    fi
    
    # Check Bundler
    if ! command_exists bundle; then
        print_error "Bundler is not installed. Run ./install first"
        exit 1
    fi
    
    # Check if gems are installed
    if ! bundle check >/dev/null 2>&1; then
        print_warning "Dependencies not installed. Running bundle install..."
        bundle install
    fi
}

# Main function
main() {
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Source-License Deploy Script                              ║
║                         Unix Systems                                         ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Parse arguments
    parse_args "$@"
    
    # Run preflight checks
    preflight_checks
    
    # Execute action
    case "$ACTION" in
        run|start)
            start_app
            ;;
        stop)
            stop_app
            ;;
        restart)
            restart_app
            ;;
        status)
            show_status
            ;;
        update)
            update_app
            ;;
        migrate)
            run_migrations
            ;;
        install-service)
            create_systemd_service
            ;;
        remove-service)
            remove_systemd_service
            ;;
        help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown action: $ACTION"
            show_help
            exit 1
            ;;
    esac
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${YELLOW}Shutting down gracefully...${NC}"; stop_app; exit 0' INT TERM

# Run main function with all arguments
main "$@"
