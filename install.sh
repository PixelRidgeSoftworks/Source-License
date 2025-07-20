#!/bin/bash
# Source-License Unified Installer
# Simplified installer for Unix systems (Linux/macOS)

set -e

# Default values
RUBY_MIN_VERSION="3.4.4"
SKIP_RUBY_CHECK=false
SKIP_BUNDLER_CHECK=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging setup
INSTALLER_LOG_DIR="./installer-logs"
INSTALLER_LOG_FILE="$INSTALLER_LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"

# Ensure log directory exists
mkdir -p "$INSTALLER_LOG_DIR"

# Initialize log file with session header
{
    echo "=========================================="
    echo "Source-License Installer Script Log"
    echo "=========================================="
    echo "Started: $(date)"
    echo "Ruby Min Version: $RUBY_MIN_VERSION"
    echo "Skip Ruby Check: $SKIP_RUBY_CHECK"
    echo "Skip Bundler Check: $SKIP_BUNDLER_CHECK"
    echo "User: $(whoami)"
    echo "Working Directory: $(pwd)"
    echo "System: $(uname -a)"
    echo "=========================================="
    echo ""
} > "$INSTALLER_LOG_FILE"

# Enhanced logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$INSTALLER_LOG_FILE"
}

# Log function calls
log_function_call() {
    local function_name="$1"
    local status="${2:-START}"
    log_message "FUNCTION" "$function_name - $status"
}

# Log command execution
log_command() {
    local command="$1"
    local status="${2:-EXECUTE}"
    log_message "COMMAND" "$command - $status"
}

# Log errors with stack trace
log_error() {
    local error_message="$1"
    local line_number="${2:-unknown}"
    log_message "ERROR" "$error_message (Line: $line_number)"
    # Also log current function stack if available
    if command -v caller >/dev/null 2>&1; then
        local i=0
        while caller $i >> "$INSTALLER_LOG_FILE" 2>/dev/null; do
            ((i++))
        done
    fi
}

# Print functions
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${CYAN}ℹ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

# Show help
show_help() {
    cat << EOF
Source-License Installer for Unix Systems

USAGE:
    ./install [OPTIONS]

OPTIONS:
    --skip-ruby              Skip Ruby version check
    --skip-bundler           Skip Bundler installation check
    -h, --help               Show this help message

EXAMPLES:
    ./install
    ./install --skip-ruby
EOF
}

# Parse command line arguments
parse_args() {
    log_function_call "parse_args" "START"
    log_message "INFO" "Parsing command line arguments: $*"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-ruby)
                SKIP_RUBY_CHECK=true
                log_message "INFO" "Skip Ruby check enabled"
                shift
                ;;
            --skip-bundler)
                SKIP_BUNDLER_CHECK=true
                log_message "INFO" "Skip Bundler check enabled"
                shift
                ;;
            -h|--help)
                log_message "INFO" "Help requested, showing help and exiting"
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log_function_call "parse_args" "COMPLETE"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check Ruby version
check_ruby_version() {
    log_function_call "check_ruby_version" "START"
    
    if [[ "$SKIP_RUBY_CHECK" == true ]]; then
        log_message "WARNING" "Skipping Ruby version check as requested"
        print_warning "Skipping Ruby version check"
        log_function_call "check_ruby_version" "COMPLETE - SKIPPED"
        return 0
    fi

    log_message "INFO" "Checking Ruby version against minimum: $RUBY_MIN_VERSION"
    print_info "Checking Ruby version..."
    
    log_command "command -v ruby"
    if ! command_exists ruby; then
        log_error "Ruby is not installed"
        print_error "Ruby is not installed"
        print_info "Please install Ruby $RUBY_MIN_VERSION or higher:"
        print_info "  - Ubuntu/Debian: sudo apt install ruby-full"
        print_info "  - CentOS/RHEL: sudo yum install ruby"
        print_info "  - macOS: brew install ruby"
        print_info "  - Or use rbenv/rvm for version management"
        log_function_call "check_ruby_version" "FAILED - NOT_INSTALLED"
        return 1
    fi

    log_command "ruby -v"
    local ruby_version=$(ruby -v | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
    log_message "INFO" "Found Ruby version: $ruby_version"
    
    if [[ "$(printf '%s\n' "$RUBY_MIN_VERSION" "$ruby_version" | sort -V | head -n1)" != "$RUBY_MIN_VERSION" ]]; then
        log_error "Ruby version check failed: $ruby_version < $RUBY_MIN_VERSION"
        print_error "Ruby $RUBY_MIN_VERSION or higher required (found: $ruby_version)"
        print_info "Please upgrade Ruby or use --skip-ruby to bypass this check"
        log_function_call "check_ruby_version" "FAILED - VERSION_TOO_OLD"
        return 1
    fi

    log_message "SUCCESS" "Ruby version check passed: $ruby_version >= $RUBY_MIN_VERSION"
    print_success "Ruby version check passed ($ruby_version)"
    log_function_call "check_ruby_version" "COMPLETE"
    return 0
}

# Check/install Bundler
check_bundler() {
    if [[ "$SKIP_BUNDLER_CHECK" == true ]]; then
        print_warning "Skipping Bundler check"
        return 0
    fi

    print_info "Checking Bundler..."
    
    if command_exists bundle; then
        print_success "Bundler is already installed"
        return 0
    fi

    print_info "Installing Bundler..."
    if gem install bundler; then
        print_success "Bundler installed successfully"
        return 0
    else
        print_error "Failed to install Bundler"
        print_info "You may need to run with sudo or check your Ruby installation"
        return 1
    fi
}

# Install Ruby dependencies
install_dependencies() {
    print_info "Installing Ruby dependencies..."
    
    if bundle install; then
        print_success "Dependencies installed successfully"
        return 0
    else
        print_error "Failed to install dependencies"
        print_info "Please check your Gemfile and network connection"
        return 1
    fi
}

# Setup environment file
setup_environment() {
    print_info "Setting up environment configuration..."
    
    if [[ -f ".env" ]]; then
        print_success "Environment file already exists"
    elif [[ -f ".env.example" ]]; then
        cp ".env.example" ".env"
        print_success "Created .env file from template"
        print_warning "Please edit .env file to configure your settings"
    else
        print_warning "No .env.example found"
        print_info "You'll need to create a .env file manually"
    fi
}

# Setup database
setup_database() {
    print_info "Setting up database..."
    
    if ruby lib/migrations.rb; then
        print_success "Database setup completed"
        return 0
    else
        print_warning "Database setup failed - this is not critical for basic installation"
        print_info "You can run 'ruby lib/migrations.rb' manually later"
        return 0
    fi
}

# Create logs directory
create_logs_directory() {
    print_info "Creating logs directory..."
    
    mkdir -p logs
    print_success "Logs directory created"
}

# Interactive configuration setup
configure_application() {
    print_info "Setting up application configuration..."
    
    if [[ ! -f ".env" ]]; then
        print_error "No .env file found. Please run setup_environment first."
        return 1
    fi
    
    echo
    print_info "Let's configure your Source-License application:"
    echo
    
    # Ask for application name
    read -p "Enter your application name (default: Source-License): " app_name
    app_name=${app_name:-"Source-License"}
    
    # Ask for organization details
    read -p "Enter your organization name: " org_name
    read -p "Enter your organization website URL (optional): " org_url
    
    # Ask for support email
    while true; do
        read -p "Enter support email address: " support_email
        if [[ $support_email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            print_error "Please enter a valid email address"
        fi
    done
    
    # Ask for admin email
    while true; do
        read -p "Enter initial admin email address: " admin_email
        if [[ $admin_email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            print_error "Please enter a valid email address"
        fi
    done
    
    # Ask for admin password
    while true; do
        read -s -p "Enter initial admin password (min 12 characters): " admin_password
        echo
        if [[ ${#admin_password} -ge 12 ]]; then
            read -s -p "Confirm admin password: " admin_password_confirm
            echo
            if [[ "$admin_password" == "$admin_password_confirm" ]]; then
                break
            else
                print_error "Passwords do not match. Please try again."
            fi
        else
            print_error "Password must be at least 12 characters long"
        fi
    done
    
    # Ask for port
    read -p "Enter port number (default: 4567): " port
    port=${port:-4567}
    
    # Ask for environment
    echo "Select environment:"
    echo "1) Development"
    echo "2) Production"
    read -p "Choose (1-2, default: 1): " env_choice
    case $env_choice in
        2) environment="production" ;;
        *) environment="development" ;;
    esac
    
    # Update .env file
    print_info "Updating configuration..."
    
    # Create a backup
    cp .env .env.backup
    
    # Update values in .env
    sed -i.bak "s/^APP_NAME=.*/APP_NAME=$app_name/" .env
    sed -i.bak "s/^PORT=.*/PORT=$port/" .env
    sed -i.bak "s/^APP_ENV=.*/APP_ENV=$environment/" .env
    
    # Update organization details
    if [[ -n "$org_name" ]]; then
        sed -i.bak "s/^ORGANIZATION_NAME=.*/ORGANIZATION_NAME=$org_name/" .env
    fi
    if [[ -n "$org_url" ]]; then
        sed -i.bak "s|^ORGANIZATION_URL=.*|ORGANIZATION_URL=$org_url|" .env
    fi
    sed -i.bak "s/^SUPPORT_EMAIL=.*/SUPPORT_EMAIL=$support_email/" .env
    
    # Update initial admin credentials
    sed -i.bak "s/^INITIAL_ADMIN_EMAIL=.*/INITIAL_ADMIN_EMAIL=$admin_email/" .env
    sed -i.bak "s/^INITIAL_ADMIN_PASSWORD=.*/INITIAL_ADMIN_PASSWORD=$admin_password/" .env
    
    print_success "Configuration completed!"
    echo
    print_info "Your settings:"
    print_info "  Application: $app_name"
    print_info "  Admin Email: $admin_email"
    print_info "  Port: $port"
    print_info "  Environment: $environment"
    echo
    print_warning "Remember to remove INITIAL_ADMIN_* from .env after first login!"
}

# Main installation function
main() {
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Source-License Installer                                  ║
║                         Unix Systems                                         ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Parse arguments
    parse_args "$@"
    
    # Check if we're in the right directory
    if [[ ! -f "app.rb" ]] || [[ ! -f "Gemfile" ]] || [[ ! -f "launch.rb" ]]; then
        print_error "Please run this script from the Source-License project root directory"
        exit 1
    fi
    
    print_info "Installing Source-License on $(uname -s)"
    echo
    
    # Run installation steps
    local success=true
    
    check_ruby_version || success=false
    [[ "$success" == true ]] && check_bundler || success=false
    [[ "$success" == true ]] && install_dependencies || success=false
    [[ "$success" == true ]] && setup_environment
    [[ "$success" == true ]] && setup_database
    [[ "$success" == true ]] && create_logs_directory
    [[ "$success" == true ]] && configure_application
    
    echo
    echo -e "${CYAN}$(printf '=%.0s' {1..80})${NC}"
    
    if [[ "$success" == true ]]; then
        print_success "Installation and setup completed successfully!"
        echo
        echo -e "${GREEN}🎉 Source-License is ready to use!${NC}"
        echo
        echo "To start the application:"
        echo "  Development: ruby launch.rb"
        echo "  Production:  ./deploy.sh"
        echo
        echo "The application will be available at: http://localhost:$port"
        echo "Admin panel will be at: http://localhost:$port/admin"
        echo
        print_info "Use the admin credentials you configured to log in."
    else
        print_error "Installation failed!"
        print_info "Please check the errors above and try again"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
