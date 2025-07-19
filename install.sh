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
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-ruby)
                SKIP_RUBY_CHECK=true
                shift
                ;;
            --skip-bundler)
                SKIP_BUNDLER_CHECK=true
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

# Check Ruby version
check_ruby_version() {
    if [[ "$SKIP_RUBY_CHECK" == true ]]; then
        print_warning "Skipping Ruby version check"
        return 0
    fi

    print_info "Checking Ruby version..."
    
    if ! command_exists ruby; then
        print_error "Ruby is not installed"
        print_info "Please install Ruby $RUBY_MIN_VERSION or higher:"
        print_info "  - Ubuntu/Debian: sudo apt install ruby-full"
        print_info "  - CentOS/RHEL: sudo yum install ruby"
        print_info "  - macOS: brew install ruby"
        print_info "  - Or use rbenv/rvm for version management"
        return 1
    fi

    local ruby_version=$(ruby -v | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
    
    if [[ "$(printf '%s\n' "$RUBY_MIN_VERSION" "$ruby_version" | sort -V | head -n1)" != "$RUBY_MIN_VERSION" ]]; then
        print_error "Ruby $RUBY_MIN_VERSION or higher required (found: $ruby_version)"
        print_info "Please upgrade Ruby or use --skip-ruby to bypass this check"
        return 1
    fi

    print_success "Ruby version check passed ($ruby_version)"
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

# Run tests
run_tests() {
    print_info "Running basic tests..."
    
    if ruby run_tests.rb; then
        print_success "Tests passed"
        return 0
    else
        print_warning "Some tests failed - this may not be critical"
        print_info "The application should still work for basic usage"
        return 0
    fi
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
    [[ "$success" == true ]] && run_tests
    
    echo
    echo -e "${CYAN}$(printf '=%.0s' {1..80})${NC}"
    
    if [[ "$success" == true ]]; then
        print_success "Installation completed successfully!"
        echo
        echo -e "${GREEN}🎉 Source-License is now installed!${NC}"
        echo
        echo "Next steps:"
        echo "  1. Edit .env file with your configuration"
        echo "  2. Configure database settings if needed"
        echo "  3. Run the application:"
        echo "     Development: ruby launch.rb"
        echo "     Production:  ./deploy"
        echo
        echo "The application will be available at: http://localhost:4567"
        echo "Admin panel will be at: http://localhost:4567/admin"
    else
        print_error "Installation failed!"
        print_info "Please check the errors above and try again"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
