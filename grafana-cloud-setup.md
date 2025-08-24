# Grafana Cloud Loki Configuration Guide

## Overview

This guide explains how to configure Grafana Alloy to send logs to Grafana Cloud (Grafana Labs) managed Loki service and set up alert rules in the cloud.

## Prerequisites

1. **Grafana Cloud Account**: Sign up at https://grafana.com/products/cloud/
2. **Loki Data Source**: Configured in your Grafana Cloud instance
3. **API Key**: With appropriate permissions for logs and alerting

## Getting Grafana Cloud Credentials

### 1. Access Your Grafana Cloud Portal

1. Log into https://grafana.com/
2. Go to your organization's stack
3. Navigate to **Security** → **Access Policies** or **API Keys**

### 2. Create API Key

Create an API key with the following scopes:
- `logs:write` - To send logs to Loki
- `alerts:write` - To create alert rules
- `metrics:write` - Optional, for metrics

### 3. Get Your Endpoints

Your endpoints will be in this format:
- **Loki Endpoint**: `https://logs-prod-{region}.grafana.net/loki/api/v1/push`
- **User ID**: Your instance ID (usually a number)

Example endpoints by region:
- US Central: `logs-prod-us-central1.grafana.net`
- EU West: `logs-prod-eu-west-0.grafana.net`
- Asia Pacific: `logs-prod-ap-southeast-0.grafana.net`

## Configuration Files

### Environment Configuration (/etc/default/alloy)

```bash
# Grafana Cloud Loki Configuration
# Replace with your actual values
LOKI_ENDPOINT=https://logs-prod-us-central1.grafana.net/loki/api/v1/push
LOKI_USERNAME=123456  # Your Grafana Cloud instance ID
LOKI_PASSWORD=glc_your_api_key_here

# Environment Configuration
ENVIRONMENT=production
AZURE_REGION=eastus
AZURE_RESOURCE_GROUP=your-resource-group

# Optional: Custom labels
CUSTOM_TEAM_LABEL=infrastructure
CUSTOM_ENVIRONMENT_LABEL=azure-rhel
```

## Setting Up Alert Rules in Grafana Cloud

### 1. Access Alerting

1. Log into your Grafana Cloud instance
2. Navigate to **Alerting** → **Alert Rules**
3. Click **New Rule**

### 2. Create Alert Rules

For each alert, use these configurations:

#### Filesystem Read-Only Alert

```yaml
Rule Name: FilesystemReadOnly
Data Source: Loki (your data source)
Query: count_over_time({job="system-logs", event_type="filesystem_readonly"}[5m]) > 0
Evaluation: Every 10s for 0s
Labels:
  severity: critical
  service: filesystem
  alert_type: readonly_filesystem
Annotations:
  summary: Filesystem mounted read-only on {{ $labels.hostname }}
  description: CRITICAL: Filesystem has been remounted read-only on {{ $labels.hostname }}
```

#### NFS Not Responding Alert

```yaml
Rule Name: NFSNotResponding
Data Source: Loki
Query: count_over_time({job="system-logs", event_type="nfs_issue"}[10m]) > 0
Evaluation: Every 30s for 1m
Labels:
  severity: critical
  service: nfs
  alert_type: nfs_failure
Annotations:
  summary: NFS issues detected on {{ $labels.hostname }}
  description: |
    NFS server {{ $labels.nfs_server | default "unknown" }} is experiencing issues on {{ $labels.hostname }}.
    Issue type: {{ $labels.issue_type | default "general" }}
    Mount point: {{ $labels.mount_point | default "not specified" }}
    Check NFS mounts and network connectivity.
```

#### Puppet Agent Failure Alert

```yaml
Rule Name: PuppetAgentFailure
Data Source: Loki
Query: count_over_time({job="system-logs", event_type="puppet_failure"}[30m]) > 2
Evaluation: Every 1m for 5m
Labels:
  severity: warning
  service: puppet
  alert_type: puppet_failure
Annotations:
  summary: Puppet agent failures on {{ $labels.hostname }}
  description: {{ $labels.hostname }} has puppet failures
```

#### System Errors High Alert

```yaml
Rule Name: SystemErrorsHigh
Data Source: Loki
Query: count_over_time({job="system-logs", event_type="system_error"}[5m]) > 5
Evaluation: Every 30s for 2m
Labels:
  severity: critical
  service: system
  alert_type: system_error
Annotations:
  summary: High number of system errors on {{ $labels.hostname }}
  description: {{ $labels.hostname }} has {{ $value }} system errors
```

#### Unforeseen Errors Alert

```yaml
Rule Name: UnforeseenSystemErrors
Data Source: Loki
Query: count_over_time({job="system-logs"} |~ "(?i).*(unexpected|unforeseen|unknown.*error|fatal.*error|critical.*error|emergency).*"[10m]) > 1
Evaluation: Every 1m for 3m
Labels:
  severity: warning
  service: system
  alert_type: unforeseen_error
Annotations:
  summary: Unforeseen system errors on {{ $labels.hostname }}
  description: {{ $value }} unforeseen errors detected on {{ $labels.hostname }}
```

### 3. Configure Notification Policies

1. Go to **Alerting** → **Notification Policies**
2. Create policies based on labels:

```yaml
# Critical alerts - immediate notification
- matchers:
    - severity = critical
  group_wait: 0s
  group_interval: 5m
  repeat_interval: 12h
  receiver: critical-alerts

# Warning alerts - grouped notification
- matchers:
    - severity = warning
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 24h
  receiver: warning-alerts
```

### 4. Set Up Contact Points

1. Go to **Alerting** → **Contact Points**
2. Create contact points for different alert types:

#### Slack Integration
```yaml
Name: critical-alerts
Type: Slack
Webhook URL: your-slack-webhook-url
Channel: #alerts-critical
Title: 🚨 Critical Alert: {{ .GroupLabels.alertname }}
Message: |
  **{{ .GroupLabels.alertname }}**
  {{ range .Alerts }}
  - **Host**: {{ .Labels.hostname }}
  - **Description**: {{ .Annotations.description }}
  {{ end }}
```

#### Email Integration
```yaml
Name: warning-alerts
Type: Email
To: ops-team@company.com
Subject: ⚠️ Warning Alert: {{ .GroupLabels.alertname }}
Body: |
  Alert Details:
  {{ range .Alerts }}
  - Host: {{ .Labels.hostname }}
  - Summary: {{ .Annotations.summary }}
  - Description: {{ .Annotations.description }}
  {{ end }}
```

## LogQL Queries for Custom Dashboards

### Critical Events Overview
```logql
sum by (event_type) (count_over_time({job="system-logs", severity=~"critical|error"}[5m]))
```

### Error Rate by Host
```logql
sum by (hostname) (rate({job="system-logs", severity="error"}[5m]))
```

### NFS Issues Timeline
```logql
{job="system-logs", event_type="nfs_issue"} | line_format "{{.timestamp}} [{{.hostname}}] NFS Server: {{.nfs_server}} - {{.message}}"
```

### NFS Issues by Server
```logql
sum by (nfs_server) (count_over_time({job="system-logs", event_type="nfs_issue"}[5m]))
```

### NFS Mount Failures with Server Info
```logql
{job="system-logs", event_type="nfs_issue", issue_type="mount_failure"} | line_format "{{.timestamp}} Server: {{.nfs_server}} Mount: {{.mount_point}} - {{.message}}"
```

### Filesystem Events
```logql
{job="system-logs", event_type="filesystem_readonly"} | json | line_format "{{.timestamp}} {{.hostname}}: {{.message}}"
```

## Testing the Configuration

### 1. Verify Alloy Connection

```bash
# Check service status
sudo systemctl status alloy.service

# Check logs for connection
sudo journalctl -u alloy.service -f | grep -i loki
```

### 2. Generate Test Events

```bash
# Test error generation
logger -p kern.err "Test system error for monitoring"

# Test filesystem message
logger -p kern.crit "Test filesystem read-only message"

# Test NFS message
logger -p daemon.err "Test NFS server not responding"
```

### 3. Verify in Grafana Cloud

1. Go to **Explore** in Grafana Cloud
2. Select Loki data source
3. Run query: `{job="system-logs"}`
4. Check for your test messages

## Troubleshooting

### Common Issues

1. **No logs in Grafana Cloud**
   - Verify API key permissions
   - Check endpoint URL format
   - Review Alloy logs: `journalctl -u alloy.service`

2. **Authentication failures**
   - Confirm username (instance ID) is numeric
   - Verify API key hasn't expired
   - Check for special characters in password

3. **Rate limiting**
   - Reduce log volume or frequency
   - Contact Grafana Labs for limits increase

### Debug Commands

```bash
# Test connectivity to Grafana Cloud
curl -u "USERNAME:API_KEY" "https://logs-prod-us-central1.grafana.net/loki/api/v1/labels"

# Validate Alloy config
/usr/local/bin/alloy fmt /etc/alloy/config.alloy

# Check network connectivity
telnet logs-prod-us-central1.grafana.net 443
```

## Best Practices

1. **Security**
   - Store API keys securely
   - Use least-privilege access policies
   - Rotate keys regularly

2. **Performance**
   - Monitor ingestion rates
   - Use appropriate log retention
   - Filter noisy logs before sending

3. **Cost Management**
   - Monitor log volume in Grafana Cloud
   - Set up billing alerts
   - Use log sampling for high-volume applications

4. **Reliability**
   - Test alert rules regularly
   - Maintain backup notification channels
   - Document escalation procedures

---

**Note**: Replace all placeholder values (endpoints, API keys, usernames) with your actual Grafana Cloud credentials.