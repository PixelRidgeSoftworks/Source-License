# Source License - AI Coding Agent Instructions

## Architecture Overview

This is a **Ruby/Sinatra** software licensing platform using proper Sinatra patterns:

- **Entry Point**: [app.rb](../app.rb) → loads `lib/database.rb` → `lib/models.rb` → controllers
- **Main App Class**: `SourceLicenseApp < Sinatra::Base` in `lib/controllers/core/application.rb`
- **Base Controller**: `BaseControllerClass < Sinatra::Base` in `lib/controllers/core/base_controller.rb`
- **Controllers**: Organized in `lib/controllers/{admin,api,auth,core,public,webhooks}/`
- **Models**: Sequel ORM models in `lib/models/` - each entity (License, Order, Product) has its own file
- **Services**: Business logic in `lib/services/` (e.g., `Admin::OrderService` for order operations)
- **Helpers**: Template/view helpers in `lib/helpers/`, auth helpers in `lib/auth/`

## Sinatra Application Structure

The main app (`SourceLicenseApp`) extends `Sinatra::Base` and uses:
- `register Sinatra::Contrib` for extensions
- `enable :sessions` with `set :session_secret` for session management
- `set :protection` for Rack::Protection middleware (CSRF, XSS, etc.)
- Environment-specific `configure` blocks for dev/test/production

```ruby
class SourceLicenseApp < Sinatra::Base
  register Sinatra::Contrib

  enable :sessions
  set :session_secret, ENV.fetch('APP_SECRET', SecureRandom.hex(64))
  set :sessions, httponly: true, secure: is_production, same_site: :lax

  # Rack::Protection enabled by default, customize as needed
  set :protection, except: [:json_csrf]

  configure :test do
    set :protection, false  # Disable in tests
  end
end
```

## Controller Pattern

Controllers use a **module-based route registration** pattern:

```ruby
# Example from lib/controllers/public/public_controller.rb
module PublicController
  def self.setup_routes(app)
    homepage_route(app)
    products_listing_route(app)
  end

  def self.homepage_route(app)
    app.get '/' do
      # route logic
    end
  end
end
```

For new controllers, you can also inherit from `BaseControllerClass` (a `Sinatra::Base` subclass):

```ruby
class MyController < BaseControllerClass
  get '/my-route' do
    # route logic - helpers already included
  end
end
```

## CSRF Protection

CSRF protection uses **Sinatra's Rack::Protection** plus a custom `before` filter in `application.rb`:

- **Rack::Protection**: Enabled by default via `set :protection`
- **Custom filter**: Validates `csrf_token` param, `_token` (legacy), and `X-CSRF-Token` header
- **Exempt paths**: `/api/*` (uses JWT auth), `/webhooks/*` (uses signature verification)
- **In views**: Use `<%= csrf_input %>` helper in all POST forms
- **In JavaScript**: Include `X-CSRF-Token` header in AJAX requests

```erb
<!-- In forms -->
<form method="POST" action="/admin/action">
  <%= csrf_input %>
  <!-- form fields -->
</form>
```

```javascript
// In JavaScript AJAX
fetch('/admin/action', {
  method: 'POST',
  headers: {
    'X-CSRF-Token': '<%= csrf_token %>'
  }
});
```

**DO NOT** add manual `require_csrf_token` calls in controllers - the global filter handles it.

## Session Configuration

Sessions are configured in `SourceLicenseApp` class using Sinatra's native session handling:
- Production requires `APP_SECRET` env var (64+ chars)
- Uses `enable :sessions` + `set :session_secret` pattern
- Session attributes: `httponly: true`, `secure` in production, `same_site: :lax`

## Database & Models

- **ORM**: Sequel (not ActiveRecord). Models inherit from `Sequel::Model`
- **Connection**: `DB` constant set in `lib/database.rb` - supports MySQL, PostgreSQL, SQLite
- **Migrations**: Located in `lib/migrations/NNN_description.rb`, extend `Migrations::BaseMigration`
- **Model relationships**: Use `many_to_one`, `one_to_many`, `one_to_one` (Sequel syntax)

```ruby
# Model pattern from lib/models/license.rb
class License < Sequel::Model
  include BaseModelMethods
  many_to_one :order
  many_to_one :product
  one_to_many :license_activations
end
```

## Authentication System

Modular auth in `lib/auth/`:
- `AuthHelpers` combines all auth modules for backward compatibility
- Admin auth: `current_secure_admin` helper, session-based
- API auth: JWT tokens via `Auth::JWTManager`
- 2FA: TOTP support via `Auth::TwoFactorAuth`

## Payment Processing

- **Facade pattern**: `PaymentProcessor` delegates to `StripeProcessor` or `PaypalProcessor`
- **Webhooks**: Handlers in `lib/webhooks/` with modular event dispatchers
- Always validate with `PaymentLogger` for audit trails

## Key Commands

```bash
# Development
./install.sh              # Install dependencies
./deploy.sh start         # Start server (port 4567)
./deploy.sh stop          # Stop server

# Testing
bundle exec ruby run_tests.rb                    # Run all tests
bundle exec ruby -Itest test/app_test.rb         # Single test file
bundle exec rubocop -A                           # Auto-fix style issues

# Database
./deploy.sh migrate       # Run migrations
```

## Testing Patterns

- **Framework**: Minitest with Rack::Test
- **Factories**: FactoryBot in `test/factories.rb` - use `create(:product)`, `create_list(:order, 3)`
- **Test DB**: SQLite in-memory, tables created in `test/test_helper.rb`
- **Helpers**: `create_test_admin`, `login_as_admin`, `assert_successful_response`
- **CSRF/Protection disabled** in test environment via `set :protection, false`

```ruby
# Test pattern from test/app_test.rb
def test_admin_dashboard_with_login
  create_test_admin
  login_as_admin
  get '/admin'
  assert_successful_response
end
```

## Code Conventions

- **Frozen string literals**: Every Ruby file starts with `# frozen_string_literal: true`
- **Rubocop**: Style enforcement enabled - run `bundle exec rubocop` before commits
- **Module namespacing**: Use explicit module definition when compact style causes issues (see webhook handlers)
- **Error responses**: API endpoints return `{ success: false, error: 'message' }` JSON

## File Location Patterns

| What | Where |
|------|-------|
| New API endpoint | `lib/controllers/api/api_controller.rb` or new controller |
| New admin feature | `lib/controllers/admin/` (follow existing pattern) |
| Business logic | `lib/services/` (avoid putting logic in controllers) |
| New model | `lib/models/your_model.rb` + require in `lib/models.rb` |
| New migration | `lib/migrations/NNN_description.rb` |
| View templates | `views/` with ERB, layouts in `views/layouts/` |
| CSRF/Security | `lib/csrf_protection.rb`, `lib/security.rb` |

## Common Gotchas

- Database must be set up BEFORE requiring models (see `app.rb` load order)
- Test environment uses different env vars - check `test/test_helper.rb`
- Security middleware disabled in dev/test - production uses `SecurityMiddleware`
- License keys are hashed with `SecureLicenseService.hash_license_key()` - never store plaintext
