# Production Deployment Guide

## 🚀 Complete Production Deployment Checklist

This guide provides step-by-step instructions for deploying the Source-License application to production with enterprise-grade security and reliability.

## Prerequisites

### System Requirements
- **Operating System**: Linux (Ubuntu 20.04+ recommended), macOS, or Windows Server
- **Ruby**: Version 3.4.4 or higher
- **Database**: MySQL 8.0+ or PostgreSQL 13+
- **Web Server**: Nginx or Apache (recommended for reverse proxy)
- **SSL Certificate**: Valid TLS certificate for your domain
- **Memory**: Minimum 2GB RAM, 4GB+ recommended
- **Storage**: Minimum 10GB free space

### Infrastructure Components
- **Load Balancer** (optional)
- **CDN** (optional - for static assets)
- **Monitoring Service** (New Relic, DataDog, etc.)
- **Error Tracking** (Sentry, Bugsnag, etc.)
- **Backup Storage** (AWS S3, Google Cloud Storage, etc.)

## Phase 1: Environment Setup

### 1. Server Preparation

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y curl git build-essential libssl-dev zlib1g-dev \
  libyaml-dev libreadline-dev libncurses5-dev libffi-dev \
  libgdbm-dev nginx mysql-server redis-server

# Install Ruby 3.4.4 (using rbenv)
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
source ~/.bashrc

rbenv install 3.4.4
rbenv global 3.4.4
```

### 2. Database Setup

#### MySQL Configuration
```bash
# Secure MySQL installation
sudo mysql_secure_installation

# Create application database
sudo mysql -u root -p
```

```sql
CREATE DATABASE source_license CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'source_license'@'localhost' IDENTIFIED BY 'STRONG_PASSWORD_HERE';
GRANT ALL PRIVILEGES ON source_license.* TO 'source_license'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

#### PostgreSQL Configuration
```bash
# Switch to postgres user
sudo -u postgres psql

# Create database and user
CREATE DATABASE source_license;
CREATE USER source_license WITH PASSWORD 'STRONG_PASSWORD_HERE';
GRANT ALL PRIVILEGES ON DATABASE source_license TO source_license;
\q
```

### 3. Application Deployment

```bash
# Create application directory
sudo mkdir -p /var/www/source-license
sudo chown $USER:$USER /var/www/source-license

# Clone repository
cd /var/www/source-license
git clone https://github.com/your-username/source-license.git .

# Install dependencies
gem install bundler
bundle install --deployment --without development test

# Create environment file
cp .env.example .env
```

### 4. Environment Configuration

Edit `.env` file with production values:

```bash
# Application Settings
APP_ENV=production
APP_SECRET=GENERATE_STRONG_32_CHAR_SECRET_HERE
APP_HOST=yourdomain.com
APP_PORT=4567
APP_VERSION=1.0.0

# Security Settings
JWT_SECRET=GENERATE_STRONG_JWT_SECRET_HERE
SECURITY_WEBHOOK_URL=https://your-monitoring-service.com/webhook

# Production Configuration
ALLOWED_ORIGINS=https://yourdomain.com,https://www.yourdomain.com
FORCE_SSL=true
HSTS_MAX_AGE=31536000

# Database Configuration
DATABASE_ADAPTER=mysql
DATABASE_HOST=localhost
DATABASE_PORT=3306
DATABASE_NAME=source_license
DATABASE_USER=source_license
DATABASE_PASSWORD=YOUR_DATABASE_PASSWORD

# Admin Settings (Change immediately after first login)
ADMIN_EMAIL=admin@yourdomain.com
ADMIN_PASSWORD=TEMPORARY_STRONG_PASSWORD

# Payment Gateway Settings
STRIPE_PUBLISHABLE_KEY=pk_live_your_stripe_publishable_key
STRIPE_SECRET_KEY=sk_live_your_stripe_secret_key
STRIPE_WEBHOOK_SECRET=whsec_your_webhook_secret

# Email Configuration
SMTP_HOST=smtp.yourmailserver.com
SMTP_PORT=587
SMTP_USERNAME=noreply@yourdomain.com
SMTP_PASSWORD=your_email_password
SMTP_TLS=true

# Logging & Monitoring
LOG_LEVEL=info
LOG_FORMAT=json
ERROR_TRACKING_DSN=https://your-sentry-dsn@sentry.io/project

# Performance & Caching
REDIS_URL=redis://localhost:6379/0
ENABLE_CACHING=true
CACHE_TTL=3600
```

### 5. SSL Certificate Setup

#### Using Let's Encrypt (Recommended)
```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx

# Obtain SSL certificate
sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com

# Test automatic renewal
sudo certbot renew --dry-run
```

### 6. Web Server Configuration

#### Nginx Configuration
Create `/etc/nginx/sites-available/source-license`:

```nginx
upstream source_license {
    server 127.0.0.1:4567 fail_timeout=0;
}

server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name yourdomain.com www.yourdomain.com;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;
    
    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";

    # Application Configuration
    root /var/www/source-license/public;
    client_max_body_size 10M;
    
    # Health Check Endpoints
    location /health {
        proxy_pass http://source_license;
        access_log off;
    }
    
    location /ready {
        proxy_pass http://source_license;
        access_log off;
    }

    # Static Assets
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # Application Proxy
    location / {
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $http_host;
        proxy_redirect off;
        proxy_pass http://source_license;
        
        # Timeouts
        proxy_connect_timeout 5s;
        proxy_send_timeout 10s;
        proxy_read_timeout 10s;
    }
}
```

Enable the site:
```bash
sudo ln -s /etc/nginx/sites-available/source-license /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

## Phase 2: Application Configuration

### 1. Database Migration
```bash
cd /var/www/source-license
bundle exec ruby lib/migrations.rb
```

### 2. Service Configuration

Create systemd service `/etc/systemd/system/source-license.service`:

```ini
[Unit]
Description=Source License Application
After=network.target mysql.service redis.service
Requires=mysql.service redis.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/var/www/source-license
Environment=RACK_ENV=production
ExecStart=/home/deploy/.rbenv/shims/bundle exec puma -C config/puma.rb
ExecReload=/bin/kill -USR1 $MAINPID
KillMode=mixed
Restart=on-failure
RestartSec=5
TimeoutStopSec=30

# Security settings
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ReadWritePaths=/var/www/source-license/tmp /var/www/source-license/log

[Install]
WantedBy=multi-user.target
```

Create Puma configuration `config/puma.rb`:

```ruby
#!/usr/bin/env puma

directory '/var/www/source-license'
rackup 'config.ru'

environment ENV.fetch('RACK_ENV') { 'production' }

# Bind to Unix socket for better performance
bind 'unix:///var/www/source-license/tmp/puma.sock'

# Workers and threads
workers ENV.fetch('WEB_CONCURRENCY') { 2 }
threads_count = ENV.fetch('RAILS_MAX_THREADS') { 5 }
threads threads_count, threads_count

# Preload application
preload_app!

# Logging
stdout_redirect '/var/www/source-license/log/puma.stdout.log',
                '/var/www/source-license/log/puma.stderr.log',
                true

# Process ID
pidfile '/var/www/source-license/tmp/puma.pid'
state_path '/var/www/source-license/tmp/puma.state'

# Graceful restart
on_restart do
  puts 'Refreshing Gemfile'
  ENV['BUNDLE_GEMFILE'] = '/var/www/source-license/Gemfile'
end

on_worker_boot do
  # Database connection per worker
  if defined?(ActiveRecord)
    ActiveRecord::Base.establish_connection
  end
end
```

### 3. File Permissions
```bash
sudo chown -R www-data:www-data /var/www/source-license
sudo chmod -R 755 /var/www/source-license
sudo chmod 600 /var/www/source-license/.env

# Create required directories
sudo mkdir -p /var/www/source-license/{tmp,log,downloads,licenses}
sudo chown www-data:www-data /var/www/source-license/{tmp,log,downloads,licenses}
```

### 4. Service Management
```bash
# Enable and start services
sudo systemctl daemon-reload
sudo systemctl enable source-license
sudo systemctl start source-license
sudo systemctl status source-license

# Check application logs
sudo journalctl -u source-license -f
```

## Phase 3: Security Hardening

### 1. Firewall Configuration
```bash
# Configure UFW firewall
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 'Nginx Full'
sudo ufw enable
```

### 2. Security Monitoring
```bash
# Install fail2ban for intrusion prevention
sudo apt install fail2ban

# Configure fail2ban for nginx
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# Edit /etc/fail2ban/jail.local and add:
```

```ini
[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 3600

[nginx-limit-req]
enabled = true
port = http,https
filter = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 5
bantime = 3600
```

### 3. Regular Security Updates
```bash
# Setup automatic security updates
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

## Phase 4: Monitoring & Backup

### 1. Log Management
```bash
# Configure logrotate for application logs
sudo tee /etc/logrotate.d/source-license << EOF
/var/www/source-license/log/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 www-data www-data
    postrotate
        systemctl reload source-license
    endscript
}
EOF
```

### 2. Database Backup
```bash
# Create backup script
sudo tee /usr/local/bin/backup-source-license << 'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/source-license"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR

# Database backup
mysqldump -u source_license -p source_license > $BACKUP_DIR/db_backup_$DATE.sql

# Application backup
tar -czf $BACKUP_DIR/app_backup_$DATE.tar.gz -C /var/www source-license

# Keep only last 30 days of backups
find $BACKUP_DIR -name "*.sql" -mtime +30 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +30 -delete
EOF

sudo chmod +x /usr/local/bin/backup-source-license

# Setup daily backup cron job
echo "0 2 * * * root /usr/local/bin/backup-source-license" | sudo tee -a /etc/crontab
```

### 3. Health Monitoring
Create monitoring script `/usr/local/bin/health-check`:

```bash
#!/bin/bash
HEALTH_URL="https://yourdomain.com/health"
SLACK_WEBHOOK="YOUR_SLACK_WEBHOOK_URL"

if ! curl -f -s $HEALTH_URL > /dev/null; then
    curl -X POST -H 'Content-type: application/json' \
        --data '{"text":"🚨 Source License application health check failed!"}' \
        $SLACK_WEBHOOK
fi
```

## Phase 5: Testing & Validation

### 1. Functional Testing
```bash
# Test application endpoints
curl -f https://yourdomain.com/health
curl -f https://yourdomain.com/ready

# Test admin login
curl -X POST https://yourdomain.com/admin/login \
  -d "email=admin@yourdomain.com&password=YOUR_PASSWORD"

# Test API endpoints
curl -f https://yourdomain.com/api/license/test-key/validate
```

### 2. Security Testing
```bash
# SSL/TLS testing
curl -I https://yourdomain.com | grep -i security

# Test HTTPS redirection
curl -I http://yourdomain.com

# Security headers check
curl -I https://yourdomain.com | grep -E "(Strict-Transport|X-Frame|X-Content)"
```

### 3. Performance Testing
```bash
# Install Apache Bench for load testing
sudo apt install apache2-utils

# Basic load test
ab -n 100 -c 10 https://yourdomain.com/

# Test API performance
ab -n 50 -c 5 https://yourdomain.com/api/license/test/validate
```

## Phase 6: Go-Live Checklist

### Pre-Launch Validation
- [ ] All environment variables configured correctly
- [ ] Database migrations completed successfully
- [ ] SSL certificate valid and auto-renewal configured
- [ ] Web server configuration tested
- [ ] Application service running and stable
- [ ] Health check endpoints responding
- [ ] Admin login working with strong password
- [ ] Payment gateways configured for production
- [ ] Email delivery working
- [ ] Backup system operational
- [ ] Monitoring and alerting configured

### Security Verification
- [ ] HTTPS enforcement working
- [ ] Security headers present
- [ ] CSRF protection active
- [ ] Rate limiting functional
- [ ] Input validation working
- [ ] Authentication lockout working
- [ ] Firewall rules active
- [ ] Intrusion prevention configured

### Performance Verification
- [ ] Response times acceptable under load
- [ ] Database queries optimized
- [ ] Static assets cached properly
- [ ] CDN configured (if applicable)
- [ ] Monitoring dashboards active

## Post-Launch Maintenance

### Daily Tasks
- Check application health status
- Review error logs
- Monitor performance metrics
- Verify backup completion

### Weekly Tasks
- Security log review
- Performance analysis
- Update security patches
- Database maintenance

### Monthly Tasks
- Full security audit
- Backup restoration test
- Certificate renewal check
- Dependency updates

## Troubleshooting Guide

### Common Issues

#### Application Won't Start
```bash
# Check service status
sudo systemctl status source-license

# Check logs
sudo journalctl -u source-license -n 50

# Check configuration
bundle exec ruby -c config.ru
```

#### Database Connection Issues
```bash
# Test database connection
mysql -u source_license -p source_license

# Check database service
sudo systemctl status mysql
```

#### SSL Certificate Issues
```bash
# Check certificate validity
sudo certbot certificates

# Test SSL configuration
sudo nginx -t
```

### Performance Issues
```bash
# Monitor system resources
htop
iotop
netstat -tlnp

# Check application performance
curl -w "@curl-format.txt" -o /dev/null https://yourdomain.com/
```

## Support and Maintenance

### Documentation
- Keep deployment documentation updated
- Document all configuration changes
- Maintain runbooks for common procedures

### Team Training
- Ensure operations team understands the deployment
- Provide troubleshooting training
- Create escalation procedures

### Continuous Improvement
- Regular security assessments
- Performance optimization
- Feature updates and patches
- Infrastructure scaling planning

---

**Deployment completed successfully!** 🎉

Your Source-License application is now running in production with enterprise-grade security, monitoring, and reliability.
