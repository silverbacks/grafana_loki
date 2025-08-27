#!/bin/bash

# Telegraf Installation Script for Azure Scheduled Events Monitoring
# Compatible with RHEL 8+ and Azure VMs
# Installs and configures Telegraf to send metrics to Grafana Labs

set -euo pipefail

# Script configuration
SCRIPT_NAME="install-telegraf-azure"
LOG_FILE="/var/log/${SCRIPT_NAME}.log"
TELEGRAF_VERSION="1.28.3"
TELEGRAF_USER="telegraf"
TELEGRAF_GROUP="telegraf"

# Directories
TELEGRAF_CONFIG_DIR="/etc/telegraf"
TELEGRAF_LOG_DIR="/var/log/telegraf"
TELEGRAF_DATA_DIR="/var/lib/telegraf"
MONITORING_DIR="/opt/monitoring/telegraf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

warning() {
    log "${YELLOW}WARNING: $1${NC}"
}

success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

# Check if running on Azure VM
check_azure_vm() {
    log "Checking if running on Azure VM..."
    
    if curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" >/dev/null 2>&1; then
        success "Confirmed running on Azure VM"
        return 0
    else
        warning "Not running on Azure VM - scheduled events monitoring may not work"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error "Installation cancelled"
        fi
    fi
}

# Check OS compatibility
check_os() {
    log "Checking OS compatibility..."
    
    if [[ -f /etc/redhat-release ]]; then
        OS_VERSION=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
        if [[ $OS_VERSION -ge 8 ]]; then
            success "RHEL ${OS_VERSION} detected - compatible"
            PACKAGE_MANAGER="dnf"
        else
            error "RHEL ${OS_VERSION} detected - requires RHEL 8 or higher"
        fi
    else
        error "Unsupported OS - requires RHEL 8+"
    fi
}

# Install required packages
install_dependencies() {
    log "Installing dependencies..."
    
    $PACKAGE_MANAGER update -y
    $PACKAGE_MANAGER install -y \
        curl \
        wget \
        tar \
        gzip \
        systemd \
        firewalld \
        || error "Failed to install dependencies"
    
    success "Dependencies installed"
}

# Create telegraf user and directories
create_user_directories() {
    log "Creating telegraf user and directories..."
    
    # Create telegraf user
    if ! id "$TELEGRAF_USER" &>/dev/null; then
        useradd --system --shell /bin/false --home-dir "$TELEGRAF_DATA_DIR" "$TELEGRAF_USER"
        success "Created telegraf user"
    else
        log "Telegraf user already exists"
    fi
    
    # Create directories
    mkdir -p "$TELEGRAF_CONFIG_DIR/conf.d"
    mkdir -p "$TELEGRAF_LOG_DIR"
    mkdir -p "$TELEGRAF_DATA_DIR"
    mkdir -p "$MONITORING_DIR"
    
    # Set permissions
    chown -R "$TELEGRAF_USER:$TELEGRAF_GROUP" "$TELEGRAF_LOG_DIR"
    chown -R "$TELEGRAF_USER:$TELEGRAF_GROUP" "$TELEGRAF_DATA_DIR"
    chown -R root:root "$TELEGRAF_CONFIG_DIR"
    chmod 755 "$TELEGRAF_CONFIG_DIR"
    chmod 644 "$TELEGRAF_CONFIG_DIR"/*.conf 2>/dev/null || true
    
    success "User and directories created"
}

# Download and install Telegraf
install_telegraf() {
    log "Installing Telegraf ${TELEGRAF_VERSION}..."
    
    TELEGRAF_URL="https://dl.influxdata.com/telegraf/releases/telegraf-${TELEGRAF_VERSION}-1.x86_64.rpm"
    
    # Download Telegraf RPM
    cd /tmp
    wget "$TELEGRAF_URL" -O "telegraf-${TELEGRAF_VERSION}.rpm" || error "Failed to download Telegraf"
    
    # Install RPM
    rpm -Uvh "telegraf-${TELEGRAF_VERSION}.rpm" || error "Failed to install Telegraf RPM"
    
    # Cleanup
    rm -f "telegraf-${TELEGRAF_VERSION}.rpm"
    
    success "Telegraf installed"
}

# Copy configuration files
install_configuration() {
    log "Installing Telegraf configuration..."
    
    # Check if configuration files exist in monitoring directory
    CURRENT_DIR="$(dirname "$(readlink -f "$0")")"
    TELEGRAF_MONITORING_DIR="$(dirname "$CURRENT_DIR")"
    
    if [[ -f "$TELEGRAF_MONITORING_DIR/telegraf.conf" ]]; then
        cp "$TELEGRAF_MONITORING_DIR/telegraf.conf" "$TELEGRAF_CONFIG_DIR/"
        success "Main configuration copied"
    else
        error "Main configuration file not found at $TELEGRAF_MONITORING_DIR/telegraf.conf"
    fi
    
    if [[ -d "$TELEGRAF_MONITORING_DIR/conf.d" ]]; then
        cp "$TELEGRAF_MONITORING_DIR/conf.d"/*.conf "$TELEGRAF_CONFIG_DIR/conf.d/"
        success "Additional configurations copied"
    else
        warning "No additional configurations found"
    fi
    
    # Copy environment file
    if [[ -f "$TELEGRAF_MONITORING_DIR/telegraf.env" ]]; then
        cp "$TELEGRAF_MONITORING_DIR/telegraf.env" "/etc/default/telegraf"
        success "Environment configuration copied"
    else
        warning "Environment file not found - creating default"
        cat > /etc/default/telegraf << 'EOF'
# Telegraf Environment Configuration
ENVIRONMENT=production
PROMETHEUS_REMOTE_WRITE_URL=https://prometheus-prod-13-prod-us-east-0.grafana.net/api/prom/push
PROMETHEUS_USERNAME=your_instance_id
PROMETHEUS_PASSWORD=your_api_key
EOF
    fi
    
    # Set permissions
    chmod 644 "$TELEGRAF_CONFIG_DIR"/*.conf
    chmod 644 "$TELEGRAF_CONFIG_DIR/conf.d"/*.conf
    chmod 600 /etc/default/telegraf
    
    success "Configuration installed"
}

# Configure systemd service
configure_systemd() {
    log "Configuring systemd service..."
    
    # Enable and start telegraf service
    systemctl daemon-reload
    systemctl enable telegraf
    
    success "Systemd service configured"
}

# Configure firewall
configure_firewall() {
    log "Configuring firewall..."
    
    if systemctl is-active --quiet firewalld; then
        # Open Prometheus metrics port
        firewall-cmd --permanent --add-port=9273/tcp || warning "Failed to open port 9273"
        firewall-cmd --reload || warning "Failed to reload firewall"
        success "Firewall configured"
    else
        warning "Firewalld not running - skipping firewall configuration"
    fi
}

# Validate configuration
validate_configuration() {
    log "Validating Telegraf configuration..."
    
    if telegraf --config "$TELEGRAF_CONFIG_DIR/telegraf.conf" --test > /dev/null 2>&1; then
        success "Configuration validation passed"
    else
        error "Configuration validation failed - check $LOG_FILE for details"
    fi
}

# Start services
start_services() {
    log "Starting Telegraf service..."
    
    systemctl start telegraf
    
    # Wait a moment and check status
    sleep 3
    
    if systemctl is-active --quiet telegraf; then
        success "Telegraf service started successfully"
    else
        error "Telegraf service failed to start - check 'systemctl status telegraf'"
    fi
}

# Test Azure IMDS connectivity and rate limiting compliance
test_azure_connectivity() {
    log "Testing Azure IMDS connectivity and rate limiting compliance..."
    
    # Test basic IMDS connectivity with proper headers
    if curl -s -H "Metadata:true" -H "User-Agent:telegraf-installer/1.0" --max-time 10 "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-12-13&format=text" >/dev/null; then
        success "Azure IMDS connectivity test passed"
    else
        warning "Azure IMDS connectivity test failed - scheduled events may not work"
        return 1
    fi
    
    # Test scheduled events endpoint with rate limiting compliance
    log "Testing scheduled events endpoint..."
    if curl -s -H "Metadata:true" -H "User-Agent:telegraf-installer/1.0" --max-time 10 "http://169.254.169.254/metadata/scheduledevents?api-version=2021-12-13" >/dev/null; then
        success "Scheduled events endpoint accessible"
    else
        warning "Scheduled events endpoint test failed"
        return 1
    fi
    
    # Rate limiting compliance check
    log "Verifying rate limiting compliance in configuration..."
    if grep -q "interval.*=.*\"30s\"" "$TELEGRAF_CONFIG_DIR/conf.d/azure_scheduled_events.conf" 2>/dev/null; then
        success "Rate limiting compliance verified (30s intervals)"
    else
        warning "Rate limiting configuration may not be optimal"
    fi
    
    # Security check - ensure no sensitive data collection
    log "Verifying security configuration..."
    if ! grep -q "customData\|userData\|publicKeys\|resourceId\|subscriptionId\|vmId" "$TELEGRAF_CONFIG_DIR/conf.d/azure_scheduled_events.conf" 2>/dev/null; then
        success "Security check passed - no sensitive data collection configured"
    else
        warning "Security check failed - sensitive data fields detected in configuration"
    fi
}

# Display next steps
show_next_steps() {
    log "Installation completed successfully!"
    echo
    echo "=============================="
    echo "Next Steps:"
    echo "=============================="
    echo "1. Edit /etc/default/telegraf with your Grafana Cloud credentials"
    echo "2. Restart telegraf: sudo systemctl restart telegraf"
    echo "3. Check status: sudo systemctl status telegraf"
    echo "4. View logs: sudo journalctl -u telegraf -f"
    echo "5. Test metrics endpoint: curl http://localhost:9273/metrics"
    echo
    echo "Configuration files:"
    echo "- Main config: $TELEGRAF_CONFIG_DIR/telegraf.conf"
    echo "- Azure events: $TELEGRAF_CONFIG_DIR/conf.d/azure_scheduled_events.conf"
    echo "- Environment: /etc/default/telegraf"
    echo
    echo "For troubleshooting, check the logs:"
    echo "- Installation: $LOG_FILE"
    echo "- Telegraf: $TELEGRAF_LOG_DIR/telegraf.log"
    echo "- System: journalctl -u telegraf"
}

# Main installation function
main() {
    log "Starting Telegraf installation for Azure Scheduled Events monitoring"
    
    check_root
    check_azure_vm
    check_os
    install_dependencies
    create_user_directories
    install_telegraf
    install_configuration
    configure_systemd
    configure_firewall
    validate_configuration
    start_services
    test_azure_connectivity
    show_next_steps
}

# Run main function
main "$@"