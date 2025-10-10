#!/bin/bash
# Source-License Update Script
# Pulls latest code from git and updates the deployed systemd service

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
BACKUP_FIRST=false
BRANCH="main"
FORCE_UPDATE=false

# Print functions
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${CYAN}ℹ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

# Show help
show_help() {
    cat << EOF
Source-License Update Script

DESCRIPTION:
    Pulls latest code from git repository and updates the deployed systemd service.
    This script combines git operations with the deploy script to provide seamless updates.

USAGE:
    ./update.sh [OPTIONS]

OPTIONS:
    -b, --branch BRANCH      Git branch to pull from (default: main)
    -B, --backup             Create backup before update
    -f, --force              Force update even if no changes detected
    -h, --help               Show this help message

EXAMPLES:
    ./update.sh                          # Update from main branch
    ./update.sh --backup                 # Update with backup
    ./update.sh --branch develop         # Update from develop branch
    ./update.sh --backup --force         # Force update with backup

REQUIREMENTS:
    - Git repository with remote origin
    - systemd service must be installed (run 'sudo ./deploy install-service' first)
    - Root/sudo privileges for service management

WORKFLOW:
    1. Check prerequisites (git repo, systemd service)
    2. Fetch latest changes from remote repository
    3. Check if updates are available
    4. Pull latest code (if changes detected or forced)
    5. Stop systemd service
    6. Update deployed application
    7. Restart systemd service
    8. Verify service is running
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--branch)
                BRANCH="$2"
                shift 2
                ;;
            -B|--backup)
                BACKUP_FIRST=true
                shift
                ;;
            -f|--force)
                FORCE_UPDATE=true
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

# Check if running as root/sudo
is_root() {
    [[ $EUID -eq 0 ]]
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if we're in a git repository
    if [[ ! -d ".git" ]]; then
        print_error "Not in a git repository. Please run this script from the Source-License project root."
        exit 1
    fi
    
    # Check if git is available
    if ! command_exists git; then
        print_error "Git is not installed or not in PATH"
        exit 1
    fi
    
    # Check if deploy script exists
    if [[ ! -f "./deploy.sh" ]]; then
        print_error "Deploy script (./deploy.sh) not found"
        exit 1
    fi
    
    # Make deploy script executable
    chmod +x ./deploy.sh
    
    # Check if systemd service exists
    if ! systemctl list-unit-files | grep -q "source-license.service"; then
        print_error "Source-License systemd service not found"
        print_info "Run 'sudo ./deploy install-service' first to install the systemd service"
        exit 1
    fi
    
    # Check if we have sudo privileges for systemctl
    if ! is_root && ! sudo -n systemctl status source-license >/dev/null 2>&1; then
        print_warning "This script requires sudo privileges for systemd service management"
        print_info "You may be prompted for your password"
    fi
    
    # Check if remote origin exists
    if ! git remote get-url origin >/dev/null 2>&1; then
        print_error "No git remote 'origin' configured"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Get current git status
get_git_status() {
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    local current_commit=$(git rev-parse HEAD)
    local current_commit_short=$(git rev-parse --short HEAD)
    
    echo "Current branch: $current_branch"
    echo "Current commit: $current_commit_short ($current_commit)"
}

# Check for updates
check_for_updates() {
    print_info "Checking for updates on branch '$BRANCH'..."
    
    # Fetch latest changes
    print_info "Fetching latest changes from remote..."
    if ! git fetch origin "$BRANCH"; then
        print_error "Failed to fetch from remote repository"
        exit 1
    fi
    
    # Check if we're on the target branch
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$current_branch" != "$BRANCH" ]]; then
        print_warning "Currently on branch '$current_branch', but target is '$BRANCH'"
        read -p "Switch to branch '$BRANCH'? [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Switching to branch '$BRANCH'..."
            if ! git checkout "$BRANCH"; then
                print_error "Failed to switch to branch '$BRANCH'"
                exit 1
            fi
        else
            print_info "Continuing with current branch '$current_branch'..."
            BRANCH="$current_branch"
        fi
    fi
    
    # Compare local and remote commits
    local local_commit=$(git rev-parse HEAD)
    local remote_commit=$(git rev-parse "origin/$BRANCH")
    
    if [[ "$local_commit" == "$remote_commit" ]]; then
        print_success "Local repository is up to date"
        if [[ "$FORCE_UPDATE" == false ]]; then
            print_info "No updates available. Use --force to update anyway."
            exit 0
        else
            print_warning "Forcing update even though no changes detected"
        fi
    else
        print_info "Updates available:"
        print_info "  Local:  $(git rev-parse --short "$local_commit")"
        print_info "  Remote: $(git rev-parse --short "$remote_commit")"
        
        # Show what will be updated
        print_info "Changes to be pulled:"
        git log --oneline "$local_commit".."$remote_commit" | head -10
        
        if [[ $(git rev-list --count "$local_commit".."$remote_commit") -gt 10 ]]; then
            print_info "... and $(( $(git rev-list --count "$local_commit".."$remote_commit") - 10 )) more commits"
        fi
    fi
}

# Pull latest changes
pull_updates() {
    print_info "Pulling latest changes..."
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        print_warning "You have uncommitted changes:"
        git status --porcelain
        read -p "Stash changes and continue? [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Stashing uncommitted changes..."
            git stash push -m "Auto-stash before update $(date)"
        else
            print_error "Cannot continue with uncommitted changes"
            exit 1
        fi
    fi
    
    # Pull the latest changes
    if ! git pull origin "$BRANCH"; then
        print_error "Failed to pull changes from remote repository"
        exit 1
    fi
    
    print_success "Successfully pulled latest changes"
    
    # Show what was updated
    local new_commit=$(git rev-parse --short HEAD)
    print_info "Updated to commit: $new_commit"
}

# Update the systemd service
update_systemd_service() {
    print_info "Updating deployed systemd service..."
    
    # Prepare deploy command arguments
    local deploy_args="update-service"
    
    if [[ "$BACKUP_FIRST" == true ]]; then
        deploy_args="$deploy_args --backup"
    fi
    
    # Run the deploy script to update the service
    print_info "Running: sudo ./deploy.sh $deploy_args"
    
    if sudo ./deploy.sh $deploy_args; then
        print_success "Systemd service updated successfully"
    else
        print_error "Failed to update systemd service"
        print_info "Check the deployment logs for more information"
        exit 1
    fi
}

# Verify service is running
verify_service() {
    print_info "Verifying service status..."
    
    # Wait a moment for the service to fully start
    sleep 5
    
    if systemctl is-active --quiet source-license; then
        print_success "Source-License service is running"
        
        # Show service status
        sudo systemctl status source-license --no-pager -l | head -15
        
        print_info ""
        print_info "Service management commands:"
        print_info "  Status: sudo systemctl status source-license"
        print_info "  Logs:   sudo journalctl -u source-license -f"
        print_info "  Stop:   sudo systemctl stop source-license"
        print_info "  Start:  sudo systemctl start source-license"
        
    else
        print_error "Source-License service failed to start"
        print_info "Check logs: sudo journalctl -u source-license"
        exit 1
    fi
}

# Main function
main() {
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Source-License Update Script                              ║
║                      Git Pull + Service Update                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Parse arguments
    parse_args "$@"
    
    print_info "Starting update process..."
    print_info "Target branch: $BRANCH"
    print_info "Backup enabled: $BACKUP_FIRST"
    print_info "Force update: $FORCE_UPDATE"
    echo
    
    # Show current git status
    print_info "Current repository status:"
    get_git_status
    echo
    
    # Check prerequisites
    check_prerequisites
    echo
    
    # Check for updates
    check_for_updates
    echo
    
    # Pull updates
    pull_updates
    echo
    
    # Update systemd service
    update_systemd_service
    echo
    
    # Verify service is running
    verify_service
    echo
    
    print_success "Update completed successfully!"
    
    local final_commit=$(git rev-parse --short HEAD)
    print_info "Repository is now at commit: $final_commit"
    print_info "Systemd service has been updated and restarted"
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${YELLOW}Update interrupted by user${NC}"; exit 130' INT TERM

# Run main function with all arguments
main "$@"
