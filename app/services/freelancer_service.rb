class FreelancerService
  attr_reader :user, :base_url

  def initialize(user)
    @user = user
    @token_refresh_attempted = false

    # Allow initialization if user has valid token or can refresh expired token
    unless @user.freelancer_token_valid? || @user.freelancer_can_refresh?
      raise ArgumentError, 'User must have valid Freelancer connection or ability to refresh. Please reauthorize.'
    end

    @base_url = freelancer_environment == 'production' ?
      'https://www.freelancer.com' :
      'https://www.freelancer-sandbox.com'
  end

  def get_user_info
    make_request('GET', '/api/users/0.1/self/')
  end

  def get_projects(limit: 10)
    make_request('GET', "/api/projects/0.1/projects/?limit=#{limit}")
  end

  def get_bids(limit: 10)
    make_request('GET', "/api/projects/0.1/bids/?bidders[]=#{@user.freelancer_user_id}&limit=#{limit}")
  end

  def test_connection
    user_info = get_user_info
    !!(user_info && user_info.dig('result', 'id').present?)
  rescue
    false
  end

  # Financial data methods for project owners
  def get_financial_milestones(limit: 50)
    make_request('GET', "/api/projects/0.1/milestones/?project_owners[]=#{@user.freelancer_user_id}&limit=#{limit}&user_details=true&user_financial_details=true")
  end

  def get_projects_with_financial_details(limit: 50)
    make_request('GET', "/api/projects/0.1/projects/?owners[]=#{@user.freelancer_user_id}&limit=#{limit}&user_details=true&user_financial_details=true&selected_bids=true")
  end

  def get_hourly_contracts(limit: 50)
    make_request('GET', "/api/projects/0.1/hourly_contracts/?project_owner_ids[]=#{@user.freelancer_user_id}&limit=#{limit}&billing_details=true&invoice_details=true")
  end

  def get_comprehensive_financial_summary
    # Get milestones (payments made)
    milestones = get_financial_milestones

    # Get projects with bid details
    projects = get_projects_with_financial_details

    # Get hourly contracts and invoices
    hourly_contracts = get_hourly_contracts

    {
      milestones: process_milestone_data(milestones),
      projects: process_project_data(projects),
      hourly_contracts: process_hourly_contract_data(hourly_contracts),
      summary: calculate_comprehensive_financial_summary(milestones, projects, hourly_contracts)
    }
  end

  def refresh_token!
    return false unless @user.freelancer_can_refresh?

    Rails.logger.info "Freelancer API: Attempting to refresh token for user #{@user.id}"

    connection = Faraday.new(url: token_endpoint_url) do |conn|
      conn.request :url_encoded
      conn.response :json
    end

    response = connection.post do |req|
      req.body = {
        'grant_type' => 'refresh_token',
        'refresh_token' => @user.freelancer_refresh_token,
        'client_id' => freelancer_client_id,
        'client_secret' => freelancer_client_secret
      }
    end

    if response.success?
      token_data = response.body

      # Validate required fields are present
      unless token_data['access_token'].present?
        Rails.logger.error "Freelancer token refresh failed: No access_token in response"
        return false
      end

      @user.update!(
        freelancer_access_token: token_data['access_token'],
        freelancer_refresh_token: token_data['refresh_token'] || @user.freelancer_refresh_token,
        freelancer_token_expires_at: Time.current + (token_data['expires_in'] || 2592000).seconds,
        freelancer_scopes: token_data['scope'] || @user.freelancer_scopes
      )

      Rails.logger.info "Freelancer API: Successfully refreshed token for user #{@user.id}"
      @token_refresh_attempted = false # Reset for future requests
      true
    else
      Rails.logger.error "Freelancer token refresh failed: #{response.status} - #{response.body}"

      # If refresh token is invalid, we might need to clear it
      if response.status == 400 && response.body.to_s.include?('invalid_grant')
        Rails.logger.warn "Freelancer refresh token appears invalid for user #{@user.id}"
      end

      false
    end
  rescue => e
    Rails.logger.error "Freelancer token refresh error: #{e.message}"
    false
  end

  private

  def process_milestone_data(milestones_response)
    return [] unless milestones_response&.dig('result', 'milestones')

    milestones_response['result']['milestones'].map do |milestone|
      {
        id: milestone['id'],
        amount: milestone['amount'],
        currency: milestone.dig('currency', 'code'),
        status: milestone['status'],
        description: milestone['description'],
        created_at: milestone['time_created'],
        released_at: milestone['time_released'],
        project_id: milestone['project_id'],
        freelancer_id: milestone['bidder_id'],
        freelancer_name: milestone.dig('bidder', 'display_name') || milestone.dig('bidder', 'username')
      }
    end
  end

  def process_project_data(projects_response)
    return [] unless projects_response&.dig('result', 'projects')

    projects_response['result']['projects'].map do |project|
      selected_bid = project.dig('selected_bids', 0) # Get the winning bid

      {
        id: project['id'],
        title: project['title'],
        description: project['description'],
        status: project['status'],
        budget_min: project.dig('budget', 'minimum'),
        budget_max: project.dig('budget', 'maximum'),
        currency: project.dig('currency', 'code'),
        created_at: project['submit_date'],
        selected_bid: selected_bid ? {
          amount: selected_bid['amount'],
          freelancer_id: selected_bid['bidder_id'],
          freelancer_name: selected_bid.dig('bidder', 'display_name') || selected_bid.dig('bidder', 'username')
        } : nil
      }
    end
  end

  def process_hourly_contract_data(contracts_response)
    return [] unless contracts_response&.dig('result', 'hourly_contracts')

    contracts_response['result']['hourly_contracts'].map do |contract|
      invoices = contract['invoices'] || []

      {
        id: contract['id'],
        project_id: contract['project_id'],
        freelancer_id: contract['bidder_id'],
        project_title: contract.dig('project', 'title'),
        freelancer_name: contract.dig('bidder', 'display_name') || contract.dig('bidder', 'username'),
        hourly_rate: contract['amount'],
        currency: contract.dig('currency', 'code'),
        status: contract['status'],
        total_hours: invoices.sum { |inv| inv['hours'] || 0 },
        total_amount: invoices.sum { |inv| inv['amount'] || 0 },
        invoices: invoices.map do |invoice|
          {
            id: invoice['id'],
            amount: invoice['amount'],
            hours: invoice['hours'],
            description: invoice['description'],
            status: invoice['status'],
            created_at: invoice['time_created'],
            paid_at: invoice['time_paid']
          }
        end
      }
    end
  end

  def calculate_financial_summary(milestones_response, projects_response)
    milestones = process_milestone_data(milestones_response)

    total_paid = milestones.sum { |m| m[:amount] || 0 }
    total_pending = milestones.select { |m| m[:status] == 'pending' }.sum { |m| m[:amount] || 0 }
    total_released = milestones.select { |m| m[:status] == 'cleared' }.sum { |m| m[:amount] || 0 }

    {
      total_projects: process_project_data(projects_response).count,
      total_milestones: milestones.count,
      total_amount_paid: total_paid,
      total_pending_payments: total_pending,
      total_released_payments: total_released,
      unique_freelancers_paid: milestones.map { |m| m[:freelancer_id] }.uniq.compact.count
    }
  end

  def calculate_comprehensive_financial_summary(milestones_response, projects_response, hourly_contracts_response)
    milestones = process_milestone_data(milestones_response)
    hourly_contracts = process_hourly_contract_data(hourly_contracts_response)

    # Milestone totals
    milestone_total = milestones.sum { |m| m[:amount] || 0 }
    milestone_pending = milestones.select { |m| m[:status] == 'pending' }.sum { |m| m[:amount] || 0 }
    milestone_released = milestones.select { |m| m[:status] == 'cleared' }.sum { |m| m[:amount] || 0 }

    # Hourly contract totals
    hourly_total = hourly_contracts.sum { |c| c[:total_amount] || 0 }
    hourly_hours = hourly_contracts.sum { |c| c[:total_hours] || 0 }

    # Combined totals
    all_freelancer_ids = (
      milestones.map { |m| m[:freelancer_id] } +
      hourly_contracts.map { |c| c[:freelancer_id] }
    ).uniq.compact

    {
      # Project counts
      total_projects: process_project_data(projects_response).count,
      total_fixed_projects: milestones.map { |m| m[:project_id] }.uniq.count,
      total_hourly_projects: hourly_contracts.count,

      # Milestone payments
      total_milestones: milestones.count,
      milestone_total_paid: milestone_total,
      milestone_pending: milestone_pending,
      milestone_released: milestone_released,

      # Hourly payments
      total_hourly_contracts: hourly_contracts.count,
      hourly_total_paid: hourly_total,
      total_hours_worked: hourly_hours,

      # Combined totals
      grand_total_paid: milestone_total + hourly_total,
      unique_freelancers_paid: all_freelancer_ids.count,

      # Payment method breakdown
      payment_breakdown: {
        milestones: milestone_total,
        hourly: hourly_total
      }
    }
  end

  def make_request(method, path, params = {})
    # Ensure we have a valid token before making request
    ensure_valid_token!

    connection = Faraday.new(url: @base_url) do |conn|
      conn.response :json
      conn.request :json if method.upcase == 'POST'
    end

    response = connection.send(method.downcase) do |req|
      req.url path
      req.headers['Freelancer-OAuth-V1'] = @user.freelancer_access_token
      req.body = params if method.upcase == 'POST' && params.any?
    end

    if response.success?
      response.body
    else
      Rails.logger.error "Freelancer API error: #{response.status} - #{response.body}"

      # If unauthorized and we haven't tried refreshing yet, try once
      if response.status == 401 && !@token_refresh_attempted && @user.freelancer_can_refresh?
        Rails.logger.info "Freelancer API: Attempting token refresh due to 401 response"
        @token_refresh_attempted = true

        if refresh_token!
          # Reset auth header with new token and retry
          return make_request(method, path, params)
        else
          Rails.logger.error "Freelancer API: Token refresh failed, cannot retry request"
        end
      end

      nil
    end
  rescue => e
    Rails.logger.error "Freelancer API request error: #{e.message}"
    nil
  end

  def ensure_valid_token!
    # If token is expired or expiring soon, try to refresh
    if @user.freelancer_needs_refresh? && @user.freelancer_can_refresh? && !@token_refresh_attempted
      Rails.logger.info "Freelancer API: Proactively refreshing token before request"
      refresh_token!
    elsif @user.freelancer_token_expired? && !@user.freelancer_can_refresh?
      raise ArgumentError, 'Freelancer token expired and cannot be refreshed. User needs to reauthorize.'
    elsif !@user.freelancer_token_valid? && !@user.freelancer_can_refresh?
      raise ArgumentError, 'No valid Freelancer token available and cannot refresh. User needs to authorize.'
    end
  end

  def token_endpoint_url
    base_auth_url = freelancer_environment == 'production' ?
      'https://accounts.freelancer.com' :
      'https://accounts.freelancer-sandbox.com'
    "#{base_auth_url}/oauth/token"
  end

  def freelancer_environment
    ENV['FREELANCER_ENVIRONMENT'] || 'sandbox'
  end

  def freelancer_client_id
    if freelancer_environment == 'production'
      ENV['FREELANCER_CLIENT_ID']
    else
      ENV['FREELANCER_SANDBOX_CLIENT_ID'] || ENV['FREELANCER_CLIENT_ID']
    end
  end

  def freelancer_client_secret
    if freelancer_environment == 'production'
      ENV['FREELANCER_CLIENT_SECRET']
    else
      ENV['FREELANCER_SANDBOX_CLIENT_SECRET'] || ENV['FREELANCER_CLIENT_SECRET']
    end
  end
end