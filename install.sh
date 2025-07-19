#!/bin/bash
# Bash Installation Script for Source License Management System
# Linux and macOS installer

set -e

# Default values
DOMAIN="localhost"
PORT="4567"
ENVIRONMENT="production"
SKIP_RUBY=false
SKIP_NGINX=false
SERVICE_USER=""

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
Source License Management System - Unix Installer

USAGE:
    ./install.sh [OPTIONS]

OPTIONS:
    -d, --domain <domain>     Domain name for the application (default: localhost)
    -p, --port <port>         Port for the application (default: 4567)
    -e, --environment <env>   Environment (development/production, default: production)
    -u, --user <user>         Service user for systemd (auto-detected if not specified)
    --skip-ruby              Skip Ruby installation
    --skip-nginx             Skip Nginx installation
    -h, --help               Show this help message

EXAMPLES:
    ./install.sh
    ./install.sh -d "license.example.com" -p "3000"
    ./install.sh -e "development" --skip-nginx
    ./install.sh -u "nginx" -d "license.company.com"
EOF
}

# Parse command line arguments
parse_args() {
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
            -u|--user)
                SERVICE_USER="$2"
                shift 2
                ;;
            --skip-ruby)
                SKIP_RUBY=true
                shift
                ;;
            --skip-nginx)
                SKIP_NGINX=true
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
        if [ -f /etc/ubuntu-release ] || grep -q "ubuntu" /etc/os-release 2>/dev/null; then
            OS="ubuntu"
            PACKAGE_MANAGER="apt"
        elif [ -f /etc/centos-release ] || grep -q "centos" /etc/os-release 2>/dev/null; then
            OS="centos"
            PACKAGE_MANAGER="yum"
        elif [ -f /etc/fedora-release ] || grep -q "fedora" /etc/os-release 2>/dev/null; then
            OS="fedora"
            PACKAGE_MANAGER="dnf"
        elif [ -f /etc/debian_version ]; then
            OS="debian"
            PACKAGE_MANAGER="apt"
        elif [ -f /etc/redhat-release ]; then
            OS="rhel"
            PACKAGE_MANAGER="yum"
        else
            OS="linux"
            PACKAGE_MANAGER="apt"  # Default to apt
        fi
        PLATFORM="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        PLATFORM="macos"
        PACKAGE_MANAGER="brew"
    else
        print_error "Unsupported operating system: $OSTYPE"
        exit 1
    fi
}

# Detect appropriate service user
detect_service_user() {
    if [[ "$PLATFORM" != "linux" ]]; then
        return 0
    fi
    
    # If user already specified, validate it exists
    if [[ -n "$SERVICE_USER" ]]; then
        if id "$SERVICE_USER" &>/dev/null; then
            print_success "Using specified service user: $SERVICE_USER"
            return 0
        else
            print_error "Specified user '$SERVICE_USER' does not exist"
            exit 1
        fi
    fi
    
    print_info "Detecting appropriate service user for your system..."
    
    # Common web server users by distribution
    local possible_users=()
    
    case $OS in
        ubuntu|debian)
            possible_users=("www-data" "nginx" "apache")
            ;;
        centos|rhel|fedora)
            possible_users=("nginx" "apache" "www-data")
            ;;
        *)
            possible_users=("www-data" "nginx" "apache")
            ;;
    esac
    
    # Check which users exist
    local existing_users=()
    for user in "${possible_users[@]}"; do
        if id "$user" &>/dev/null; then
            existing_users+=("$user")
        fi
    done
    
    # If we found existing web server users, let user choose
    if [[ ${#existing_users[@]} -gt 0 ]]; then
        echo
        print_info "Found the following web server users on your system:"
        for i in "${!existing_users[@]}"; do
            echo "  $((i+1)). ${existing_users[i]}"
        done
        echo "  $((${#existing_users[@]}+1)). Create new user 'sourcelicense'"
        echo "  $((${#existing_users[@]}+2)). Run as current user ($(whoami))"
        echo
        
        while true; do
            read -p "Please select a user to run the Source License service (1-$((${#existing_users[@]}+2))): " choice
            
            if [[ "$choice" =~ ^[0-9]+$ ]]; then
                if [[ $choice -ge 1 && $choice -le ${#existing_users[@]} ]]; then
                    SERVICE_USER="${existing_users[$((choice-1))]}"
                    print_success "Selected service user: $SERVICE_USER"
                    break
                elif [[ $choice -eq $((${#existing_users[@]}+1)) ]]; then
                    SERVICE_USER="sourcelicense"
                    create_service_user
                    break
                elif [[ $choice -eq $((${#existing_users[@]}+2)) ]]; then
                    SERVICE_USER="$(whoami)"
                    print_warning "Running as current user: $SERVICE_USER"
                    print_warning "This is not recommended for production deployments"
                    break
                fi
            fi
            
            print_error "Invalid selection. Please choose a number between 1 and $((${#existing_users[@]}+2))"
        done
    else
        # No existing web server users found, create one
        print_warning "No existing web server users found"
        echo
        print_info "Options:"
        echo "  1. Create new user 'sourcelicense'"
        echo "  2. Run as current user ($(whoami))"
        echo
        
        while true; do
            read -p "Please select an option (1-2): " choice
            case $choice in
                1)
                    SERVICE_USER="sourcelicense"
                    create_service_user
                    break
                    ;;
                2)
                    SERVICE_USER="$(whoami)"
                    print_warning "Running as current user: $SERVICE_USER"
                    print_warning "This is not recommended for production deployments"
                    break
                    ;;
                *)
                    print_error "Invalid selection. Please choose 1 or 2"
                    ;;
            esac
        done
    fi
    
    # Ensure the user can access the application directory
    setup_user_permissions
}

# Create service user
create_service_user() {
    print_info "Creating service user: $SERVICE_USER..."
    
    # Create user with no login shell and home directory
    if sudo useradd --system --shell /bin/false --home-dir /var/lib/sourcelicense --create-home "$SERVICE_USER" 2>/dev/null; then
        print_success "Created service user: $SERVICE_USER"
    else
        print_warning "User $SERVICE_USER may already exist or creation failed"
    fi
    
    # Create group if it doesn't exist
    if ! getent group "$SERVICE_USER" >/dev/null; then
        sudo groupadd "$SERVICE_USER" 2>/dev/null || true
        sudo usermod -g "$SERVICE_USER" "$SERVICE_USER" 2>/dev/null || true
    fi
}

# Setup user permissions
setup_user_permissions() {
    local current_dir=$(pwd)
    
    print_info "Setting up permissions for user: $SERVICE_USER..."
    
    # Ensure the service user can read the application directory
    sudo chown -R "$SERVICE_USER:$SERVICE_USER" "$current_dir" 2>/dev/null || {
        print_warning "Could not change ownership to $SERVICE_USER"
        print_info "Ensuring read permissions for $SERVICE_USER..."
        sudo chmod -R o+r "$current_dir"
        sudo find "$current_dir" -type d -exec chmod o+x {} \;
    }
    
    # Ensure logs directory is writable
    if [[ ! -d "logs" ]]; then
        mkdir -p logs
    fi
    sudo chown "$SERVICE_USER:$SERVICE_USER" logs 2>/dev/null || {
        sudo chmod 777 logs
        print_warning "Could not set ownership for logs directory, set to world-writable"
    }
    
    # Ensure database file is writable if it exists
    if [[ -f "database.db" ]]; then
        sudo chown "$SERVICE_USER:$SERVICE_USER" database.db 2>/dev/null || {
            sudo chmod 666 database.db
            print_warning "Could not set ownership for database file, set to world-writable"
        }
    fi
    
    print_success "Permissions configured for $SERVICE_USER"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]] && [[ "$ENVIRONMENT" == "production" ]]; then
        print_warning "Running as root. This is required for production installation."
    elif [[ $EUID -ne 0 ]] && [[ "$ENVIRONMENT" == "production" ]]; then
        print_error "Root privileges required for production installation. Use sudo."
        exit 1
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install package
install_package() {
    local package_name="$1"
    local apt_name="${2:-$package_name}"
    local yum_name="${3:-$package_name}"
    local brew_name="${4:-$package_name}"
    
    print_info "Installing $package_name..."
    
    case $PACKAGE_MANAGER in
        apt)
            sudo apt update >/dev/null 2>&1
            sudo apt install -y $apt_name
            ;;
        yum)
            sudo yum install -y $yum_name
            ;;
        dnf)
            sudo dnf install -y $yum_name
            ;;
        brew)
            brew install $brew_name
            ;;
        *)
            print_error "Unsupported package manager: $PACKAGE_MANAGER"
            return 1
            ;;
    esac
    
    print_success "$package_name installed successfully"
}

# Install Homebrew on macOS
install_homebrew() {
    if [[ "$PLATFORM" != "macos" ]]; then
        return 0
    fi
    
    if command_exists brew; then
        print_success "Homebrew already installed"
        return 0
    fi
    
    print_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    print_success "Homebrew installed successfully"
}

# Install Ruby
install_ruby() {
    if [[ "$SKIP_RUBY" == true ]]; then
        print_warning "Skipping Ruby installation"
        return 0
    fi
    
    print_info "Checking Ruby installation..."
    
    if command_exists ruby; then
        local ruby_version=$(ruby --version)
        print_success "Ruby already installed: $ruby_version"
        return 0
    fi
    
    print_info "Installing Ruby..."
    
    case $PACKAGE_MANAGER in
        apt)
            install_package "Ruby" "ruby-full ruby-dev build-essential"
            ;;
        yum|dnf)
            install_package "Ruby" "" "ruby ruby-devel gcc gcc-c++ make"
            ;;
        brew)
            install_package "Ruby" "" "" "ruby"
            ;;
    esac
}

# Install Bundler
install_bundler() {
    print_info "Installing Bundler..."
    if gem install bundler; then
        print_success "Bundler installed successfully"
        return 0
    else
        print_error "Failed to install Bundler"
        return 1
    fi
}

# Install dependencies
install_dependencies() {
    print_info "Installing Ruby dependencies..."
    if bundle install; then
        print_success "Dependencies installed successfully"
        return 0
    else
        print_error "Failed to install dependencies"
        return 1
    fi
}

# Setup database
setup_database() {
    print_info "Setting up database..."
    if ruby lib/migrations.rb; then
        print_success "Database setup completed"
        return 0
    else
        print_error "Failed to setup database"
        return 1
    fi
}

# Install Nginx
install_nginx() {
    if [[ "$SKIP_NGINX" == true ]]; then
        print_warning "Skipping Nginx installation"
        return 0
    fi
    
    print_info "Installing Nginx..."
    
    if command_exists nginx; then
        print_success "Nginx already installed"
        return 0
    fi
    
    install_package "Nginx" "nginx" "nginx" "nginx"
}

# Create Nginx configuration
create_nginx_config() {
    if [[ "$SKIP_NGINX" == true ]]; then
        return 0
    fi
    
    print_info "Creating Nginx configuration..."
    
    local config_path=""
    
    if [[ "$PLATFORM" == "linux" ]]; then
        config_path="/etc/nginx/sites-available/source-license"
        local enabled_path="/etc/nginx/sites-enabled/source-license"
    else
        config_path="/usr/local/etc/nginx/servers/source-license.conf"
    fi
    
    local nginx_config="upstream source_license {
    server 127.0.0.1:$PORT fail_timeout=0;
}

server {
    listen 80;
    server_name $DOMAIN;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection \"1; mode=block\";
    add_header Referrer-Policy strict-origin-when-cross-origin;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
    
    # Static files
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)\$ {
        expires 1y;
        add_header Cache-Control \"public, immutable\";
        try_files \$uri @source_license;
    }
    
    # Main application
    location / {
        proxy_pass http://source_license;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        
        # Increase timeout for long-running requests
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        proxy_pass http://source_license;
    }
}"
    
    # Create configuration file
    if [[ "$PLATFORM" == "linux" ]]; then
        sudo mkdir -p /etc/nginx/sites-available
        echo "$nginx_config" | sudo tee "$config_path" > /dev/null
        
        # Enable site on Ubuntu/Debian
        if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
            sudo mkdir -p /etc/nginx/sites-enabled
            sudo ln -sf "$config_path" "$enabled_path"
        fi
    else
        sudo mkdir -p /usr/local/etc/nginx/servers
        echo "$nginx_config" | sudo tee "$config_path" > /dev/null
    fi
    
    print_success "Nginx configuration created at $config_path"
}

# Create systemd service (Linux)
create_systemd_service() {
    if [[ "$PLATFORM" != "linux" ]] || [[ "$ENVIRONMENT" != "production" ]]; then
        return 0
    fi
    
    print_info "Creating systemd service..."
    
    local current_dir=$(pwd)
    local service_config="[Unit]
Description=Source License Management System
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$current_dir
ExecStart=/usr/bin/env ruby launch.rb
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
    
    echo "$service_config" | sudo tee /etc/systemd/system/source-license.service > /dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable source-license
    
    print_success "Systemd service created and enabled for user: $SERVICE_USER"
}

# Create macOS LaunchDaemon
create_macos_service() {
    if [[ "$PLATFORM" != "macos" ]] || [[ "$ENVIRONMENT" != "production" ]]; then
        return 0
    fi
    
    print_info "Creating macOS LaunchDaemon..."
    
    local current_dir=$(pwd)
    local plist_config="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>com.sourcelicense.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/env</string>
        <string>ruby</string>
        <string>launch.rb</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$current_dir</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>RACK_ENV</key>
        <string>$ENVIRONMENT</string>
        <key>APP_ENV</key>
        <string>$ENVIRONMENT</string>
        <key>PORT</key>
        <string>$PORT</string>
    </dict>
</dict>
</plist>"
    
    local plist_path="/Library/LaunchDaemons/com.sourcelicense.app.plist"
    echo "$plist_config" | sudo tee "$plist_path" > /dev/null
    sudo launchctl load "$plist_path"
    
    print_success "macOS LaunchDaemon created and loaded"
}

# Create environment file
create_environment_file() {
    print_info "Creating environment configuration..."
    
    if [[ ! -f ".env" ]]; then
        cp ".env.example" ".env"
        print_success "Created .env file from template"
    else
        print_info ".env file already exists"
    fi
    
    # Update domain in .env if not localhost
    if [[ "$DOMAIN" != "localhost" ]]; then
        sed -i.bak "s/^APP_HOST=.*/APP_HOST=$DOMAIN/" .env
        print_success "Updated APP_HOST in .env file"
    fi
}

# Configure firewall
configure_firewall() {
    if [[ "$ENVIRONMENT" != "production" ]]; then
        return 0
    fi
    
    print_info "Configuring firewall..."
    
    if [[ "$PLATFORM" == "linux" ]]; then
        # Configure UFW if available
        if command_exists ufw; then
            sudo ufw allow $PORT/tcp comment "Source License App"
            if [[ "$SKIP_NGINX" != true ]]; then
                sudo ufw allow 80/tcp comment "Source License Nginx"
                sudo ufw allow 443/tcp comment "Source License Nginx HTTPS"
            fi
            print_success "UFW firewall rules configured"
        # Configure firewalld if available
        elif command_exists firewall-cmd; then
            sudo firewall-cmd --permanent --add-port=$PORT/tcp
            if [[ "$SKIP_NGINX" != true ]]; then
                sudo firewall-cmd --permanent --add-service=http
                sudo firewall-cmd --permanent --add-service=https
            fi
            sudo firewall-cmd --reload
            print_success "firewalld rules configured"
        else
            print_warning "No supported firewall found (ufw/firewalld)"
        fi
    elif [[ "$PLATFORM" == "macos" ]]; then
        print_info "macOS firewall configuration may be needed manually"
    fi
}

# Start services
start_services() {
    if [[ "$ENVIRONMENT" != "production" ]]; then
        return 0
    fi
    
    print_info "Starting services..."
    
    # Start Nginx
    if [[ "$SKIP_NGINX" != true ]]; then
        if [[ "$PLATFORM" == "linux" ]]; then
            sudo systemctl start nginx
            sudo systemctl enable nginx
            print_success "Nginx started and enabled"
        elif [[ "$PLATFORM" == "macos" ]]; then
            if command_exists brew; then
                sudo brew services start nginx
                print_success "Nginx started"
            fi
        fi
    fi
    
    # Start application service
    if [[ "$PLATFORM" == "linux" ]]; then
        sudo systemctl start source-license
        print_success "Source License service started"
    elif [[ "$PLATFORM" == "macos" ]]; then
        print_success "Source License service loaded (will start automatically)"
    fi
}

# Run tests
run_tests() {
    print_info "Running tests to verify installation..."
    if ruby run_tests.rb; then
        return 0
    else
        print_error "Tests failed"
        return 1
    fi
}

# Main installation function
main() {
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Source License Management System                          ║
║                         Unix Installation Script                             ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Parse arguments
    parse_args "$@"
    
    # Detect OS
    detect_os
    print_info "Detected OS: $OS ($PLATFORM)"
    
    # Check root privileges
    check_root
    
    # Check if we're in the right directory
    if [[ ! -f "app.rb" ]] || [[ ! -f "Gemfile" ]]; then
        print_error "Please run this script from the project root directory"
        exit 1
    fi
    
    local success=true
    
    # Install package manager on macOS
    if [[ "$PLATFORM" == "macos" ]]; then
        install_homebrew || success=false
    fi
    
    # Install Ruby
    if [[ "$SKIP_RUBY" != true ]]; then
        install_ruby || success=false
        install_bundler || success=false
    fi
    
    # Install dependencies
    install_dependencies || success=false
    
    # Setup database
    setup_database || success=false
    
    # Install and configure Nginx
    if [[ "$SKIP_NGINX" != true ]]; then
        install_nginx || success=false
        create_nginx_config || success=false
    fi
    
    # Create environment file
    create_environment_file
    
    # Detect and configure service user (Linux only)
    if [[ "$PLATFORM" == "linux" ]] && [[ "$ENVIRONMENT" == "production" ]]; then
        detect_service_user
    fi
    
    # Configure firewall
    configure_firewall
    
    # Create services for production
    if [[ "$ENVIRONMENT" == "production" ]]; then
        if [[ "$PLATFORM" == "linux" ]]; then
            create_systemd_service || success=false
        elif [[ "$PLATFORM" == "macos" ]]; then
            create_macos_service || success=false
        fi
        
        # Start services
        start_services
    fi
    
    # Run tests
    print_info "Running verification tests..."
    local tests_success=true
    run_tests || tests_success=false
    
    # Final status
    echo -e "${CYAN}$(printf '=%.0s' {1..80})${NC}"
    
    if [[ "$success" == true ]] && [[ "$tests_success" == true ]]; then
        print_success "Installation completed successfully!"
        echo
        echo -e "${GREEN}🎉 Source License Management System is now installed and running on $PLATFORM!${NC}"
        echo
        echo "Access your application:"
        if [[ "$PORT" == "80" ]]; then
            echo "  URL: http://$DOMAIN"
            echo "  Admin: http://$DOMAIN/admin"
        else
            echo "  URL: http://$DOMAIN:$PORT"
            echo "  Admin: http://$DOMAIN:$PORT/admin"
        fi
        echo
        if [[ "$PLATFORM" == "linux" ]] && [[ -n "$SERVICE_USER" ]]; then
            echo "Service configuration:"
            echo "  Service user: $SERVICE_USER"
            echo "  Service name: source-license"
        fi
        echo
        echo "Next steps:"
        echo "  1. Edit .env file with your configuration"
        echo "  2. Setup payment gateways (Stripe/PayPal)"
        echo "  3. Configure SMTP for email delivery"
        echo "  4. Add your products via the admin interface"
        echo "  5. Setup SSL certificate for production use"
        echo
        echo "Service management:"
        if [[ "$PLATFORM" == "linux" ]]; then
            echo "  Start:   sudo systemctl start source-license"
            echo "  Stop:    sudo systemctl stop source-license"
            echo "  Status:  sudo systemctl status source-license"
            echo "  Logs:    sudo journalctl -u source-license -f"
        elif [[ "$PLATFORM" == "macos" ]]; then
            echo "  Start:   sudo launchctl load /Library/LaunchDaemons/com.sourcelicense.app.plist"
            echo "  Stop:    sudo launchctl unload /Library/LaunchDaemons/com.sourcelicense.app.plist"
            echo "  Logs:    tail -f /var/log/system.log | grep sourcelicense"
        fi
        echo
        echo "Development mode:"
        echo "  Start:   ruby launch.rb"
        echo "  Monitor: ./service_manager.ps1 monitor (if PowerShell available)"
    else
        print_error "Installation failed! Please check the error messages above."
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
