# Grafana Loki Monitoring for RHEL 8+ Systems

## Overview

This monitoring solution provides comprehensive log collection and alerting for critical system events on RHEL 8+ systems. It uses Grafana Alloy to collect logs from `/var/log/messages` and sends them to Grafana Cloud Loki for analysis and alerting.

## Architecture

```mermaid
graph TB
    A[RHEL 8+ System] --> B[/var/log/messages]
    B --> C[Grafana Alloy]
    C --> D[Grafana Cloud Loki]
    D --> E[Grafana Dashboard]
    D --> F[Alert Manager]
    F --> G[Notifications]
```

### Components

1. **Grafana Alloy**: Unified observability agent that collects logs
2. **Grafana Cloud Loki**: Log aggregation and storage
3. **Grafana Dashboard**: Visualization of critical events
4. **Alert Manager**: Handles alerting for critical events

## Monitored Events

### Critical System Events
- **System Errors**: General system failures, segfaults, kernel oops
- **NFS Issues**: NFS timeouts, connection failures, server not responding
- **Puppet Agent Failures**: Puppet run failures, connection issues
- **Filesystem Read-Only**: Filesystem remounted read-only due to errors
- **Kernel Issues**: Kernel panics, OOM killer, memory errors
- **Service Failures**: Systemd service failures
- **Security Issues**: Authentication failures, permission denied
- **Storage Issues**: Disk full, I/O errors, device not ready

### Alert Severity Levels
- **Critical (P1)**: Immediate attention required (filesystem read-only, kernel panic)
- **Warning (P2)**: Attention needed (repeated failures, security issues)

## Directory Structure

```
monitoring/
├── alloy/
│   └── config.alloy           # Grafana Alloy configuration
├── loki/
│   └── loki-config.yaml       # Loki server configuration
├── grafana/
│   ├── dashboards/
│   │   └── rhel-critical-events.json
│   └── alerts/
│       ├── critical-system-alerts.yaml
│       └── filesystem-alerts.yaml
├── systemd/
│   ├── alloy.service          # Systemd service file
│   └── alloy.env              # Environment configuration
└── scripts/
    └── install-alloy-rhel.sh  # Installation script
```

## Installation

### Prerequisites

1. **RHEL 8 or higher**
2. **Root access**
3. **Internet connectivity**
4. **Grafana Cloud account** with Loki access

### Step 1: Prepare Grafana Cloud

1. Sign up for [Grafana Cloud](https://grafana.com/products/cloud/)
2. Create a Loki data source
3. Generate an API key with MetricsPublisher role
4. Note your Loki endpoint URL and credentials

### Step 2: Run Installation Script

```bash
# Make script executable
chmod +x monitoring/scripts/install-alloy-rhel.sh

# Run installation (as root)
sudo ./monitoring/scripts/install-alloy-rhel.sh
```

### Step 3: Configure Credentials

Edit the environment file with your Grafana Cloud credentials:

```bash
sudo nano /etc/default/alloy
```

Update the following variables:
```bash
LOKI_ENDPOINT=https://logs-prod-us-central1.grafana.net/loki/api/v1/push
LOKI_USERNAME=your_loki_instance_id
LOKI_PASSWORD=your_grafana_cloud_api_key
ENVIRONMENT=production
SERVER_TIMEZONE=Local
```

### Step 4: Restart Service

```bash
sudo systemctl restart alloy.service
sudo systemctl status alloy.service
```

## Configuration Details

### Grafana Alloy Configuration

The `config.alloy` file includes:

- **File Discovery**: Monitors `/var/log/messages`
- **Log Processing**: Filters and labels critical events
- **Event Types**: Categorizes events by type and severity
- **Azure Metadata**: Adds cloud-specific labels

Key features:
- Real-time log tailing
- Position tracking for reliability
- Regex-based event filtering
- Structured labeling for easy querying

### Alert Rules

#### Critical System Alerts (`critical-system-alerts.yaml`)
- **SystemErrorsHigh**: >5 errors in 5 minutes
- **NFSNotResponding**: Any NFS issues in 10 minutes
- **PuppetAgentFailure**: >2 failures in 30 minutes
- **KernelPanic**: Immediate alert on kernel issues
- **ServiceFailures**: >3 failures in 15 minutes
- **SecurityIssues**: >10 security events in 10 minutes
- **StorageIssues**: Any storage problems

#### Filesystem Alerts (`filesystem-alerts.yaml`)
- **FilesystemReadOnly**: Immediate alert on read-only filesystem
- **FilesystemCorruption**: Immediate alert on corruption
- **DiskSpaceCritical**: Disk full warnings
- **IOErrors**: >2 I/O errors in 5 minutes
- **UnforeseenSystemErrors**: Unexpected errors
- **AzureVMMetadataErrors**: Azure-specific issues
- **MemoryPressure**: OOM killer activity

## Grafana Dashboard

The dashboard provides:

1. **Critical Events Overview**: Real-time statistics
2. **System Errors Timeline**: Chronological error view
3. **Event-Specific Panels**: NFS, Puppet, filesystem issues
4. **Error Rate Trends**: Time-series visualization
5. **Hostname Filtering**: Multi-VM support

### Dashboard Features
- Real-time updates (30-second refresh)
- 6-hour default time range
- Event type categorization
- Hostname-based filtering

## Maintenance

### Log Rotation

Automatic log rotation is configured via `/etc/logrotate.d/alloy`:
- Daily rotation
- 7-day retention
- Compression enabled
- Service reload on rotation

### Monitoring Health

Check Alloy service status:
```bash
sudo systemctl status alloy.service
sudo journalctl -u alloy.service -f
```

Validate configuration:
```bash
sudo /usr/local/bin/alloy fmt /etc/alloy/config.alloy
```

### Performance Tuning

For high-volume logging environments, adjust in `/etc/default/alloy`:
```bash
ALLOY_MAX_RECV_MSG_SIZE=104857600
ALLOY_TARGET_SYNC_PERIOD=10s
```

## Troubleshooting

### Common Issues

1. **Service fails to start**
   ```bash
   sudo journalctl -u alloy.service --no-pager -l
   ```
   - Check configuration syntax
   - Verify file permissions
   - Ensure credentials are correct

2. **No logs appearing in Grafana**
   - Verify Loki endpoint and credentials
   - Check network connectivity
   - Review Alloy logs for errors

3. **High memory usage**
   - Reduce log processing volume
   - Adjust buffer sizes
   - Check for log rotation issues

4. **SELinux denials**
   ```bash
   sudo ausearch -m avc -ts recent
   ```
   - Review and create custom policies if needed

### Performance Monitoring

Monitor Alloy performance:
```bash
# CPU and memory usage
ps aux | grep alloy

# Network connections
ss -tulpn | grep alloy

# Disk usage
du -sh /var/lib/alloy
```

## Security Considerations

1. **Service Account**: Runs as dedicated `alloy` user
2. **File Permissions**: Read-only access to log files
3. **Network Security**: HTTPS communication to Grafana Cloud
4. **Credential Management**: Environment file with restricted permissions
5. **SELinux Compatibility**: Custom policies for log access

## Azure-Specific Features

1. **Metadata Integration**: Automatic Azure resource tagging
2. **Regional Configuration**: Multi-region deployment support
3. **Resource Group Labeling**: Organized log classification
4. **VM Instance Identification**: Unique instance tracking

## Best Practices

1. **Regular Updates**: Keep Alloy and configuration updated
2. **Credential Rotation**: Regularly rotate API keys
3. **Alert Tuning**: Adjust thresholds based on environment
4. **Backup Configuration**: Version control all configuration files
5. **Documentation**: Maintain runbook links in alerts

## Support and Contact

For issues and questions:
1. Check Grafana Alloy documentation
2. Review Grafana Cloud Loki documentation
3. Monitor service logs and system metrics
4. Contact system administrators for Azure-specific issues

---

**Version**: 1.0  
**Last Updated**: 2024-08-25  
**Supported Platforms**: RHEL 8+, Azure VMs