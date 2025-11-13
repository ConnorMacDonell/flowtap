# frozen_string_literal: true

# Configure session cookie security settings
# - httponly: true prevents JavaScript access (XSS protection)
# - secure: true enforces HTTPS-only transmission (MITM protection)
# - same_site: :lax prevents CSRF while allowing normal navigation
Rails.application.config.session_store :cookie_store,
  key: '_flowtap_session',
  httponly: true,
  secure: Rails.env.production?,
  same_site: :lax
