# Enhanced NFS Monitoring with Server Detection

## Overview

The NFS monitoring has been enhanced to capture and track the specific NFS servers experiencing issues. This provides more detailed information for troubleshooting and allows for server-specific alerting.

## Enhanced Features

### 1. NFS Server Detection

The Grafana Alloy configuration now extracts NFS server information from log messages using multiple regex patterns:

#### Server Not Responding
- Pattern: `(?i).*server\s+([0-9a-zA-Z.-]+).*not responding.*`
- Captures: Server hostname/IP when "server X not responding" messages appear
- Label: `nfs_server=$1`, `issue_type=server_not_responding`

#### NFS Timeout Issues  
- Pattern: `(?i).*nfs.*(?:server\s+([0-9a-zA-Z.-]+)|([0-9a-zA-Z.-]+)\s*:).*timeout.*`
- Captures: Server from both "server hostname" and "hostname:" formats
- Label: `nfs_server=$1$2`, `issue_type=timeout`

#### Mount Failures
- Pattern: `(?i).*mount.*([0-9a-zA-Z.-]+):(/\S+).*(?:failed|error|timeout).*`
- Captures: Both NFS server and mount point from mount commands
- Labels: `nfs_server=$1`, `mount_point=$2`, `issue_type=mount_failure`

#### RPC Timeouts
- Pattern: `(?i).*rpc.*(?:server\s+([0-9a-zA-Z.-]+)|([0-9a-zA-Z.-]+)\s*:).*(?:timeout|not responding).*`
- Captures: Server information from RPC-related messages
- Label: `nfs_server=$1$2`, `issue_type=rpc_timeout`

#### General NFS Issues
- Pattern: `(?i).*(nfs.*(?:error|failed|failure|stale|hung)|portmap.*(?:error|failed)).*`
- Captures: General NFS problems without specific server info
- Label: `nfs_server=unknown`, `issue_type=general_nfs_error`

### 2. Enhanced Alert Rules

#### Updated NFSNotResponding Alert
```yaml
- alert: NFSNotResponding
  expr: 'count_over_time({job="system-logs", event_type="nfs_issue"}[10m]) > 0'
  for: 1m
  labels:
    severity: critical
    service: nfs
    alert_type: nfs_failure
  annotations:
    summary: "NFS issues detected on {{ $labels.hostname }}"
    description: |
      NFS server {{ $labels.nfs_server | default "unknown" }} is experiencing issues on {{ $labels.hostname }}.
      Issue type: {{ $labels.issue_type | default "general" }}
      Mount point: {{ $labels.mount_point | default "not specified" }}
      Check NFS mounts and network connectivity.
    nfs_server: "{{ $labels.nfs_server | default \"unknown\" }}"
    mount_point: "{{ $labels.mount_point | default \"not specified\" }}"
```

### 3. Enhanced Dashboard Panels

#### NFS Issues by Server Panel
- **Type**: Stat panel
- **Query**: `sum by (nfs_server) (count_over_time({job="system-logs", event_type="nfs_issue"}[5m]))`
- **Purpose**: Shows which NFS servers are experiencing the most issues
- **Thresholds**: Green (0), Yellow (1+), Red (5+)

#### NFS Issues Timeline Panel
- **Type**: Logs panel
- **Query**: `{job="system-logs", event_type="nfs_issue"} | line_format "{{.timestamp}} [{{.hostname}}] Server: {{.nfs_server}} Issue: {{.issue_type}} - {{.message}}"`
- **Purpose**: Detailed timeline showing server and issue type information

#### NFS Server Template Variable
- **Variable**: `$nfs_server`
- **Query**: `label_values({job="system-logs", event_type="nfs_issue"}, nfs_server)`
- **Purpose**: Filter dashboard by specific NFS server

### 4. Useful LogQL Queries

#### List All NFS Servers with Issues
```logql
sum by (nfs_server) (count_over_time({job="system-logs", event_type="nfs_issue"}[1h]))
```

#### Issues by Issue Type
```logql
sum by (issue_type) (count_over_time({job="system-logs", event_type="nfs_issue"}[1h]))
```

#### Mount Failures with Server and Path
```logql
{job="system-logs", event_type="nfs_issue", issue_type="mount_failure"} 
| line_format "Server: {{.nfs_server}} Mount: {{.mount_point}} - {{.message}}"
```

#### Top 5 Problematic NFS Servers
```logql
topk(5, sum by (nfs_server) (count_over_time({job="system-logs", event_type="nfs_issue"}[24h])))
```

## Example Log Messages and Extracted Data

### Server Not Responding
**Log**: `kernel: nfs: server fileserver01.company.com not responding, still trying`
**Extracted**:
- `nfs_server`: `fileserver01.company.com`
- `issue_type`: `server_not_responding`
- `severity`: `critical`

### Mount Failure
**Log**: `mount.nfs: mount to NFS server '192.168.1.100' failed: timed out`
**Extracted**:
- `nfs_server`: `192.168.1.100`
- `issue_type`: `mount_failure`
- `severity`: `critical`

### RPC Timeout
**Log**: `rpc.statd: server nfs-server.local timeout (RPC error 5)`
**Extracted**:
- `nfs_server`: `nfs-server.local`
- `issue_type`: `rpc_timeout`
- `severity`: `critical`

## Benefits

1. **Server-Specific Alerting**: Know exactly which NFS server is having issues
2. **Faster Troubleshooting**: Immediately identify the problematic server
3. **Trend Analysis**: Track which servers have frequent issues
4. **Capacity Planning**: Identify overloaded NFS servers
5. **SLA Monitoring**: Monitor specific server availability

## Alert Integration

The enhanced alerts now include:
- **NFS Server Name** in alert descriptions
- **Issue Type** classification
- **Mount Point** information (when available)
- **Structured annotations** for automation integration

This allows downstream systems to:
- Route alerts to server-specific teams
- Automatically check server status
- Create tickets with specific server information
- Trigger server-specific remediation scripts

## Grafana Cloud Configuration

When setting up in Grafana Cloud, use these enhanced queries in your alert rules to get the full benefit of server-specific information. The alerts will automatically include the NFS server details in the notification messages, making it easier to respond quickly to NFS issues.