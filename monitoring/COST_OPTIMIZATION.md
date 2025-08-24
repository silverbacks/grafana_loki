# Cost Optimization Guide for Grafana Loki Monitoring

## Overview

This configuration is designed to minimize Grafana Cloud Loki costs while maintaining comprehensive alerting for critical system events. By filtering out non-critical log messages, you can achieve significant cost savings.

## Log Volume Reduction

### Default Filtering Behavior

The Alloy configuration includes a `stage.keep` filter that only forwards logs that match critical event patterns:

```alloy
stage.keep {
  expression = ".+"  // Keep if event_type has any value
  source = "event_type"  // Check the event_type label
}
```

### What Gets Kept vs. Dropped

#### ✅ **KEPT (Sent to Loki)**
- System errors (segfaults, kernel oops, fatal errors)
- NFS issues (timeouts, server not responding)
- Puppet agent failures
- Filesystem read-only errors
- Kernel panics and OOM killer
- Service failures (systemd units)
- Security issues (authentication failures)
- Storage issues (disk full, I/O errors)

#### ❌ **DROPPED (Not sent to Loki)**
- Normal service startups
- Routine log rotations
- Regular cron job messages
- Network interface status changes
- Successful authentication logs
- Normal systemd service operations
- Informational messages
- Debug messages

## Cost Impact Examples

### Typical RHEL 8+ System

**Without Filtering:**
- Average `/var/log/messages` size: 50-500 MB/day
- Log entries: 50,000-500,000/day
- Monthly volume: 1.5-15 GB per server

**With Filtering:**
- Critical events only: 1-10 MB/day
- Log entries: 100-1,000/day
- Monthly volume: 30-300 MB per server

**Savings: 90-95% reduction in log volume**

### Cost Comparison (Example pricing)

Based on typical Grafana Cloud pricing:

| Scenario | Daily Volume | Monthly Volume | Est. Monthly Cost |
|----------|-------------|----------------|-------------------|
| No Filtering | 200 MB/day | 6 GB | $12-18/server |
| With Filtering | 5 MB/day | 150 MB | $0.30-0.50/server |
| **Savings** | **97.5%** | **97.5%** | **~$12-17/server** |

*Note: Costs are estimates and vary by Grafana Cloud tier and region*

## Configuration Options

### Enable Cost Optimization (Default)

```bash
# /etc/default/alloy
ALLOY_DROP_NON_CRITICAL=true
```

This enables the keep stage that only forwards critical events.

### Disable for Debugging

```bash
# /etc/default/alloy
ALLOY_DROP_NON_CRITICAL=false
```

To temporarily keep all messages for debugging:

1. Edit `/etc/default/alloy`
2. Set `ALLOY_DROP_NON_CRITICAL=false`
3. Restart: `sudo systemctl restart alloy`
4. Debug the issue
5. Re-enable: Set back to `true` and restart

### Custom Event Types

To add new event types that should be kept, modify the Alloy config:

```alloy
// Add new critical event filter
stage.match {
  selector = "{job=\"system-logs\"}"
  
  stage.regex {
    expression = "(?i).*your_new_pattern.*"
  }
  
  stage.labels {
    values = {
      severity = "warning",
      event_type = "custom_event",
    }
  }
}
```

## Monitoring Costs

### Track Log Volume in Grafana

```logql
# Bytes ingested per day by server
sum by (vm_name) (
  bytes_over_time({job="system-logs"}[24h])
)

# Count of log lines by event type
sum by (event_type) (
  count_over_time({job="system-logs"}[24h])
)

# Average message size
avg(
  bytes_over_time({job="system-logs"}[24h]) /
  count_over_time({job="system-logs"}[24h])
)
```

### Grafana Cloud Usage Dashboard

Create alerts for unexpected volume increases:

```yaml
# Alert on high log volume (potential cost issue)
- alert: HighLogVolume
  expr: 'sum(bytes_over_time({job="system-logs"}[1h])) > 50000000'  # 50MB/hour
  for: 5m
  labels:
    severity: warning
    alert_type: cost_optimization
  annotations:
    summary: "High log volume detected"
    description: "Log volume exceeded 50MB/hour, check for configuration issues"
```

## Alternative Approaches

### 1. Sampling

Instead of dropping, you could sample non-critical logs:

```alloy
// Sample 1% of non-critical messages
stage.sampling {
  rate = 0.01  // Keep 1%
}
```

### 2. Separate Endpoints

Send critical events to Loki and non-critical to cheaper storage:

```alloy
// Different endpoints for different severities
loki.write "critical_events" {
  endpoint {
    url = env("LOKI_ENDPOINT")
  }
}

loki.write "all_events" {
  endpoint {
    url = env("CHEAPER_STORAGE_ENDPOINT")
  }
}
```

### 3. Retention-Based Strategy

Keep all logs but with different retention:

- Critical events: 90 days
- Warning events: 30 days  
- Info events: 7 days

## Best Practices

1. **Start with filtering enabled** (default configuration)
2. **Monitor alert effectiveness** - ensure you're not missing critical events
3. **Review monthly costs** in Grafana Cloud billing
4. **Test without filtering** in development environments
5. **Document any custom event types** you add
6. **Set up cost alerts** to detect volume spikes
7. **Regular review** of what's being filtered vs. kept

## Troubleshooting

### Missing Expected Alerts

If you expect an alert but don't see it:

1. Temporarily disable filtering: `ALLOY_DROP_NON_CRITICAL=false`
2. Check if the log pattern exists in raw logs
3. Verify regex patterns match your log format
4. Add custom patterns if needed
5. Re-enable filtering after testing

### High Costs Despite Filtering

1. Check log volume metrics in Grafana
2. Look for new error patterns not covered by filters
3. Verify keep stage is working: `journalctl -u alloy -f`
4. Review Grafana Cloud usage dashboard

### Configuration Validation

```bash
# Test configuration syntax
sudo /usr/local/bin/alloy fmt /etc/alloy/config.alloy

# Check service status
sudo systemctl status alloy

# Monitor real-time filtering
sudo journalctl -u alloy -f | grep -i "keep\|drop"
```

---

**Remember**: The goal is 95%+ cost reduction while maintaining 100% alerting effectiveness for critical system events.