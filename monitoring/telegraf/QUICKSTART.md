# Quick Setup Guide - Telegraf Azure Scheduled Events Monitoring

## 🚀 Quick Start (5 minutes)

### 1. Prerequisites Check
```bash
# Verify you're on Azure VM
curl -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01"

# Confirm RHEL 8+
cat /etc/redhat-release
```

### 2. Get Grafana Cloud Credentials
1. Go to [Grafana Cloud](https://grafana.com/auth/sign-up)
2. Navigate to: **Prometheus** → **Configuration** → **Remote Write**
3. Copy your endpoint URL and generate API key

### 3. Install
```bash
cd monitoring/telegraf
sudo ./scripts/install-telegraf-azure.sh
```

### 4. Configure
```bash
sudo nano /etc/default/telegraf
```
Update these values:
```bash
PROMETHEUS_REMOTE_WRITE_URL=https://prometheus-prod-13-prod-us-east-0.grafana.net/api/prom/push
PROMETHEUS_USERNAME=your_instance_id
PROMETHEUS_PASSWORD=your_api_key
```

### 5. Start & Verify
```bash
sudo systemctl restart telegraf
sudo ./scripts/validate-telegraf-config.sh
curl http://localhost:9273/metrics | grep azure
```

### 6. Import Dashboard
1. Go to Grafana Cloud → **Dashboards** → **Import**
2. Upload: `monitoring/grafana/dashboards/azure-scheduled-events.json`
3. Select your Prometheus data source

### 7. Setup Alerts
1. Go to **Alerting** → **Alert Rules** → **Import**
2. Use: `monitoring/grafana/alerts/azure-scheduled-events-alerts.yaml`
3. Configure notification channels

## 🔧 Key Files

| File | Purpose |
|------|---------|
| `telegraf.conf` | Main configuration |
| `conf.d/azure_scheduled_events.conf` | Azure events input |
| `conf.d/prometheus_output.conf` | Grafana Cloud output |
| `telegraf.env` | Environment variables |
| `scripts/install-telegraf-azure.sh` | Automated installer |
| `scripts/validate-telegraf-config.sh` | Health checker |

## 📊 What You'll Monitor

- **VM Preemption Events** (Critical)
- **VM Freeze/Reboot/Redeploy** (High Priority)
- **Azure IMDS Health** (Service monitoring)
- **VM Metadata Changes** (Informational)

## 🚨 Alert Levels

| Severity | Events | Response Time |
|----------|--------|---------------|
| **Critical** | Preempt, Freeze | Immediate |
| **High** | Reboot, Redeploy | 30 seconds |
| **Warning** | Multiple events, Agent issues | 2 minutes |

## 🛠️ Troubleshooting

```bash
# Check service
sudo systemctl status telegraf

# View logs
sudo journalctl -u telegraf -f

# Test configuration
telegraf --config /etc/telegraf/telegraf.conf --test

# Validate setup
sudo ./scripts/validate-telegraf-config.sh
```

## 🔗 Quick Links

- [Full Documentation](README.md)
- [Azure Scheduled Events API](https://docs.microsoft.com/en-us/azure/virtual-machines/scheduled-events)
- [Grafana Cloud Setup](https://grafana.com/docs/grafana-cloud/)

---
**Need Help?** Check the detailed `README.md` or run the validation script for diagnostics.