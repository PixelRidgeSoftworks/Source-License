# Monitoring Configuration Guide

## Overview

The monitoring service is **optional** but **strongly recommended** for production deployments. The Source-License application includes built-in monitoring capabilities that work with or without external services.

## Built-in Monitoring (Always Available)

### 1. Health Check Endpoints ✅ **INCLUDED**
These work without any external services:

```bash
# Basic health check
curl https://yourdomain.com/health

# Comprehensive readiness check
curl https://yourdomain.com/ready
```

### 2. Built-in Logging System ✅ **INCLUDED**
The application includes comprehensive logging:

- **Structured JSON logging** for production
- **Security event logging** with severity levels
- **Payment transaction logging** (PII-safe)
- **API request/response logging**
- **Error logging** with stack traces

### 3. Local Log Files ✅ **INCLUDED**
All logs are written to local files:

```
/var/www/source-license/log/
├── application.log
├── security.log
├── payment.log
├── error.log
└── puma.stdout.log
```

## Deployment Options

### Option 1: Minimal Production (No External Monitoring)

**What's Included:**
- Built-in health checks
- Local file logging
- System logs via journalctl
- Basic alerting via log monitoring

**Configuration:**
```bash
# .env configuration (minimal)
LOG_LEVEL=info
LOG_FORMAT=json
# Leave these empty/unset:
# ERROR_TRACKING_DSN=
# SECURITY_WEBHOOK_URL=
```

**Monitoring Commands:**
```bash
# Check application health
curl https://yourdomain.com/health

# View real-time logs
sudo journalctl -u source-license -f

# Check error logs
tail -f /var/www/source-license/log/error.log
```

### Option 2: Enhanced Production (With External Monitoring)

**What's Added:**
- External error tracking (Sentry, Bugsnag)
- Security alert webhooks (Slack, Teams)
- Performance monitoring (New Relic, DataDog)
- Uptime monitoring (Pingdom, StatusCake)

**Configuration:**
```bash
# .env configuration (enhanced)
LOG_LEVEL=info
LOG_FORMAT=json
ERROR_TRACKING_DSN=https://your-sentry-dsn@sentry.io/project
SECURITY_WEBHOOK_URL=https://hooks.slack.com/your-webhook
```

## Setting Up Different Monitoring Levels

### Level 1: Basic (Free/Built-in)

**Requirements:** None - all included
**Cost:** $0
**Setup Time:** 0 minutes

```bash
# Already configured! Just check health:
curl https://yourdomain.com/health
```

### Level 2: Basic + Alerts (Free)

**Requirements:** Slack webhook or email
**Cost:** $0
**Setup Time:** 15 minutes

1. **Create Slack Webhook:**
   ```bash
   # Go to https://api.slack.com/apps
   # Create new app > Incoming Webhooks
   # Copy webhook URL to .env:
   SECURITY_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
   ```

2. **Test Alerting:**
   ```bash
   # Trigger a security event to test alerts
   curl -X POST https://yourdomain.com/admin/login \
     -d "email=invalid&password=test"
   ```

### Level 3: Professional Monitoring

**Requirements:** Monitoring service account
**Cost:** $10-50/month
**Setup Time:** 30-60 minutes

#### Sentry Error Tracking (Recommended)
```bash
# 1. Sign up at https://sentry.io (free tier available)
# 2. Create new project and select "Ruby" platform
# 3. Copy the DSN from project settings
# 4. Add DSN to .env:
ERROR_TRACKING_DSN=https://PUBLIC_KEY@SENTRY_PROJECT_ID.ingest.sentry.io/PROJECT_ID

# 5. Restart application
sudo systemctl restart source-license

# 6. Test error tracking
curl -X POST https://yourdomain.com/admin/login -d "email=test&password=wrong"
```

#### UptimeRobot Monitoring (Free)
```bash
# 1. Sign up at https://uptimerobot.com (free tier)
# 2. Add monitor for: https://yourdomain.com/health
# 3. Configure email/SMS alerts
```

### Level 4: Enterprise Monitoring

**Requirements:** Enterprise monitoring platform
**Cost:** $100-500/month
**Setup Time:** 2-4 hours

Options include:
- **New Relic**: Full APM monitoring
- **DataDog**: Infrastructure + application monitoring
- **Splunk**: Enterprise log management
- **ELK Stack**: Self-hosted log aggregation

## Configuration Examples

### Minimal .env (No External Services)
```bash
# Basic configuration - no external monitoring required
APP_ENV=production
APP_SECRET=your_strong_secret_here
LOG_LEVEL=info
LOG_FORMAT=json

# Database, payment, email configs...
# (monitoring fields left empty/unset)
```

### Enhanced .env (With Monitoring)
```bash
# Enhanced configuration with monitoring
APP_ENV=production
APP_SECRET=your_strong_secret_here
LOG_LEVEL=info
LOG_FORMAT=json

# External monitoring (optional)
ERROR_TRACKING_DSN=https://your-sentry-dsn@sentry.io/project
SECURITY_WEBHOOK_URL=https://hooks.slack.com/your-webhook

# Database, payment, email configs...
```

## Built-in Monitoring Commands

### Health Checks
```bash
# Application health
curl https://yourdomain.com/health

# Detailed readiness check
curl https://yourdomain.com/ready

# Check from inside server
curl http://localhost:4567/health
```

### Log Monitoring
```bash
# Real-time application logs
sudo journalctl -u source-license -f

# Security events
grep "SECURITY_EVENT" /var/www/source-license/log/application.log

# Payment events
grep "payment_event" /var/www/source-license/log/application.log

# Error monitoring
tail -f /var/www/source-license/log/error.log
```

### System Monitoring
```bash
# Service status
sudo systemctl status source-license

# Resource usage
htop
df -h
free -h

# Network connections
netstat -tlnp | grep 4567
```

## Alert Configuration (Without External Services)

### Basic Email Alerts
Create `/usr/local/bin/basic-monitor`:

```bash
#!/bin/bash
HEALTH_URL="https://yourdomain.com/health"
EMAIL="admin@yourdomain.com"

if ! curl -f -s $HEALTH_URL > /dev/null; then
    echo "Source License application is down!" | \
    mail -s "🚨 Application Down Alert" $EMAIL
fi
```

Add to crontab:
```bash
# Check every 5 minutes
*/5 * * * * /usr/local/bin/basic-monitor
```

### Log-based Alerts
Monitor logs for critical events:

```bash
#!/bin/bash
# /usr/local/bin/log-monitor
LOG_FILE="/var/www/source-license/log/application.log"
ALERT_EMAIL="admin@yourdomain.com"

# Check for critical security events in last 5 minutes
if grep -q "security.*critical" $LOG_FILE; then
    echo "Critical security event detected" | \
    mail -s "🚨 Security Alert" $ALERT_EMAIL
fi
```

## Monitoring Without External Dependencies

### File-based Health Monitoring
```bash
# Create health check script
#!/bin/bash
HEALTH_FILE="/tmp/source-license-health"
HEALTH_URL="http://localhost:4567/health"

# Check health and write to file
if curl -f -s $HEALTH_URL > /dev/null; then
    echo "healthy" > $HEALTH_FILE
else
    echo "unhealthy" > $HEALTH_FILE
fi
```

### Simple Dashboard
Create a simple status page:

```html
<!DOCTYPE html>
<html>
<head>
    <title>Source License Status</title>
    <meta http-equiv="refresh" content="30">
</head>
<body>
    <h1>Application Status</h1>
    <div id="status">
        <!-- Auto-refreshed status -->
    </div>
    <script>
        fetch('/health')
            .then(response => response.json())
            .then(data => {
                document.getElementById('status').innerHTML = 
                    `<p>Status: ${data.status}</p>
                     <p>Database: ${data.database}</p>
                     <p>Last Check: ${new Date()}</p>`;
            });
    </script>
</body>
</html>
```

## Recommendation

### For Small Deployments (1-10 users)
- **Use built-in monitoring only**
- **Cost:** $0
- **Setup:** Included by default

### For Medium Deployments (10-100 users)
- **Add Slack alerts and Sentry free tier**
- **Cost:** $0
- **Setup:** 30 minutes

### For Large Deployments (100+ users)
- **Add professional monitoring service**
- **Cost:** $20-100/month
- **Setup:** 1-2 hours

## Conclusion

**The monitoring service is completely optional.** The Source-License application includes comprehensive built-in monitoring that provides:

✅ **Health checks** for load balancers
✅ **Structured logging** for debugging
✅ **Security event tracking** for compliance
✅ **Error logging** for troubleshooting
✅ **Performance metrics** for optimization

You can deploy to production immediately using only the built-in monitoring, then add external services later as your needs grow.
