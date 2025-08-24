#!/bin/bash

# Grafana Alloy Installation Script for RHEL 8+ Systems
# This script installs and configures Grafana Alloy for log collection
# from /var/log/messages with critical event filtering

set -euo pipefail

# Configuration variables
ALLOY_VERSION="v1.0.0"
ALLOY_USER="alloy"
ALLOY_GROUP="alloy"
CONFIG_DIR="/etc/alloy"
DATA_DIR="/var/lib/alloy"
LOG_DIR="/var/log/alloy"
SYSTEMD_DIR="/etc/systemd/system"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Check RHEL version
check_rhel_version() {
    if [[ ! -f /etc/redhat-release ]]; then
        log_error "This script is designed for RHEL systems"
        exit 1
    fi
    
    local version=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
    if [[ $version -lt 8 ]]; then
        log_error "This script requires RHEL 8 or higher. Found version: $version"
        exit 1
    fi
    
    log_success "RHEL version $version detected"
}

# Create alloy user and group
create_user() {
    if ! getent group $ALLOY_GROUP &>/dev/null; then
        groupadd --system $ALLOY_GROUP
        log_success "Created group: $ALLOY_GROUP"
    fi
    
    if ! getent passwd $ALLOY_USER &>/dev/null; then
        useradd --system --gid $ALLOY_GROUP --home-dir $DATA_DIR \
                --shell /sbin/nologin --comment "Grafana Alloy" $ALLOY_USER
        log_success "Created user: $ALLOY_USER"
    fi
}

# Create directories
create_directories() {
    local dirs=("$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" "$DATA_DIR/data" "$DATA_DIR/positions")
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        chown $ALLOY_USER:$ALLOY_GROUP "$dir"
        chmod 755 "$dir"
        log_success "Created directory: $dir"
    done
    
    # Special permissions for positions file
    chmod 644 "$DATA_DIR/positions" 2>/dev/null || true
}

# Download and install Grafana Alloy
install_alloy() {
    local arch
    case $(uname -m) in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *) log_error "Unsupported architecture: $(uname -m)"; exit 1 ;;
    esac
    
    local download_url="https://github.com/grafana/alloy/releases/download/$ALLOY_VERSION/alloy-linux-$arch.zip"
    local temp_dir=$(mktemp -d)
    
    log_info "Downloading Grafana Alloy $ALLOY_VERSION for $arch..."
    
    cd "$temp_dir"
    curl -L -o alloy.zip "$download_url"
    unzip alloy.zip
    
    # Install binary
    install -m 755 alloy-linux-$arch /usr/local/bin/alloy
    
    # Cleanup
    cd /
    rm -rf "$temp_dir"
    
    log_success "Grafana Alloy installed to /usr/local/bin/alloy"
}

# Install configuration files
install_config() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local monitoring_dir="$script_dir/../monitoring"
    
    # Copy Alloy configuration
    if [[ -f "$monitoring_dir/alloy/config.alloy" ]]; then
        cp "$monitoring_dir/alloy/config.alloy" "$CONFIG_DIR/"
        chown $ALLOY_USER:$ALLOY_GROUP "$CONFIG_DIR/config.alloy"
        chmod 644 "$CONFIG_DIR/config.alloy"
        log_success "Installed Alloy configuration"
    else
        log_error "Alloy configuration file not found at $monitoring_dir/alloy/config.alloy"
        exit 1
    fi
    
    # Copy environment file
    if [[ -f "$monitoring_dir/systemd/alloy.env" ]]; then
        cp "$monitoring_dir/systemd/alloy.env" "/etc/default/alloy"
        chmod 640 "/etc/default/alloy"
        log_success "Installed environment configuration"
    fi
    
    # Copy systemd service
    if [[ -f "$monitoring_dir/systemd/alloy.service" ]]; then
        cp "$monitoring_dir/systemd/alloy.service" "$SYSTEMD_DIR/"
        systemctl daemon-reload
        log_success "Installed systemd service"
    else
        log_error "Systemd service file not found"
        exit 1
    fi
}

# Configure SELinux (if enabled)
configure_selinux() {
    if command -v getenforce &>/dev/null && [[ $(getenforce) != "Disabled" ]]; then
        log_info "Configuring SELinux policies for Alloy..."
        
        # Allow Alloy to read log files
        setsebool -P logging_syslog_use_tty on
        
        # Create custom SELinux policy if needed
        cat > /tmp/alloy.te << 'EOF'
module alloy 1.0;

require {
    type unconfined_t;
    type var_log_t;
    class file { read getattr open };
}

# Allow alloy to read log files
allow unconfined_t var_log_t:file { read getattr open };
EOF
        
        checkmodule -M -m -o /tmp/alloy.mod /tmp/alloy.te
        semodule_package -o /tmp/alloy.pp -m /tmp/alloy.mod
        semodule -i /tmp/alloy.pp
        
        rm -f /tmp/alloy.{te,mod,pp}
        
        log_success "SELinux policies configured"
    fi
}

# Configure firewall (if needed)
configure_firewall() {
    if systemctl is-active firewalld &>/dev/null; then
        log_info "Firewall is active, configuring rules if needed..."
        # Add any firewall rules here if Alloy needs to expose ports
        log_success "Firewall configured"
    fi
}

# Set up log rotation
setup_logrotation() {
    cat > /etc/logrotate.d/alloy << 'EOF'
/var/log/alloy/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    postrotate
        /bin/systemctl reload alloy.service > /dev/null 2>&1 || true
    endscript
}
EOF
    
    log_success "Log rotation configured"
}

# Validate installation
validate_installation() {
    # Check if binary exists and is executable
    if [[ ! -x /usr/local/bin/alloy ]]; then
        log_error "Alloy binary not found or not executable"
        return 1
    fi
    
    # Check configuration syntax
    if ! /usr/local/bin/alloy fmt "$CONFIG_DIR/config.alloy" &>/dev/null; then
        log_error "Alloy configuration syntax error"
        return 1
    fi
    
    # Check if systemd service is installed
    if [[ ! -f "$SYSTEMD_DIR/alloy.service" ]]; then
        log_error "Systemd service not installed"
        return 1
    fi
    
    log_success "Installation validation passed"
    return 0
}

# Start and enable service
start_service() {
    systemctl enable alloy.service
    systemctl start alloy.service
    
    # Wait a moment and check status
    sleep 3
    
    if systemctl is-active alloy.service &>/dev/null; then
        log_success "Alloy service started successfully"
        log_info "Service status:"
        systemctl status alloy.service --no-pager -l
    else
        log_error "Failed to start Alloy service"
        log_info "Service logs:"
        journalctl -u alloy.service --no-pager -l
        return 1
    fi
}

# Main installation function
main() {
    log_info "Starting Grafana Alloy installation for RHEL 8+ systems..."
    
    check_root
    check_rhel_version
    
    create_user
    create_directories
    install_alloy
    install_config
    configure_selinux
    configure_firewall
    setup_logrotation
    
    if validate_installation; then
        start_service
        
        log_success "Grafana Alloy installation completed successfully!"
        log_info "Configuration file: $CONFIG_DIR/config.alloy"
        log_info "Environment file: /etc/default/alloy"
        log_info "Log files: $LOG_DIR/"
        log_info "Data directory: $DATA_DIR/"
        log_info ""
        log_info "Next steps:"
        log_info "1. Edit /etc/default/alloy with your Grafana Cloud credentials"
        log_info "2. Restart the service: systemctl restart alloy.service"
        log_info "3. Monitor logs: journalctl -u alloy.service -f"
    else
        log_error "Installation validation failed"
        exit 1
    fi
}

# Run main function
main "$@"