#!/bin/bash
# Source-License Unified Installer
# Simplified installer for Unix systems (Linux/macOS) using sl_configure utility

# Note: Removed 'set -e' to prevent script from terminating parent shell when sourced
# Instead, we'll handle errors explicitly in each function

# Signal trap to handle CTRL+C gracefully
cleanup() {
    echo
    echo -e "\n${YELLOW}[!] Installation interrupted by user${NC}"
    echo -e "${CYAN}[i] You can run the installer again later: ./install.sh${NC}"
    echo -e "${CYAN}[i] Or run 'ruby ./sl_configure' manually to configure settings${NC}"
    exit 130
}

# Set up signal traps for graceful exit
trap cleanup SIGINT SIGTERM

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
cat > "$INSTALLER_LOG_FILE" << EOF
==========================================
Source-License Installer Script Log
==========================================
Started: $(date)
Ruby Min Version: $RUBY_MIN_VERSION
Skip Ruby Check: $SKIP_RUBY_CHECK
Skip Bundler Check: $SKIP_BUNDLER_CHECK
User: $(whoami)
Working Directory: $(pwd)
System: $(uname -a)
==========================================

EOF

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

# Log errors
log_error() {
    local error_message="$1"
    local line_number="${2:-unknown}"
    log_message "ERROR" "$error_message (Line: $line_number)"
}

# Print functions
print_success() { echo -e "${GREEN}[+] $1${NC}"; }
print_error() { echo -e "${RED}[-] $1${NC}"; }
print_info() { echo -e "${CYAN}[i] $1${NC}"; }
print_warning() { echo -e "${YELLOW}[!] $1${NC}"; }

# Show help
show_help() {
    cat << EOF
Source-License Installer for Unix Systems

USAGE:
    ./install.sh [OPTIONS]

OPTIONS:
    --skip-ruby              Skip Ruby version check
    --skip-bundler           Skip Bundler installation check
    -h, --help               Show this help message

EXAMPLES:
    ./install.sh
    ./install.sh --skip-ruby

NOTES:
    This installer uses the sl_configure utility which requires Ruby $RUBY_MIN_VERSION.
    The sl_configure tool provides interactive configuration with secure value generation.
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
    log_function_call "check_bundler" "START"
    
    if [[ "$SKIP_BUNDLER_CHECK" == true ]]; then
        log_message "WARNING" "Skipping Bundler check as requested"
        print_warning "Skipping Bundler check"
        log_function_call "check_bundler" "COMPLETE - SKIPPED"
        return 0
    fi

    log_message "INFO" "Checking for Bundler installation"
    print_info "Checking Bundler..."
    
    log_command "command -v bundle"
    if command_exists bundle; then
        log_message "SUCCESS" "Bundler is already installed"
        print_success "Bundler is already installed"
        log_function_call "check_bundler" "COMPLETE - ALREADY_INSTALLED"
        return 0
    fi

    log_message "INFO" "Installing Bundler via gem install"
    print_info "Installing Bundler..."
    log_command "gem install bundler"
    if gem install bundler; then
        log_message "SUCCESS" "Bundler installed successfully"
        print_success "Bundler installed successfully"
        log_function_call "check_bundler" "COMPLETE"
        return 0
    else
        log_error "Failed to install Bundler"
        print_error "Failed to install Bundler"
        print_info "You may need to run with sudo or check your Ruby installation"
        log_function_call "check_bundler" "FAILED"
        return 1
    fi
}

# Install Ruby dependencies
install_dependencies() {
    log_function_call "install_dependencies" "START"
    log_message "INFO" "Installing Ruby dependencies via bundle install"
    print_info "Installing Ruby dependencies..."
    
    log_command "bundle install"
    if bundle install; then
        log_message "SUCCESS" "Dependencies installed successfully"
        print_success "Dependencies installed successfully"
        log_function_call "install_dependencies" "COMPLETE"
        return 0
    else
        log_error "Failed to install dependencies"
        print_error "Failed to install dependencies"
        print_info "Please check your Gemfile and network connection"
        log_function_call "install_dependencies" "FAILED"
        return 1
    fi
}

# Setup environment file
setup_environment() {
    log_function_call "setup_environment" "START"
    log_message "INFO" "Setting up environment configuration"
    print_info "Setting up environment configuration..."
    
    if [[ -f ".env" ]]; then
        log_message "INFO" "Environment file already exists"
        print_success "Environment file already exists"
    elif [[ -f ".env.example" ]]; then
        log_message "INFO" "Creating .env file from .env.example"
        log_command "cp .env.example .env"
        cp ".env.example" ".env"
        log_message "SUCCESS" "Created .env file from template"
        print_success "Created .env file from template"
    else
        log_message "WARNING" "No .env.example found"
        print_warning "No .env.example found"
        print_info "You'll need to create a .env file manually"
        log_function_call "setup_environment" "COMPLETE - WARNING"
        return 1
    fi
    
    log_function_call "setup_environment" "COMPLETE"
    return 0
}

# Setup database
setup_database() {
    log_function_call "setup_database" "START"
    log_message "INFO" "Setting up database via migrations"
    print_info "Setting up database..."
    
    log_command "ruby lib/migrations.rb"
    if ruby lib/migrations.rb; then
        log_message "SUCCESS" "Database setup completed"
        print_success "Database setup completed"
        log_function_call "setup_database" "COMPLETE"
        return 0
    else
        log_message "WARNING" "Database setup failed - not critical for basic installation"
        print_warning "Database setup failed - this is not critical for basic installation"
        print_info "You can run 'ruby lib/migrations.rb' manually later"
        log_function_call "setup_database" "COMPLETE - WARNING"
        return 0
    fi
}

# Create logs directory
create_logs_directory() {
    log_function_call "create_logs_directory" "START"
    log_message "INFO" "Creating logs directory"
    print_info "Creating logs directory..."
    
    log_command "mkdir -p logs"
    mkdir -p logs
    log_message "SUCCESS" "Logs directory created/verified"
    print_success "Logs directory ready"
    log_function_call "create_logs_directory" "COMPLETE"
}

# Run sl_configure utility for application configuration
run_sl_configure() {
    log_function_call "run_sl_configure" "START"
    log_message "INFO" "Running sl_configure utility for application configuration"
    
    echo
    print_info "Running Source-License configuration utility..."
    echo
    print_info "The sl_configure tool will guide you through setting up your application."
    print_info "It can automatically generate secure values for sensitive settings."
    echo
    
    log_command "ruby ./sl_configure"
    if ruby ./sl_configure; then
        log_message "SUCCESS" "sl_configure completed successfully"
        print_success "Configuration completed successfully!"
        log_function_call "run_sl_configure" "COMPLETE"
        return 0
    else
        log_error "sl_configure failed"
        print_error "Configuration failed"
        print_info "You can run 'ruby ./sl_configure' manually later"
        log_function_call "run_sl_configure" "FAILED"
        return 1
    fi
}

# Main installation function
main() {
    log_function_call "main" "START"
    log_message "INFO" "Starting installer script execution"
    
    echo -e "${CYAN}"
    echo "================================================================================"
    echo "                       Source-License Installer                                "
    echo "                           Unix Systems                                        "
    echo "                        Using sl_configure utility                            "
    echo "================================================================================"
    echo -e "${NC}"
    
    # Parse arguments
    parse_args "$@"
    
    # Check if we're in the right directory
    log_message "INFO" "Verifying we're in the correct directory"
    if [[ ! -f "app.rb" ]] || [[ ! -f "Gemfile" ]] || [[ ! -f "launch.rb" ]] || [[ ! -f "sl_configure" ]]; then
        log_error "Not in Source-License project root directory or sl_configure not found"
        print_error "Please run this script from the Source-License project root directory"
        print_error "Make sure the sl_configure utility is present"
        exit 1
    fi
    
    log_message "INFO" "Directory verification passed"
    print_info "Installing Source-License on $(uname -s) using sl_configure utility"
    echo
    
    # Run installation steps
    local success=true
    
    log_message "INFO" "Starting installation steps"
    
    if ! check_ruby_version; then
        success=false
        log_message "ERROR" "Ruby version check failed"
    else
        log_message "SUCCESS" "Ruby version check passed"
    fi
    
    if [[ "$success" == true ]] && ! check_bundler; then
        success=false
        log_message "ERROR" "Bundler installation failed"
    elif [[ "$success" == true ]]; then
        log_message "SUCCESS" "Bundler installation completed"
    fi
    
    if [[ "$success" == true ]] && ! install_dependencies; then
        success=false
        log_message "ERROR" "Dependencies installation failed"
    elif [[ "$success" == true ]]; then
        log_message "SUCCESS" "Dependencies installation completed"
    fi
    
    if [[ "$success" == true ]]; then
        setup_environment
        log_message "SUCCESS" "Environment initialization completed"
    fi
    
    if [[ "$success" == true ]]; then
        setup_database
        log_message "SUCCESS" "Database initialization completed"
    fi
    
    if [[ "$success" == true ]]; then
        create_logs_directory
        log_message "SUCCESS" "Logs directory setup completed"
    fi
    
    if [[ "$success" == true ]]; then
        if ! run_sl_configure; then
            print_warning "Configuration step failed, but installation can continue"
            print_info "You can run 'ruby ./sl_configure' manually later to configure your settings"
        fi
    fi
    
    echo
    echo -e "${CYAN}$(printf '=%.0s' {1..80})${NC}"
    
    if [[ "$success" == true ]]; then
        log_message "SUCCESS" "Installation completed successfully"
        print_success "Installation completed successfully!"
        echo
        echo -e "${GREEN}Source-License is ready to use!${NC}"
        echo
        echo "To start the application:"
        echo "  Development: ruby launch.rb"
        echo "  Production:  ./deploy.sh"
        echo
        echo "To reconfigure your settings anytime:"
        echo "     ruby ./sl_configure"
        echo
        print_info "Check your .env file for the configured port and admin credentials."
    else
        log_message "ERROR" "Installation failed"
        print_error "Installation failed!"
        print_info "Please check the errors above and try again"
        print_info "You may need to run 'ruby ./sl_configure' manually if the basic setup completed"
        exit 1
    fi
    
    log_message "INFO" "Installer script execution completed"
    log_function_call "main" "COMPLETE"
    
    # Log session end
    cat >> "$INSTALLER_LOG_FILE" << EOF

Session completed: $(date)
Final status: $(if [[ "$success" == true ]]; then echo "SUCCESS"; else echo "FAILED"; fi)
Exit status: $?
EOF
}

# Run main function with all arguments
main "$@"
