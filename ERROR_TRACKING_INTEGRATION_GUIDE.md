# Error Tracking Integration Guide

## Overview

The Source-License application includes built-in error tracking integration that supports multiple popular error tracking services. All error tracking is **completely optional** - the application works perfectly without any external services.

## Supported Error Tracking Services

### ✅ **Sentry** (Recommended)
- **Website**: https://sentry.io
- **Free Tier**: 5,000 errors/month
- **Paid Plans**: From $26/month
- **Best For**: Most applications, excellent Ruby support

### ✅ **Bugsnag**
- **Website**: https://bugsnag.com
- **Free Tier**: 7,500 errors/month
- **Paid Plans**: From $59/month
- **Best For**: Teams wanting detailed error context

### ✅ **Rollbar**
- **Website**: https://rollbar.com
- **Free Tier**: 5,000 errors/month
- **Paid Plans**: From $12/month
- **Best For**: Budget-conscious teams

### ✅ **Airbrake**
- **Website**: https://airbrake.io
- **Free Tier**: No free tier
- **Paid Plans**: From $49/month
- **Best For**: Enterprise applications

### ✅ **Honeybadger**
- **Website**: https://honeybadger.io
- **Free Tier**: 30-day trial
- **Paid Plans**: From $39/month
- **Best For**: Ruby/Rails focused teams

### ✅ **Custom Webhook**
- **Cost**: Free (your infrastructure)
- **Best For**: Custom integrations, Slack/Discord alerts

## Quick Setup Guide

### Option 1: No Error Tracking (Default)
```bash
# .env configuration
# Simply don't set ERROR_TRACKING_DSN
# All errors will be logged locally only
```

**Result**: All errors logged to local files and stdout. Perfect for development and small deployments.

### Option 2: Sentry Integration (Recommended)

#### Step 1: Create Sentry Account
1. Sign up at https://sentry.io (free tier available)
2. Create a new project
3. Select "Ruby" as the platform
4. Copy the DSN from the project settings

#### Step 2: Configure Application
```bash
# Add to .env file
ERROR_TRACKING_DSN=https://PUBLIC_KEY@SENTRY_PROJECT_ID.ingest.sentry.io/PROJECT_ID
```

#### Step 3: Test Integration
```bash
# Restart the application
sudo systemctl restart source-license

# Test error reporting
curl -X POST https://yourdomain.com/api/test-error
```

#### Step 4: Verify in Sentry Dashboard
- Go to your Sentry dashboard
- Check for incoming errors
- Configure alert rules and integrations

### Option 3: Bugsnag Integration

#### Step 1: Setup Bugsnag
1. Sign up at https://bugsnag.com
2. Create a new project
3. Copy the API key from project settings

#### Step 2: Configure Application
```bash
# Add to .env file
ERROR_TRACKING_DSN=YOUR_BUGSNAG_API_KEY
```

### Option 4: Rollbar Integration

#### Step 1: Setup Rollbar
1. Sign up at https://rollbar.com
2. Create a new project
3. Copy the server-side access token

#### Step 2: Configure Application
```bash
# Add to .env file
ERROR_TRACKING_DSN=YOUR_ROLLBAR_ACCESS_TOKEN
```

### Option 5: Custom Webhook

#### Step 1: Create Webhook Endpoint
Set up a webhook that accepts POST requests with JSON payloads.

#### Step 2: Configure Application
```bash
# Add to .env file
ERROR_TRACKING_DSN=https://your-webhook-url.com/errors
```

## Detailed Configuration Examples

### Sentry Configuration

#### Basic Setup
```bash
# .env
ERROR_TRACKING_DSN=https://abc123@o123456.ingest.sentry.io/123456
APP_VERSION=1.0.0
APP_ENV=production
```

#### Advanced Sentry Features
```bash
# Enable performance monitoring
SENTRY_TRACES_SAMPLE_RATE=0.1

# Set release information
SENTRY_RELEASE=source-license@1.0.0

# Configure environment
SENTRY_ENVIRONMENT=production
```

### Bugsnag Configuration

#### Basic Setup
```bash
# .env
ERROR_TRACKING_DSN=1234567890abcdef1234567890abcdef
APP_VERSION=1.0.0
```

#### Advanced Features
Configure in Bugsnag dashboard:
- Release stages (development, staging, production)
- User tracking
- Breadcrumbs
- Custom metadata

### Custom Webhook Configuration

#### Webhook Payload Format
Your webhook will receive POST requests with this JSON structure:

```json
{
  "error": {
    "class": "NoMethodError",
    "message": "undefined method `foo' for nil:NilClass",
    "backtrace": [
      "/var/www/source-license/app.rb:123:in `some_method'",
      "/var/www/source-license/app.rb:456:in `another_method'"
    ]
  },
  "context": {
    "method": "POST",
    "path": "/api/some-endpoint",
    "ip": "192.168.1.100",
    "user_agent": "Mozilla/5.0..."
  },
  "application": {
    "name": "source-license",
    "version": "1.0.0",
    "environment": "production",
    "hostname": "server-1"
  },
  "timestamp": "2025-07-05T13:06:53Z"
}
```

#### Slack Webhook Example
```bash
# For Slack notifications
ERROR_TRACKING_DSN=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK
```

## Testing Error Tracking

### Manual Testing

#### Test Error Endpoint
Add this to your app.rb for testing (remove in production):

```ruby
# Test endpoint - REMOVE IN PRODUCTION
get '/test-error' do
  require_admin_auth
  
  # Test different error types
  case params[:type]
  when 'runtime'
    raise StandardError, 'Test runtime error'
  when 'method'
    nil.some_nonexistent_method
  when 'argument'
    raise ArgumentError, 'Test argument error'
  else
    raise 'Generic test error'
  end
end
```

#### Test Commands
```bash
# Test runtime error
curl "https://yourdomain.com/test-error?type=runtime"

# Test method error
curl "https://yourdomain.com/test-error?type=method"

# Test argument error
curl "https://yourdomain.com/test-error?type=argument"
```

### Automated Testing

#### Health Check Integration
The error tracking is tested as part of the application startup:

```bash
# Check if error tracking is configured
curl https://yourdomain.com/ready

# Response includes error tracking status
{
  "status": "ready",
  "checks": {
    "error_tracking": {
      "status": "configured",
      "service": "sentry"
    }
  }
}
```

## Monitoring Error Tracking

### Built-in Monitoring
The application logs all error tracking attempts:

```bash
# Check error tracking logs
grep "error.*tracking" /var/www/source-license/log/application.log

# Check for failed attempts
grep "Failed to send error" /var/www/source-license/log/application.log
```

### Service-Specific Monitoring

#### Sentry
- Dashboard: Issues tab
- Alerts: Configure in Alerts settings
- Performance: Performance tab

#### Bugsnag
- Dashboard: Errors tab
- Alerts: Configure in Project Settings
- Stability Score: Overview tab

#### Rollbar
- Dashboard: Items tab
- Alerts: Settings > Notifications
- Deploy tracking: Deploys tab

## Troubleshooting

### Common Issues

#### 1. Error Tracking Not Working
```bash
# Check configuration
grep ERROR_TRACKING_DSN /var/www/source-license/.env

# Check application logs
tail -f /var/www/source-license/log/application.log | grep -i error

# Test connectivity
curl -I https://sentry.io
```

#### 2. Invalid DSN Format
```bash
# Correct formats:
# Sentry: https://PUBLIC_KEY@SENTRY_PROJECT_ID.ingest.sentry.io/PROJECT_ID
# Bugsnag: API_KEY_STRING
# Rollbar: ACCESS_TOKEN_STRING
# Webhook: https://your-webhook-url.com/endpoint
```

#### 3. Authentication Errors
- **Sentry**: Check public key and project ID in DSN
- **Bugsnag**: Verify API key is correct
- **Rollbar**: Ensure access token has proper permissions
- **Webhook**: Verify URL is accessible and accepts POST requests

#### 4. Rate Limiting
Most services have rate limits:
- **Sentry**: 60 requests/minute per key
- **Bugsnag**: 100 errors/minute
- **Rollbar**: Based on plan

### Debug Mode
Enable debug logging for error tracking:

```bash
# Add to .env
LOG_LEVEL=debug
ERROR_TRACKING_DEBUG=true

# Restart application
sudo systemctl restart source-license

# Watch debug logs
tail -f /var/www/source-license/log/application.log | grep -i "error.*tracking"
```

## Performance Considerations

### Asynchronous Processing
All error tracking is processed asynchronously to avoid impacting application performance:

```ruby
# Errors are sent in background threads
Thread.new do
  send_to_error_tracking(exception, context)
end
```

### Rate Limiting
The application includes built-in rate limiting for error reporting:

```bash
# Configure in .env
ERROR_TRACKING_RATE_LIMIT=100  # Max errors per minute
ERROR_TRACKING_BURST_LIMIT=10  # Max errors per second
```

### Memory Usage
Error tracking adds minimal memory overhead:
- **Without error tracking**: 0MB additional
- **With error tracking**: ~2-5MB for HTTP client libraries

## Security Considerations

### Data Sanitization
The application automatically sanitizes sensitive data before sending to error tracking services:

#### Automatically Removed:
- Credit card numbers
- CVV codes
- SSN numbers
- Bank account numbers
- API keys and secrets
- Password fields

#### Email Masking:
- `user@example.com` becomes `u***r@example.com`

#### Custom Sanitization
Add custom sanitization in `lib/logger.rb`:

```ruby
def sanitize_error_context(context)
  sanitized = context.dup
  
  # Remove custom sensitive fields
  sensitive_fields = %w[custom_secret internal_id]
  sensitive_fields.each do |field|
    sanitized.delete(field)
    sanitized.delete(field.to_sym)
  end
  
  sanitized
end
```

## Cost Optimization

### Free Tier Optimization
Maximize free tier usage:

1. **Filter Non-Critical Errors**
   ```bash
   # Set higher error threshold
   ERROR_TRACKING_LEVEL=warn  # Only warn/error/fatal
   ```

2. **Sampling**
   ```bash
   # Sample 50% of errors
   ERROR_TRACKING_SAMPLE_RATE=0.5
   ```

3. **Local Development**
   ```bash
   # Disable in development
   # Don't set ERROR_TRACKING_DSN in development .env
   ```

### Cost Comparison

| Service | Free Tier | First Paid Tier | Cost per Additional Error |
|---------|-----------|-----------------|---------------------------|
| Sentry | 5,000/month | $26/month (50K) | ~$0.0005 |
| Bugsnag | 7,500/month | $59/month (unlimited) | N/A |
| Rollbar | 5,000/month | $12/month (25K) | ~$0.0004 |
| Webhook | Unlimited | Your hosting cost | Varies |

## Best Practices

### 1. Environment-Specific Configuration
```bash
# Development
ERROR_TRACKING_DSN=  # Empty - no external tracking

# Staging
ERROR_TRACKING_DSN=https://staging-key@sentry.io/staging-project

# Production
ERROR_TRACKING_DSN=https://production-key@sentry.io/production-project
```

### 2. Alert Configuration
- **Critical**: Payment failures, security breaches
- **High**: Admin authentication failures, database errors
- **Medium**: API rate limits, validation errors
- **Low**: 404 errors, client-side errors

### 3. Error Grouping
Configure intelligent error grouping to avoid alert fatigue:
- Group by error class and method
- Ignore common client errors (404, etc.)
- Set frequency limits for repeat errors

### 4. Performance Monitoring
If supported by your service, enable performance monitoring:
- Track slow database queries
- Monitor payment processing times
- Track license validation performance

## Migration Between Services

### From No Tracking to Sentry
```bash
# 1. Create Sentry account and project
# 2. Add DSN to .env
ERROR_TRACKING_DSN=https://key@sentry.io/project

# 3. Restart application
sudo systemctl restart source-license

# 4. Verify in Sentry dashboard
```

### From Sentry to Bugsnag
```bash
# 1. Create Bugsnag account and project
# 2. Update .env
ERROR_TRACKING_DSN=bugsnag_api_key_here

# 3. Restart application
sudo systemctl restart source-license
```

### Service Detection
The application automatically detects the service based on the DSN format:
- URLs containing `sentry.io` → Sentry
- URLs containing `bugsnag.com` → Bugsnag  
- URLs containing `rollbar.com` → Rollbar
- API keys → Detected by format
- HTTP URLs → Custom webhook

## Conclusion

Error tracking is a powerful tool for maintaining application reliability, but it's completely optional. The Source-License application provides:

✅ **Works without error tracking** - All errors logged locally
✅ **Easy integration** - Single environment variable
✅ **Multiple service support** - Choose what works for you
✅ **Automatic detection** - No complex configuration
✅ **Security-first** - Automatic data sanitization
✅ **Performance-optimized** - Asynchronous processing

Start with local logging and add external error tracking as your needs grow!
