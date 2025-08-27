#!/bin/bash

# Telegraf Azure Scheduled Events Configuration Validation Script
# Tests configuration, connectivity, and metrics collection

set -euo pipefail

# Script configuration
SCRIPT_NAME="validate-telegraf-azure"
LOG_FILE="/var/log/${SCRIPT_NAME}.log"

# Configuration paths
TELEGRAF_CONFIG_DIR="/etc/telegraf"
TELEGRAF_ENV_FILE="/etc/default/telegraf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    log "${RED}❌ ERROR: $1${NC}"
}

warning() {
    log "${YELLOW}⚠️  WARNING: $1${NC}"
}

success() {
    log "${GREEN}✅ SUCCESS: $1${NC}"
}

info() {
    log "${BLUE}ℹ️  INFO: $1${NC}"
}

# Load environment variables
load_environment() {
    if [[ -f "$TELEGRAF_ENV_FILE" ]]; then
        source "$TELEGRAF_ENV_FILE"
        success "Environment variables loaded"
    else
        warning "Environment file not found at $TELEGRAF_ENV_FILE"
    fi
}

# Test 1: Check if Telegraf is installed
test_telegraf_installation() {
    info "Testing Telegraf installation..."
    
    if command -v telegraf >/dev/null 2>&1; then
        TELEGRAF_VERSION=$(telegraf version | head -1)
        success "Telegraf is installed: $TELEGRAF_VERSION"
        return 0
    else
        error "Telegraf is not installed"
        return 1
    fi
}

# Test 2: Validate configuration syntax
test_configuration_syntax() {
    info "Testing configuration syntax..."
    
    if telegraf --config "$TELEGRAF_CONFIG_DIR/telegraf.conf" --test >/dev/null 2>&1; then
        success "Configuration syntax is valid"
        return 0
    else
        error "Configuration syntax validation failed"
        telegraf --config "$TELEGRAF_CONFIG_DIR/telegraf.conf" --test 2>&1 | head -10
        return 1
    fi
}

# Test 3: Check Azure IMDS connectivity and compliance
test_azure_imds() {
    info "Testing Azure Instance Metadata Service connectivity and compliance..."
    
    # Test basic IMDS connectivity with proper headers and API version
    if curl -s -H "Metadata:true" -H "User-Agent:telegraf-validator/1.0" --max-time 10 "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-12-13&format=text" >/dev/null 2>&1; then
        success "Azure IMDS is accessible with latest API version"
    else
        error "Azure IMDS is not accessible - not running on Azure VM?"
        return 1
    fi
    
    # Test scheduled events endpoint with proper headers
    if curl -s -H "Metadata:true" -H "User-Agent:telegraf-validator/1.0" --max-time 10 "http://169.254.169.254/metadata/scheduledevents?api-version=2021-12-13" >/dev/null 2>&1; then
        success "Azure Scheduled Events endpoint is accessible"
    else
        error "Azure Scheduled Events endpoint is not accessible"
        return 1
    fi
    
    # Rate limiting compliance check
    info "Checking rate limiting compliance..."
    SCHEDULED_EVENTS_INTERVAL=$(grep -o 'interval.*=.*"[0-9]*s"' "$TELEGRAF_CONFIG_DIR/conf.d/azure_scheduled_events.conf" | head -1 | grep -o '[0-9]*')
    if [[ "$SCHEDULED_EVENTS_INTERVAL" -ge 30 ]]; then
        success "Rate limiting compliant: ${SCHEDULED_EVENTS_INTERVAL}s intervals (Microsoft recommends ≥30s)"
    else
        warning "Rate limiting concern: ${SCHEDULED_EVENTS_INTERVAL}s intervals (Microsoft recommends ≥30s)"
    fi
    
    # Security compliance check
    info "Checking security compliance..."
    SENSITIVE_FIELDS=("customData" "userData" "publicKeys" "resourceId" "subscriptionId" "vmId")
    SENSITIVE_FOUND=false
    
    for field in "${SENSITIVE_FIELDS[@]}"; do
        if grep -q "$field" "$TELEGRAF_CONFIG_DIR/conf.d/azure_scheduled_events.conf" 2>/dev/null; then
            warning "Security concern: Sensitive field '$field' found in configuration"
            SENSITIVE_FOUND=true
        fi
    done
    
    if [[ "$SENSITIVE_FOUND" == "false" ]]; then
        success "Security compliance: No sensitive fields detected in configuration"
    fi
    
    # API version check
    API_VERSION=$(grep -o 'api-version=[0-9-]*' "$TELEGRAF_CONFIG_DIR/conf.d/azure_scheduled_events.conf" | head -1 | cut -d'=' -f2)
    if [[ "$API_VERSION" == "2021-12-13" ]]; then
        success "Using latest stable IMDS API version: $API_VERSION"
    else
        warning "Consider upgrading to latest IMDS API version 2021-12-13 (current: $API_VERSION)"
    fi
    
    return 0
}

# Test 4: Check Telegraf service status
test_service_status() {
    info "Testing Telegraf service status..."
    
    if systemctl is-active --quiet telegraf; then
        success "Telegraf service is running"
        
        # Show service info
        SINCE=$(systemctl show telegraf --property=ActiveEnterTimestamp --value)
        info "Service active since: $SINCE"
        
        return 0
    else
        error "Telegraf service is not running"
        warning "Service status: $(systemctl is-active telegraf)"
        warning "Check logs with: journalctl -u telegraf -n 20"
        return 1
    fi
}

# Test 5: Check Prometheus metrics endpoint
test_metrics_endpoint() {
    info "Testing Prometheus metrics endpoint..."
    
    METRICS_PORT=${PROMETHEUS_LISTEN_PORT:-9273}
    
    if curl -s "http://localhost:$METRICS_PORT/metrics" >/dev/null; then
        success "Prometheus metrics endpoint is accessible on port $METRICS_PORT"
        
        # Count available metrics
        METRIC_COUNT=$(curl -s "http://localhost:$METRICS_PORT/metrics" | grep -c "^[a-zA-Z]" || echo "0")
        info "Number of metrics available: $METRIC_COUNT"
        
        return 0
    else
        error "Prometheus metrics endpoint is not accessible on port $METRICS_PORT"
        return 1
    fi
}

# Test 6: Verify Azure scheduled events collection
test_azure_events_collection() {
    info "Testing Azure scheduled events data collection..."
    
    METRICS_PORT=${PROMETHEUS_LISTEN_PORT:-9273}
    
    # Check for Azure-specific metrics
    AZURE_METRICS=$(curl -s "http://localhost:$METRICS_PORT/metrics" | grep -c "azure_" || echo "0")
    
    if [[ $AZURE_METRICS -gt 0 ]]; then
        success "Found $AZURE_METRICS Azure-related metrics"
        
        # Show sample Azure metrics
        info "Sample Azure metrics:"
        curl -s "http://localhost:$METRICS_PORT/metrics" | grep "azure_" | head -5 | while read line; do
            info "  $line"
        done
        
        return 0
    else
        warning "No Azure-specific metrics found - data may still be collecting"
        return 1
    fi
}

# Test 7: Check log files
test_log_files() {
    info "Checking Telegraf log files..."
    
    LOG_DIR="/var/log/telegraf"
    
    if [[ -d "$LOG_DIR" ]]; then
        success "Log directory exists: $LOG_DIR"
        
        # Check for recent log entries
        if [[ -f "$LOG_DIR/telegraf.log" ]]; then
            RECENT_LINES=$(tail -5 "$LOG_DIR/telegraf.log" 2>/dev/null | wc -l)
            if [[ $RECENT_LINES -gt 0 ]]; then
                success "Log file has recent entries"
                info "Recent log entries:"
                tail -3 "$LOG_DIR/telegraf.log" 2>/dev/null | while read line; do
                    info "  $line"
                done
            else
                warning "Log file exists but appears empty"
            fi
        else
            warning "No telegraf.log file found"
        fi
    else
        warning "Log directory not found: $LOG_DIR"
    fi
}

# Test 8: Validate Grafana Cloud connectivity (if configured)
test_grafana_cloud_connectivity() {
    info "Testing Grafana Cloud connectivity..."
    
    if [[ -n "${PROMETHEUS_REMOTE_WRITE_URL:-}" ]]; then
        # Test basic connectivity to Grafana Cloud
        GRAFANA_HOST=$(echo "$PROMETHEUS_REMOTE_WRITE_URL" | sed -e 's|^[^/]*//||' -e 's|/.*||')
        
        if ping -c 1 -W 3 "$GRAFANA_HOST" >/dev/null 2>&1; then
            success "Can reach Grafana Cloud host: $GRAFANA_HOST"
        else
            warning "Cannot reach Grafana Cloud host: $GRAFANA_HOST"
        fi
        
        # Note: We can't easily test the full write endpoint without proper credentials
        info "Remote write URL configured: $PROMETHEUS_REMOTE_WRITE_URL"
        
        if [[ -n "${PROMETHEUS_USERNAME:-}" ]]; then
            info "Prometheus username configured: $PROMETHEUS_USERNAME"
        else
            warning "Prometheus username not configured"
        fi
        
        if [[ -n "${PROMETHEUS_PASSWORD:-}" ]]; then
            info "Prometheus password configured: [REDACTED]"
        else
            warning "Prometheus password not configured"
        fi
    else
        warning "Grafana Cloud remote write URL not configured"
    fi
}

# Test 9: Check file permissions
test_file_permissions() {
    info "Checking file permissions..."
    
    # Check config directory permissions
    if [[ -r "$TELEGRAF_CONFIG_DIR/telegraf.conf" ]]; then
        success "Main config file is readable"
    else
        error "Main config file is not readable"
    fi
    
    # Check environment file permissions
    if [[ -r "$TELEGRAF_ENV_FILE" ]]; then
        success "Environment file is readable"
        PERMS=$(stat -c "%a" "$TELEGRAF_ENV_FILE")
        if [[ "$PERMS" = "600" ]]; then
            success "Environment file has correct permissions (600)"
        else
            warning "Environment file permissions are $PERMS (should be 600)"
        fi
    else
        warning "Environment file is not readable"
    fi
}

# Generate test report
generate_report() {
    echo
    echo "=================================================="
    echo "TELEGRAF AZURE SCHEDULED EVENTS VALIDATION REPORT"
    echo "=================================================="
    echo "Generated: $(date)"
    echo "Host: $(hostname)"
    echo
    
    # System info
    echo "System Information:"
    echo "- OS: $(cat /etc/redhat-release 2>/dev/null || echo "Unknown")"
    echo "- Kernel: $(uname -r)"
    echo "- Uptime: $(uptime -p)"
    echo
    
    # Telegraf info
    if command -v telegraf >/dev/null 2>&1; then
        echo "Telegraf Information:"
        echo "- Version: $(telegraf version | head -1)"
        echo "- Config: $TELEGRAF_CONFIG_DIR/telegraf.conf"
        echo "- Status: $(systemctl is-active telegraf 2>/dev/null || echo "unknown")"
        echo
    fi
    
    # Configuration summary
    echo "Configuration Summary:"
    if [[ -f "$TELEGRAF_ENV_FILE" ]]; then
        source "$TELEGRAF_ENV_FILE"
        echo "- Environment: ${ENVIRONMENT:-not set}"
        echo "- Prometheus endpoint: ${PROMETHEUS_REMOTE_WRITE_URL:-not set}"
        echo "- Metrics port: ${PROMETHEUS_LISTEN_PORT:-9273}"
    else
        echo "- Environment file not found"
    fi
    echo
    
    echo "For detailed logs, check:"
    echo "- Installation log: $LOG_FILE"
    echo "- Telegraf logs: journalctl -u telegraf -f"
    echo "- Telegraf file log: /var/log/telegraf/telegraf.log"
    echo
    echo "To test metrics manually:"
    echo "- curl http://localhost:9273/metrics"
    echo "- curl -H 'Metadata:true' http://169.254.169.254/metadata/scheduledevents?api-version=2020-07-01"
}

# Main validation function
main() {
    log "Starting Telegraf Azure Scheduled Events validation"
    
    local test_count=0
    local test_passed=0
    
    # Load environment
    load_environment
    
    # Run all tests
    tests=(
        "test_telegraf_installation"
        "test_configuration_syntax"
        "test_azure_imds"
        "test_service_status"
        "test_metrics_endpoint"
        "test_azure_events_collection"
        "test_log_files"
        "test_grafana_cloud_connectivity"
        "test_file_permissions"
    )
    
    for test_func in "${tests[@]}"; do
        test_count=$((test_count + 1))
        echo
        if $test_func; then
            test_passed=$((test_passed + 1))
        fi
    done
    
    echo
    echo "=================================================="
    echo "VALIDATION SUMMARY"
    echo "=================================================="
    echo "Tests passed: $test_passed/$test_count"
    
    if [[ $test_passed -eq $test_count ]]; then
        success "All tests passed! Telegraf is properly configured for Azure scheduled events monitoring."
    else
        warning "Some tests failed. Check the output above for details."
    fi
    
    generate_report
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help]"
        echo "Validates Telegraf configuration for Azure scheduled events monitoring"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac