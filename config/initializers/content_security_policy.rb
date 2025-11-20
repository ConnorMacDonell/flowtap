# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.font_src    :self, :https, :data
    policy.img_src     :self, :https, :data
    policy.object_src  :none

    # Allow scripts from self - nonces will be used for any inline scripts
    policy.script_src  :self, :https

    # Allow styles from self and unsafe-inline for Tailwind utility classes
    policy.style_src   :self, :https, :unsafe_inline

    # Allow connections to Stripe and Intuit APIs
    policy.connect_src :self, :https, "https://api.stripe.com", "https://*.intuit.com"

    # Allow iframes from Stripe (for checkout/payment forms)
    policy.frame_src   "https://js.stripe.com", "https://checkout.stripe.com"
  end

  # Generate session nonces for permitted importmap and inline scripts
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w(script-src)

  # Start in report-only mode to monitor violations without breaking functionality
  # Once confirmed working, set to false to enforce the policy
  config.content_security_policy_report_only = false
end
