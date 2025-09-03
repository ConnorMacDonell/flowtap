# CLAUDE.md - Rails SaaS Template Project Guide

## General Instructions
- Always read PLANNING.md at the start of every new conversation
- Check TASKS.md before starting work
- Mark completed tasks immediately
- Add newly discovered tasks to TASKS.md

## Project Overview
Rails 7 SaaS starter template with essential features for launching a Software as a Service application. Focus on core functionality without unnecessary complexity.

## Technical Stack
- **Framework**: Rails 7.x + PostgreSQL
- **Frontend**: Tailwind CSS + Hotwire (Turbo + Stimulus)  
- **Background Jobs**: Sidekiq + Redis
- **Email**: SendGrid
- **Payments**: Stripe (ready, paid tiers disabled)
- **File Storage**: AWS S3 (configured for future)
- **Deployment**: Heroku

## Implemented Features
1. **Authentication** - Devise with email verification, password reset, profile management, soft delete
2. **Subscriptions** - Three tiers (Free active, Standard/Premium $19/$49 blocked), Stripe ready
3. **Admin Dashboard** - User management, impersonation, system monitoring, Sidekiq interface
4. **Email System** - 8 professional templates via SendGrid, background delivery
5. **Background Jobs** - Async processing for emails, exports, webhooks, scheduled cleanup

## NOT Implemented (Intentionally)
Multi-tenancy, notifications, onboarding, file uploads, APIs, 2FA

## Core Models
- **User**: Devise authentication with first/last name, timezone, soft delete
- **Subscription**: Three tiers (free/standard/premium) with Stripe integration
- **AdminUser**: Separate admin authentication system
- **AuditLog**: Security and compliance tracking

## Key Dependencies
```ruby
gem 'devise'                  # Authentication
gem 'stripe'                  # Payments
gem 'sidekiq', 'redis'        # Background jobs
gem 'tailwindcss-rails'       # Styling
gem 'sendgrid-ruby'           # Email
gem 'ransack', 'kaminari'     # Admin search/pagination
gem 'rspec-rails'             # Testing
```

## Required Environment Variables
```bash
DATABASE_URL=postgresql://...
REDIS_URL=redis://...
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_SECRET_KEY=sk_test_...
SENDGRID_API_KEY=SG...
SECRET_KEY_BASE=...
```

## Quick Reference

### Development Commands
```bash
# Start development
bundle exec foreman start -f Procfile.dev

# Email previews
http://localhost:3000/rails/mailers

# Admin dashboard  
http://localhost:3000/admin

# Background jobs
bundle exec sidekiq
```

### Common Tasks
```ruby
# Create test user
User.create!(email: "test@example.com", password: "password123", 
            first_name: "Test", confirmed_at: Time.current)

# Create admin
AdminUser.create!(email: "admin@example.com", password: "password", name: "Admin")

# Send email
UserMailer.welcome_email(user).deliver_later
```

## Coding Guidelines
- **Controllers**: Strong parameters, thin controllers, move logic to models
- **Models**: Validations, scopes, minimal callbacks, proper indexes
- **Views**: Tailwind utilities, Turbo frames, partials for reuse
- **Jobs**: Idempotent, focused responsibilities, proper error handling

## Common Issues
- **No emails**: Check `letter_opener` at http://localhost:3000/letter_opener
- **Sidekiq not processing**: Start Redis and `bundle exec sidekiq`
- **Stripe webhooks**: Use `stripe listen --forward-to localhost:3000/stripe/webhooks`

## Future Implementation
- **Paid Tiers**: Remove `SubscriptionsController` blocks, add Stripe checkout
- **File Uploads**: Configure Active Storage + S3
- **Multi-tenancy**: Add Organization model with subdomain routing

## Development History

### Completed Milestones ✅
1. **Project Foundation** - Rails 7 + PostgreSQL + Tailwind + Sidekiq + landing page
2. **Authentication** - Devise integration with custom controllers and professional UI
3. **User Dashboard** - Profile management, settings, soft delete, timezone support
4. **Subscription System** - Three-tier pricing, Stripe integration (paid tiers disabled)
5. **Admin Dashboard** - User management, impersonation, system monitoring, search/filtering
6. **Email System** - 8 professional templates, SendGrid integration, background delivery
7. **Background Jobs** - Enhanced Sidekiq, scheduled tasks, audit logging, error handling
8. **Error Handling Refactor** - Simplified to Rails conventions, removed unused complexity

### Key Technical Details
- **Authentication**: Custom Devise controllers with enhanced User model (soft delete, timezones)
- **Subscriptions**: Free tier auto-assigned, paid tiers ready but blocked
- **Admin**: Separate authentication, user impersonation, system health monitoring
- **Background Jobs**: Sidekiq with scheduled cleanup, metrics calculation, email delivery
- **Error Handling**: Rails conventions with custom error pages (404, 500, 422)

## Notes
- Project prioritizes simplicity and maintainability
- Paid features disabled but ready to activate
- Admin panel separate from user system  
- Soft delete for GDPR compliance
- Designed to scale horizontally on Heroku