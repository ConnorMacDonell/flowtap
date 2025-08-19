# PLANNING.md - Rails SaaS Template Project Planning

## Vision Statement

### Project Vision
Create a production-ready Ruby on Rails template that enables developers to launch SaaS applications in days instead of months. This template provides a solid, secure, and scalable foundation with all essential SaaS features pre-built, allowing developers to focus on their unique business logic rather than reimplementing common functionality.

### Core Principles
1. **Simplicity First** - Avoid over-engineering; include only what most SaaS apps need
2. **Production Ready** - Security, performance, and reliability built-in from day one
3. **Developer Friendly** - Clear code structure, comprehensive documentation, easy customization
4. **Business Oriented** - Ready for real customers with billing, subscriptions, and admin tools
5. **Modern Standards** - Use current best practices and actively maintained technologies

### Target Audience
- **Primary**: Individual developers and small teams building their first SaaS
- **Secondary**: Agencies needing a reliable starting point for client projects
- **Tertiary**: Experienced developers wanting to prototype quickly

### Success Metrics
- Time from clone to deployed app: < 2 hours
- Time to first paying customer: < 30 days
- Code coverage: > 90%
- Documentation completeness: 100%
- Developer satisfaction: > 4.5/5

## Architecture Overview

### High-Level Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                 │     │                 │     │                 │
│   Web Browser   │────▶│   Load Balancer │────▶│   Web Server    │
│   (Tailwind +   │     │    (Heroku)     │     │    (Puma)       │
│    Hotwire)     │     │                 │     │                 │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                          │
                                ┌─────────────────────────┴─────────────────────────┐
                                │                                                   │
                                ▼                                                   ▼
                        ┌───────────────┐                                   ┌───────────────┐
                        │               │                                   │               │
                        │  Rails App    │                                   │  Background   │
                        │  (MVC + Jobs) │                                   │  Workers      │
                        │               │                                   │  (Sidekiq)    │
                        └───────┬───────┘                                   └───────┬───────┘
                                │                                                   │
                                └─────────────────┬─────────────────────────────────┘
                                                  │
                        ┌─────────────────────────┴─────────────────────────────────┐
                        │                                                           │
                        ▼                                                           ▼
                ┌───────────────┐     ┌───────────────┐     ┌───────────────┐    ┌───────────────┐
                │  PostgreSQL   │     │     Redis     │     │   SendGrid    │    │    Stripe     │
                │   Database    │     │    Cache/     │     │    Email      │    │   Payments    │
                │               │     │    Queue      │     │   Service     │    │   Service     │
                └───────────────┘     └───────────────┘     └───────────────┘    └───────────────┘
```

### Application Layers

#### 1. Presentation Layer
- **Technology**: Tailwind CSS + Hotwire (Turbo + Stimulus)
- **Responsibilities**: 
  - Responsive UI rendering
  - Real-time updates without full page reloads
  - Form validation and user feedback
  - Progressive enhancement

#### 2. Application Layer
- **Technology**: Rails Controllers + Service Objects
- **Responsibilities**:
  - Request handling and routing
  - Authentication and authorization
  - Input validation
  - Response formatting

#### 3. Business Logic Layer
- **Technology**: Rails Models + Service Objects
- **Responsibilities**:
  - Core business rules
  - Data validation
  - Complex calculations
  - External service integration

#### 4. Data Access Layer
- **Technology**: ActiveRecord + PostgreSQL
- **Responsibilities**:
  - Database queries
  - Data persistence
  - Transaction management
  - Query optimization

#### 5. Background Processing Layer
- **Technology**: Sidekiq + Redis
- **Responsibilities**:
  - Asynchronous job processing
  - Email sending
  - Webhook processing
  - Scheduled tasks

### Security Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Security Layers                          │
├─────────────────────────────────────────────────────────────┤
│  1. Network Security                                        │
│     - HTTPS enforcement                                     │
│     - SSL/TLS certificates                                  │
│     - Secure headers (HSTS, CSP, X-Frame-Options)         │
├─────────────────────────────────────────────────────────────┤
│  2. Application Security                                    │
│     - CSRF protection                                       │
│     - SQL injection prevention (parameterized queries)      │
│     - XSS protection (output encoding)                      │
│     - Authentication (Devise with bcrypt)                   │
│     - Authorization (role-based access)                     │
├─────────────────────────────────────────────────────────────┤
│  3. Data Security                                           │
│     - Encrypted passwords                                   │
│     - Encrypted API keys and secrets                        │
│     - Secure session management                             │
│     - PII data protection                                   │
└─────────────────────────────────────────────────────────────┘
```

## Technology Stack

### Core Technologies

#### Backend
- **Ruby**: 3.2.0 or higher
  - *Rationale*: Latest stable version with performance improvements
- **Rails**: 7.1.0 or higher
  - *Rationale*: Modern Rails with Hotwire support and improved performance
- **PostgreSQL**: 15.0 or higher
  - *Rationale*: Robust, scalable, with excellent Rails support

#### Frontend
- **Hotwire**: Turbo 7.3.0 + Stimulus 3.2.0
  - *Rationale*: Minimal JavaScript, server-side rendering, real-time updates
- **Tailwind CSS**: 3.4.0
  - *Rationale*: Utility-first, highly customizable, small production builds

#### Infrastructure
- **Redis**: 7.0 or higher
  - *Rationale*: Fast caching, Sidekiq backend, ActionCable support
- **Sidekiq**: 7.0 or higher
  - *Rationale*: Reliable background processing, excellent Rails integration

### Third-Party Services

#### Payment Processing
- **Stripe**: Latest API version
  - *Rationale*: Industry standard, excellent documentation, global support
  - *Features Used*: Customers, Subscriptions, Webhooks, Invoices

#### Email Delivery
- **SendGrid**: Latest API version
  - *Rationale*: Reliable delivery, good analytics, Heroku addon available
  - *Features Used*: Transactional emails, Templates, Webhooks

#### Cloud Storage (Future)
- **AWS S3**: Latest SDK
  - *Rationale*: Scalable, reliable, Active Storage support
  - *Features Planned*: File uploads, Avatar storage, Document storage

#### Deployment Platform
- **Heroku**: Professional dynos
  - *Rationale*: Easy deployment, automatic scaling, excellent Rails support
  - *Addons Required*: Heroku Postgres, Heroku Redis, SendGrid

### Development Dependencies

#### Testing
- **RSpec**: 3.12 or higher
  - *Rationale*: Expressive syntax, great Rails integration
- **Factory Bot**: 6.2 or higher
  - *Rationale*: Flexible test data generation
- **Capybara**: 3.39 or higher
  - *Rationale*: Integration testing with JavaScript support

#### Code Quality
- **RuboCop**: Latest version
  - *Rationale*: Ruby style guide enforcement
- **Brakeman**: Latest version
  - *Rationale*: Security vulnerability scanning
- **Bundle Audit**: Latest version
  - *Rationale*: Gem vulnerability checking

#### Development Tools
- **Letter Opener**: Latest version
  - *Rationale*: Email preview in development
- **Pry Rails**: Latest version
  - *Rationale*: Better debugging experience
- **Annotate**: Latest version
  - *Rationale*: Schema documentation in models

## Required Tools List

### Development Environment

#### Essential Tools
1. **Ruby Version Manager**
   - Options: rbenv, RVM, or asdf
   - Purpose: Ruby version management
   - Installation: `brew install rbenv` (macOS)

2. **PostgreSQL**
   - Version: 15.0+
   - Purpose: Database server
   - Installation: `brew install postgresql@15` (macOS)

3. **Redis**
   - Version: 7.0+
   - Purpose: Caching and job queue
   - Installation: `brew install redis` (macOS)

4. **Git**
   - Version: 2.30+
   - Purpose: Version control
   - Installation: Pre-installed on most systems

5. **Node.js**
   - Version: 18.0+ (for asset compilation)
   - Purpose: JavaScript runtime for Tailwind
   - Installation: `brew install node` (macOS)

6. **Yarn**
   - Version: 1.22+
   - Purpose: JavaScript package management
   - Installation: `npm install -g yarn`

#### Development Tools
1. **Code Editor**
   - Recommended: VS Code, RubyMine, or Sublime Text
   - Required Extensions:
     - Ruby LSP or Solargraph
     - Rails snippets
     - Tailwind CSS IntelliSense

2. **Database Client**
   - Options: TablePlus, pgAdmin, or DBeaver
   - Purpose: Database management and queries

3. **API Testing**
   - Options: Postman, Insomnia, or HTTPie
   - Purpose: Testing API endpoints

4. **Redis Client**
   - Options: RedisInsight or Medis
   - Purpose: Redis monitoring and debugging

### Command Line Tools

```bash
# Required system dependencies
sudo apt-get update
sudo apt-get install -y \
  build-essential \
  libpq-dev \
  nodejs \
  yarn \
  redis-server \
  postgresql \
  git \
  curl \
  libssl-dev \
  libreadline-dev \
  zlib1g-dev \
  libyaml-dev \
  libffi-dev

# Ruby installation (using rbenv)
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
source ~/.bashrc

git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
rbenv install 3.2.0
rbenv global 3.2.0

# Verify installations
ruby -v    # Should show 3.2.0
rails -v   # Should show 7.1.0+
psql --version  # Should show 15.0+
redis-server --version  # Should show 7.0+
```

### Service Accounts Required

1. **Stripe Account**
   - URL: https://stripe.com
   - Requirements: Business verification
   - Test Mode: Available immediately

2. **SendGrid Account**
   - URL: https://sendgrid.com
   - Free Tier: 100 emails/day
   - Requirements: Domain verification

3. **Heroku Account**
   - URL: https://heroku.com
   - Requirements: Credit card for addons
   - Free Tier: No longer available

4. **AWS Account** (Future)
   - URL: https://aws.amazon.com
   - Service: S3 for file storage
   - Free Tier: 5GB storage for 12 months

5. **GitHub Account**
   - URL: https://github.com
   - Purpose: Code repository
   - Requirements: None

### Monitoring and Analytics (Recommended)

1. **Error Tracking**
   - Options: Honeybadger, Sentry, or Rollbar
   - Purpose: Production error monitoring

2. **Performance Monitoring**
   - Options: New Relic, Scout APM, or AppSignal
   - Purpose: Application performance tracking

3. **Uptime Monitoring**
   - Options: UptimeRobot, Pingdom, or StatusCake
   - Purpose: Service availability monitoring

4. **Analytics**
   - Options: Google Analytics, Plausible, or Fathom
   - Purpose: User behavior tracking

## Development Progress

### Completed Milestones ✅

#### Milestone 1: Project Foundation & Setup (Session 1)
- ✅ Rails 7.1.5 application with PostgreSQL and Tailwind CSS
- ✅ Core dependencies (Devise, Sidekiq, Stripe, SendGrid, RSpec)
- ✅ Professional application layout with responsive navigation
- ✅ Landing page with features and pricing sections
- ✅ Development environment with Redis and Sidekiq
- ✅ Complete documentation and project setup

#### Milestone 2: User Authentication System (Session 2)
- ✅ Devise integration with custom controllers
- ✅ User model with custom fields (name, timezone, marketing preferences, soft delete)
- ✅ Professional authentication UI with Tailwind CSS
- ✅ Registration, login, password reset flows
- ✅ Email confirmation system
- ✅ Secure authentication with proper validations

#### Milestone 3: User Dashboard & Profile Management (Session 2)
- ✅ User dashboard with account status widgets
- ✅ Comprehensive profile editing with all custom fields
- ✅ Settings controller with multiple management sections
- ✅ Account deletion with soft delete implementation
- ✅ GDPR-compliant data export functionality
- ✅ Professional UI with clear navigation and user feedback

#### Session 3 Follow-up: UI/UX Fixes & Testing (January 2025)
- ✅ Comprehensive Playwright browser testing of all functionality
- ✅ Fixed Tailwind CSS loading issue causing completely unstyled pages
- ✅ Fixed sign out routing error with proper DELETE method implementation
- ✅ Created Stimulus dropdown controller for interactive user menu
- ✅ Verified all authentication flows work with proper styling and interaction

#### Session 4: Subscription & Billing System (January 2025)
- ✅ Complete Stripe integration with environment-based configuration
- ✅ Subscription model with three tiers (Free, Standard $19/mo, Premium $49/mo)  
- ✅ Professional pricing page with current plan status display
- ✅ Dashboard integration showing subscription tier and pricing
- ✅ Stripe webhook system with signature verification and event handling
- ✅ Automatic free subscription creation for new users
- ✅ Subscription management controller with tier comparison
- ✅ Navigation and UI updates for subscription access
- ✅ Comprehensive testing verification of all subscription functionality

#### Session 5: Admin Dashboard & System Management (January 2025)
- ✅ Complete AdminUser authentication system with Devise integration
- ✅ Professional admin dashboard with real-time metrics and visual charts
- ✅ Advanced user management with search, filtering, pagination (Ransack + Kaminari)
- ✅ User impersonation system for customer support with session tracking
- ✅ System health monitoring (database, Redis, Sidekiq status and performance)
- ✅ Comprehensive admin UI with secure authorization and responsive design
- ✅ Integration with Sidekiq web interface and system resource monitoring

#### Session 6: Email System Implementation (January 2025)
- ✅ Complete SendGrid integration with environment-based SMTP configuration
- ✅ UserMailer system with 8 professional email types (welcome, auth, billing, security)
- ✅ Professional HTML and text email templates with responsive design and branding
- ✅ Background email processing via EmailJob with Sidekiq integration and retry logic
- ✅ Devise integration with custom mailer configuration for authentication workflows
- ✅ Development email preview system accessible at `/rails/mailers` for testing
- ✅ Email lifecycle integration (welcome emails, deletion notifications, billing alerts)
- ✅ GDPR-compliant email communications with proper data retention messaging

#### Session 7: Background Jobs & Infrastructure Implementation (January 2025)
- ✅ Enhanced Sidekiq configuration with production-optimized settings and comprehensive middleware
- ✅ Five robust background job classes with error handling (UserExport, DeleteFile, StripeWebhook, MetricsCalculation, DataCleanup)
- ✅ Scheduled jobs system using sidekiq-cron for automated daily/weekly/monthly maintenance
- ✅ Professional error handling system with custom error pages and ApplicationError hierarchy
- ✅ Complete audit logging system with AuditLog model for security compliance and activity tracking
- ✅ Structured logging infrastructure with JSON formatting and request ID tracking
- ✅ Data export email template for GDPR compliance notifications

### Next Development Phase

#### Ready for Implementation
- **Milestone 8**: Testing suite with 90%+ coverage
- **Milestone 9**: Security & compliance implementation
- **Milestone 10**: Production deployment

### Current Status
- **Total Completion**: 70% (7 of 10 milestones)
- **Core Authentication**: 100% complete with user dashboard
- **Subscription System**: 100% complete with paid tiers ready to activate  
- **Admin Dashboard**: 100% complete with comprehensive management tools
- **Email System**: 100% complete with professional templates and background processing
- **Background Infrastructure**: 100% complete with job processing and automated maintenance
- **User Experience**: Professional and modern across all interfaces
- **Security**: Properly implemented with soft delete, GDPR compliance, audit logging, and admin security
- **System Monitoring**: Real-time health checks, performance metrics, and automated maintenance
- **Next Priority**: Comprehensive testing suite implementation

## Development Workflow

### Git Branch Strategy
```
main ✅ (Milestones 1-5 completed)
├── develop
│   ├── feature/email-system (next)
│   ├── feature/background-jobs
│   └── feature/testing-suite
├── staging
└── hotfix/critical-bug-fix
```

### Environment Strategy
1. **Development**: Local machine with SQLite/PostgreSQL
2. **Test**: Automated testing environment
3. **Staging**: Heroku staging app (mirror of production)
4. **Production**: Heroku production app

### Deployment Pipeline
1. Code push to feature branch
2. Run test suite (RSpec)
3. Code review via pull request
4. Merge to develop
5. Deploy to staging
6. QA testing
7. Merge to main
8. Deploy to production

## Performance Targets

### Page Load Times
- Landing page: < 1.5 seconds
- Dashboard: < 2 seconds
- Admin pages: < 3 seconds

### Database Performance
- Simple queries: < 50ms
- Complex queries: < 200ms
- Background jobs: < 30 seconds

### Scalability Targets
- Concurrent users: 1,000+
- Requests per minute: 10,000+
- Database connections: 100 (with pooling)
- Background job throughput: 1,000 jobs/minute

## Cost Estimates

### Development Phase
- Domain name: $15/year
- Development tools: Free (open source)
- Test services: Free tiers

### Production Launch (Monthly)
- Heroku Professional Dyno: $25-50
- Heroku Postgres: $9-50
- Heroku Redis: $15-30
- SendGrid: $15-20
- Monitoring tools: $20-50
- **Total**: $84-200/month

### Scaling Costs (Monthly)
- Multiple dynos: $200-500
- Larger database: $200-400
- Premium Redis: $100-200
- Higher email volume: $80-300
- **Total**: $580-1,400/month