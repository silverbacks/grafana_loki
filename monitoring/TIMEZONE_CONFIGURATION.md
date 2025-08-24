# Timezone Configuration for Multi-Location Servers

## Overview

When you have servers in different geographic locations, proper timezone handling is crucial for accurate log analysis and alerting. This guide explains how `stage.timestamp` works and the best practices for different scenarios.

## Understanding the Problem

### RHEL `/var/log/messages` Format

RHEL systems log timestamps in this format:
```
Dec 25 15:30:45 hostname kernel: some message
```

**Important**: This timestamp is in the **server's local timezone**, not UTC!

### The Issue with `location = "UTC"`

If you force `location = "UTC"` on servers in different timezones:

| Server Location | Local Log Time | Interpreted as UTC | Actual UTC Time | Error |
|----------------|---------------|-------------------|-----------------|-------|
| New York (EST) | Dec 25 15:30:45 | 15:30 UTC | 20:30 UTC | -5 hours |
| London (GMT) | Dec 25 15:30:45 | 15:30 UTC | 15:30 UTC | Correct |
| Tokyo (JST) | Dec 25 15:30:45 | 15:30 UTC | 06:30 UTC | +9 hours |

This creates **incorrect timestamps** in Grafana and alerts may trigger at wrong times!

## Recommended Configuration

### Option 1: Local Timezone (Recommended)

```alloy
stage.timestamp {
  source = "timestamp"
  format = "Jan _2 15:04:05"
  location = "Local"  // Use server's system timezone
}
```

**Benefits:**
- ✅ Automatically uses each server's configured timezone
- ✅ Works correctly for servers in different locations
- ✅ No manual configuration needed per server
- ✅ Timestamps are accurate in Grafana

**How it works:**
1. Server in New York has timezone set to `America/New_York`
2. Log timestamp "Dec 25 15:30:45" is correctly interpreted as EST
3. Alloy converts to UTC before sending to Loki
4. Grafana displays in your chosen timezone

### Option 2: Specific Timezone (Advanced)

For servers that might have incorrect system timezone:

```alloy
stage.timestamp {
  source = "timestamp"
  format = "Jan _2 15:04:05"
  location = "America/New_York"  // Force specific timezone
}
```

**Use cases:**
- Server timezone is incorrectly configured
- Standardizing across regions
- Special compliance requirements

### Option 3: UTC Only (Special Cases)

```alloy
stage.timestamp {
  source = "timestamp"
  format = "Jan _2 15:04:05"
  location = "UTC"  // Only if logs are already in UTC
}
```

**Only use if:**
- You've configured all servers to log in UTC
- `/var/log/messages` timestamps are already in UTC format
- All servers have been set to UTC timezone

## Configuration Examples

### Per-Environment Configuration

#### Production Servers (Global)
```bash
# /etc/default/alloy
SERVER_TIMEZONE=Local  # Let each server use its local timezone
```

#### Development Servers (Standardized)
```bash
# /etc/default/alloy  
SERVER_TIMEZONE=UTC  # Force UTC for consistency in dev
```

#### Regional Deployments
```bash
# US East servers
SERVER_TIMEZONE=America/New_York

# UK servers  
SERVER_TIMEZONE=Europe/London

# Japan servers
SERVER_TIMEZONE=Asia/Tokyo
```

### Dynamic Configuration

You can also use environment variables:

```alloy
stage.timestamp {
  source = "timestamp"
  format = "Jan _2 15:04:05"
  location = env("SERVER_TIMEZONE")  // From environment variable
}
```

## Verification and Testing

### Check Server Timezone

```bash
# Check current timezone
timedatectl status

# Check timezone setting
cat /etc/timezone

# Check if logs are in local time
tail -n 5 /var/log/messages
```

### Test Timestamp Parsing

```bash
# Generate test log entry
logger -p kern.err "Test message for timezone verification"

# Check in Grafana with query:
{job="system-logs"} |= "Test message for timezone"
```

### Validate in Grafana

1. Generate log entry with known time
2. Check timestamp in Grafana Explore
3. Verify it matches your expected UTC time

## Troubleshooting

### Wrong Timestamps in Grafana

**Symptoms:**
- Alerts trigger at wrong times
- Log entries appear hours off
- Timeline doesn't match actual events

**Solutions:**

1. **Check server timezone:**
   ```bash
   timedatectl status
   ```

2. **Verify Alloy configuration:**
   ```bash
   sudo journalctl -u alloy -f | grep timestamp
   ```

3. **Test with known timestamp:**
   ```bash
   logger "Test at $(date)"
   ```

### Servers in Different Timezones

**Problem:** Mixed timezone servers causing confusion

**Solution:** Use `location = "Local"` and add timezone labels:

```alloy
stage.labels {
  values = {
    server_timezone = env("TZ"),  // Add timezone info to logs
  }
}
```

### DST (Daylight Saving Time) Issues

**Problem:** Timestamps shift during DST transitions

**Solutions:**
1. Use `location = "Local"` - handles DST automatically
2. Consider UTC for business-critical systems
3. Monitor around DST transition dates

## Best Practices

### 1. Consistent Server Configuration

```bash
# Set all servers to UTC (optional but recommended)
sudo timedatectl set-timezone UTC

# Or ensure consistent timezone per region
sudo timedatectl set-timezone America/New_York
```

### 2. Add Timezone Labels

```alloy
stage.labels {
  values = {
    server_timezone = env("TZ"),
    server_region = env("AZURE_REGION"),
  }
}
```

### 3. Monitor Timezone Configuration

Create alerts for timezone inconsistencies:

```yaml
# Alert on mixed timezones (if not expected)
- alert: InconsistentTimezones
  expr: 'count by (server_timezone) (count_over_time({job="system-logs"}[1h])) > 1'
  for: 5m
  annotations:
    summary: "Multiple timezones detected in logs"
```

### 4. Documentation

Document your timezone strategy:
- Which timezone each region uses
- Whether servers are set to local time or UTC
- How to handle DST transitions

## Common Scenarios

### Scenario 1: Global Infrastructure
- **Multiple regions:** US, Europe, Asia
- **Recommendation:** `location = "Local"`
- **Server setup:** Each region uses local timezone

### Scenario 2: Development Environment
- **Mixed developer locations**
- **Recommendation:** `location = "UTC"`
- **Server setup:** All servers set to UTC

### Scenario 3: Compliance Requirements
- **Audit trails need specific timezone**
- **Recommendation:** Force specific timezone
- **Server setup:** Timezone as required by regulation

### Scenario 4: Cloud Migration
- **Moving from different timezone systems**
- **Recommendation:** Standardize on UTC
- **Server setup:** Migrate all to UTC during transition

## Cloud-Specific Considerations

### Cloud VM Timezone

Cloud VMs often default to UTC, but you can change:

```bash
# Check VM timezone
timedatectl status

# Set to local timezone if needed
sudo timedatectl set-timezone America/New_York
```

---

**Key Takeaway**: Use `location = "Local"` for most multi-location deployments, ensure server timezones are correctly configured, and test timestamp accuracy in Grafana.