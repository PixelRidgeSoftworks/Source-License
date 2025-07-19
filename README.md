# Source License - Professional Software Licensing System

A comprehensive Ruby/Sinatra-based software licensing management system with integrated payment processing, secure API, and elegant web interface.

## Features

### 🔐 License Management
- **Secure License Generation**: Cryptographically secure license keys with configurable formats
- **Multiple License Types**: Support for one-time purchases and recurring subscriptions
- **Activation Tracking**: Monitor license activations across multiple machines
- **Real-time Validation**: REST API for instant license verification
- **License Operations**: Suspend, revoke, extend, and transfer licenses

### 💳 Payment Processing
- **Stripe Integration**: Complete credit card processing with webhooks
- **PayPal Support**: PayPal checkout and recurring billing
- **Automatic License Delivery**: Instant license generation upon successful payment
- **Subscription Management**: Automatic renewal and billing for subscription products

### 🎨 User Interface
- **Modern Web Design**: Bootstrap 5 with custom CSS and responsive design
- **Admin Dashboard**: Comprehensive management interface with real-time statistics
- **Customer Portal**: License lookup, downloads, and management
- **Template System**: Easily customizable ERB templates with helper functions

### 🛡️ Security & API
- **Secure REST API**: JWT-based authentication with comprehensive endpoints
- **Database Support**: MySQL and PostgreSQL via Sequel ORM
- **Cross-Platform**: Works on Windows, macOS, and Linux
- **Email Integration**: SMTP support for license delivery and notifications

## Quick Start

### Prerequisites
- Ruby 3.4.0 or higher
- Database (MySQL or PostgreSQL)
- Git

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/VetheonGames/Source-License.git
   cd Source-License
   ```

2. **Run the launcher**
   ```bash
   ruby launch.rb
   ```
   
   The launcher will automatically:
   - Check Ruby version compatibility
   - Install required gems
   - Set up the database
   - Create configuration files
   - Launch the application

3. **Access the application**
   - **Website**: http://localhost:4567
   - **Admin Panel**: http://localhost:4567/admin
   - **API Documentation**: http://localhost:4567/api/docs

### Configuration

Copy `.env.example` to `.env` and configure your settings:

```bash
cp .env.example .env
```

Edit `.env` with your specific configuration:

```env
# Database
DATABASE_ADAPTER=mysql
DATABASE_HOST=localhost
DATABASE_NAME=source_license
DATABASE_USER=your_user
DATABASE_PASSWORD=your_password

# Payment Gateways
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_SECRET_KEY=sk_test_...
PAYPAL_CLIENT_ID=your_paypal_client_id

# Email
SMTP_HOST=smtp.gmail.com
SMTP_USERNAME=your_email@gmail.com
SMTP_PASSWORD=your_app_password

# Admin
ADMIN_EMAIL=admin@yourdomain.com
ADMIN_PASSWORD=secure_password
```

## Project Structure

```
Source-License/
├── app.rb                 # Main Sinatra application
├── config.ru             # Rack configuration
├── launch.rb             # Cross-platform launcher
├── Gemfile               # Ruby dependencies
├── .env.example          # Environment configuration template
├── lib/                  # Core application logic
│   ├── auth.rb           # Authentication helpers
│   ├── database.rb       # Database configuration
│   ├── helpers.rb        # Template and utility helpers
│   ├── license_generator.rb # License generation and validation
│   ├── migrations.rb     # Database schema migrations
│   ├── models.rb         # Sequel database models
│   └── payment_processor.rb # Payment gateway integration
├── views/                # ERB template files
│   ├── layouts/          # Layout templates
│   ├── partials/         # Reusable template components
│   ├── admin/            # Admin interface templates
│   └── *.erb            # Page templates
├── public/               # Static assets (auto-created)
├── downloads/            # Product download files (auto-created)
└── licenses/             # Generated license files (auto-created)
```

## API Documentation

### Authentication

The API uses JWT-based authentication. First, obtain a token:

```bash
curl -X POST http://localhost:4567/api/auth \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@example.com", "password": "admin123"}'
```

### License Validation

```bash
curl -X GET http://localhost:4567/api/license/XXXX-XXXX-XXXX-XXXX/validate \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

### License Activation

```bash
curl -X POST http://localhost:4567/api/license/XXXX-XXXX-XXXX-XXXX/activate \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"machine_fingerprint": "unique_machine_id"}'
```

### API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth` | Authenticate and get JWT token |
| GET | `/api/license/:key/validate` | Validate a license key |
| POST | `/api/license/:key/activate` | Activate license on a machine |
| POST | `/api/orders` | Create a new order |
| GET | `/api/orders/:id` | Get order details |
| POST | `/api/webhook/:provider` | Payment webhook endpoint |

## Template Customization

The application uses ERB templates with extensive helper functions for easy customization:

### Helper Functions

```erb
<!-- Currency formatting -->
<%= format_currency(29.99) %> <!-- Output: $29.99 -->

<!-- Date formatting -->
<%= format_date(Time.now, :long) %> <!-- Output: January 5, 2025 -->

<!-- Status badges -->
<%= status_badge('active') %> <!-- Output: <span class="badge badge-success">Active</span> -->

<!-- Custom buttons with CSS classes -->
<%= button 'Buy Now', class: 'btn btn-primary btn-lg' %>

<!-- Cards with customizable styling -->
<%= card 'Product Info', class: 'border-primary' do %>
  <p>Product details here...</p>
<% end %>
```

### Partials

Reusable template components for easy customization:

```erb
<!-- Navigation bar -->
<%= partial 'navigation' %>

<!-- Footer -->
<%= partial 'footer' %>

<!-- Product card -->
<%= partial 'product_card', locals: { product: @product } %>
```

## Database Models

### Core Models

- **Admin**: Administrative users
- **Product**: Software products for sale
- **Order**: Customer purchases
- **OrderItem**: Individual items within orders
- **License**: Generated software licenses
- **Subscription**: Recurring billing for subscription products
- **LicenseActivation**: Machine activation tracking

### Relationships

```ruby
# One order can have multiple licenses
order.licenses

# Each license belongs to a product
license.product

# Licenses can have multiple activations
license.license_activations

# Subscription products have subscription records
license.subscription
```

## Payment Integration

### Stripe Setup

1. Create a Stripe account at [stripe.com](https://stripe.com)
2. Get your API keys from the Stripe dashboard
3. Add keys to your `.env` file:
   ```env
   STRIPE_PUBLISHABLE_KEY=pk_test_...
   STRIPE_SECRET_KEY=sk_test_...
   STRIPE_WEBHOOK_SECRET=whsec_...
   ```

### PayPal Setup

1. Create a PayPal developer account
2. Create an application to get client credentials
3. Add credentials to your `.env` file:
   ```env
   PAYPAL_CLIENT_ID=your_client_id
   PAYPAL_CLIENT_SECRET=your_client_secret
   PAYPAL_ENVIRONMENT=sandbox  # or 'production'
   ```

## Deployment

### Development

```bash
ruby launch.rb
```

### Production

1. **Set environment variables**
   ```bash
   export APP_ENV=production
   export DATABASE_URL=your_production_database_url
   ```

2. **Install dependencies**
   ```bash
   bundle install --without development test
   ```

3. **Run migrations**
   ```bash
   bundle exec ruby -r './lib/database' -e 'Database.setup'
   ```

4. **Start the server**
   ```bash
   bundle exec puma -C config/puma.rb
   ```

### Docker Deployment

```dockerfile
FROM ruby:3.4.0
WORKDIR /app
COPY . .
RUN bundle install --without development test
EXPOSE 4567
CMD ["bundle", "exec", "rackup", "-o", "0.0.0.0", "-p", "4567"]
```

## Security Considerations

### Production Checklist

- [ ] Change default admin credentials
- [ ] Use strong APP_SECRET
- [ ] Enable HTTPS/SSL
- [ ] Configure proper firewall rules
- [ ] Set up database backups
- [ ] Monitor logs for suspicious activity
- [ ] Keep dependencies updated

### API Security

- JWT tokens expire after 24 hours
- All admin operations require authentication
- Payment webhooks verify signatures
- License keys use cryptographically secure generation
- SQL injection protection via Sequel ORM

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests if applicable
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

This project is licensed under the GNU General Public License v2.0 - see the [LICENSE](LICENSE) file for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/VetheonGames/Source-License/issues)
- **Documentation**: [Wiki](https://github.com/VetheonGames/Source-License/wiki)
- **Email**: support@yourdomain.com

## Changelog

### v1.0.0 (2025-01-05)
- Initial release
- Complete license management system
- Stripe and PayPal integration
- REST API with JWT authentication
- Admin dashboard
- Cross-platform launcher
- MySQL and PostgreSQL support

---

**Built with ❤️ using Ruby and Sinatra**
