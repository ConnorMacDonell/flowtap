# Rails SaaS Template

A production-ready Ruby on Rails template for launching SaaS applications quickly. This template provides essential SaaS features including user authentication, subscription management, admin dashboard, and email system.

## Features

### 🔐 Authentication System
- User registration with email verification
- Login/logout with "Remember me" option
- Password reset via email
- Profile management
- Account deletion with 30-day soft delete

### 💳 Subscription System
- Three tiers: Free, Standard ($19/mo), Premium ($49/mo)
- Stripe integration (paid tiers currently disabled)
- Subscription management interface
- Customer portal integration

### 👨‍💼 Admin Dashboard
- User management and search
- User impersonation for support
- System metrics and health monitoring
- Sidekiq job monitoring

### 📧 Email System
- Transactional emails via SendGrid
- Email templates for all user actions
- Development email preview with letter_opener
- Background email processing

### ⚡ Background Processing
- Sidekiq for async job processing
- Email sending, data exports, webhook processing
- Configurable job queues and retry logic

## Technology Stack

- **Framework**: Ruby on Rails 7.1+
- **Database**: PostgreSQL 15+
- **Frontend**: Tailwind CSS + Hotwire (Turbo + Stimulus)
- **Background Jobs**: Sidekiq with Redis
- **Email**: SendGrid
- **Payments**: Stripe
- **Testing**: RSpec, Factory Bot, Capybara
- **Deployment**: Heroku

## Quick Start

### Prerequisites

- Ruby 3.1.0+
- PostgreSQL 15+
- Redis 7+
- Node.js 18+ (for Tailwind)

### Installation

1. Clone the repository
```bash
git clone <repository-url>
cd saas-template
```

2. Install dependencies
```bash
bundle install
```

3. Setup database
```bash
rails db:create
rails db:migrate
rails db:seed
```

4. Copy environment variables
```bash
cp .env.example .env
```

5. Start the development server
```bash
foreman start -f Procfile.dev
```

Visit `http://localhost:3000` to see the application.

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

- **Database**: `DATABASE_URL`
- **Redis**: `REDIS_URL`
- **Stripe**: `STRIPE_PUBLISHABLE_KEY`, `STRIPE_SECRET_KEY`
- **SendGrid**: `SENDGRID_API_KEY`
- **Application**: `SECRET_KEY_BASE`, `DEFAULT_FROM_EMAIL`

### Services Setup

1. **Stripe**: Create account at https://stripe.com
2. **SendGrid**: Create account at https://sendgrid.com
3. **Heroku**: Create account at https://heroku.com (for deployment)

## Development

### Running Tests

```bash
bundle exec rspec
```

### Starting Background Jobs

```bash
bundle exec sidekiq
```

### Email Preview

Visit `http://localhost:3000/letter_opener` to preview emails in development.

### Console Access

```bash
rails console
```

## Deployment

### Heroku Deployment

1. Create Heroku app
```bash
heroku create your-app-name
```

2. Add required addons
```bash
heroku addons:create heroku-postgresql:mini
heroku addons:create heroku-redis:mini
heroku addons:create sendgrid:starter
```

3. Set environment variables
```bash
heroku config:set RAILS_MASTER_KEY=<your-master-key>
heroku config:set STRIPE_PUBLISHABLE_KEY=<your-key>
heroku config:set STRIPE_SECRET_KEY=<your-key>
```

4. Deploy
```bash
git push heroku main
heroku run rails db:migrate
```

## Project Structure

```
app/
├── controllers/          # Request handling
├── models/              # Business logic and data
├── views/               # HTML templates
├── jobs/                # Background jobs
├── mailers/             # Email handling
└── services/            # Business logic services

config/
├── initializers/        # Gem configurations
├── routes.rb           # URL routing
└── database.yml        # Database configuration

db/
├── migrate/            # Database migrations
└── seeds.rb           # Sample data

spec/                   # Test files
```

## Key Models

### User
- Email authentication with Devise
- Profile information (name, timezone)
- Subscription association
- Soft delete support

### Subscription
- Three tiers: free, standard, premium
- Stripe integration
- Status tracking

### AdminUser
- Separate admin authentication
- Admin dashboard access

## Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

This project is licensed under the MIT License.

## Support

For questions and support:
- Check the documentation in `/docs`
- Review the code comments
- Create an issue on GitHub
