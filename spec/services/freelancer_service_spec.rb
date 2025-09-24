require 'rails_helper'

RSpec.describe FreelancerService, type: :service do
  let(:user) { create(:user, :with_freelancer_connection) }
  let(:freelancer_service) { described_class.new(user) }

  describe '#initialize' do
    context 'with valid Freelancer connection' do
      it 'initializes successfully' do
        expect { freelancer_service }.not_to raise_error
      end

      it 'sets sandbox base URL when environment is sandbox' do
        ENV['FREELANCER_ENVIRONMENT'] = 'sandbox'
        service = described_class.new(user)
        expect(service.base_url).to eq('https://www.freelancer-sandbox.com')
      end

      it 'sets production base URL when environment is production' do
        ENV['FREELANCER_ENVIRONMENT'] = 'production'
        service = described_class.new(user)
        expect(service.base_url).to eq('https://www.freelancer.com')
      end
    end

    context 'with invalid Freelancer connection' do
      let(:user_without_connection) { create(:user) }

      it 'raises ArgumentError when user has no valid connection' do
        expect { described_class.new(user_without_connection) }.to raise_error(
          ArgumentError, 'User must have valid Freelancer connection or ability to refresh'
        )
      end
    end
  end

  describe '#get_user_info' do
    it 'calls make_request with correct parameters' do
      expect(freelancer_service).to receive(:make_request).with('GET', '/api/users/0.1/self/')
      freelancer_service.get_user_info
    end
  end

  describe '#get_projects' do
    it 'calls make_request with default limit' do
      expect(freelancer_service).to receive(:make_request).with('GET', '/api/projects/0.1/projects/?limit=10')
      freelancer_service.get_projects
    end

    it 'accepts custom limit parameter' do
      expect(freelancer_service).to receive(:make_request).with('GET', '/api/projects/0.1/projects/?limit=5')
      freelancer_service.get_projects(limit: 5)
    end
  end

  describe '#get_bids' do
    it 'calls make_request with user ID in parameters' do
      expect(freelancer_service).to receive(:make_request).with('GET', "/api/projects/0.1/bids/?bidders[]=#{user.freelancer_user_id}&limit=10")
      freelancer_service.get_bids
    end
  end

  describe '#test_connection' do
    it 'returns true when user info request succeeds' do
      allow(freelancer_service).to receive(:get_user_info).and_return({
        'result' => { 'id' => '12345' }
      })

      expect(freelancer_service.test_connection).to be true
    end

    it 'returns false when user info request fails' do
      allow(freelancer_service).to receive(:get_user_info).and_return(nil)

      expect(freelancer_service.test_connection).to be false
    end

    it 'returns false when user info request raises exception' do
      allow(freelancer_service).to receive(:get_user_info).and_raise(StandardError)

      expect(freelancer_service.test_connection).to be false
    end
  end

  describe '#get_financial_milestones' do
    it 'calls make_request with correct parameters for project owner' do
      expected_path = "/api/projects/0.1/milestones/?project_owners[]=#{user.freelancer_user_id}&limit=50&user_details=true&user_financial_details=true"
      expect(freelancer_service).to receive(:make_request).with('GET', expected_path)
      freelancer_service.get_financial_milestones
    end

    it 'accepts custom limit parameter' do
      expected_path = "/api/projects/0.1/milestones/?project_owners[]=#{user.freelancer_user_id}&limit=25&user_details=true&user_financial_details=true"
      expect(freelancer_service).to receive(:make_request).with('GET', expected_path)
      freelancer_service.get_financial_milestones(limit: 25)
    end
  end

  describe '#get_projects_with_financial_details' do
    it 'calls make_request with correct parameters' do
      expected_path = "/api/projects/0.1/projects/?owners[]=#{user.freelancer_user_id}&limit=50&user_details=true&user_financial_details=true&selected_bids=true"
      expect(freelancer_service).to receive(:make_request).with('GET', expected_path)
      freelancer_service.get_projects_with_financial_details
    end

    it 'accepts custom limit parameter' do
      expected_path = "/api/projects/0.1/projects/?owners[]=#{user.freelancer_user_id}&limit=20&user_details=true&user_financial_details=true&selected_bids=true"
      expect(freelancer_service).to receive(:make_request).with('GET', expected_path)
      freelancer_service.get_projects_with_financial_details(limit: 20)
    end
  end

  describe '#get_hourly_contracts' do
    it 'calls make_request with correct parameters' do
      expected_path = "/api/projects/0.1/hourly_contracts/?project_owner_ids[]=#{user.freelancer_user_id}&limit=50&billing_details=true&invoice_details=true"
      expect(freelancer_service).to receive(:make_request).with('GET', expected_path)
      freelancer_service.get_hourly_contracts
    end

    it 'accepts custom limit parameter' do
      expected_path = "/api/projects/0.1/hourly_contracts/?project_owner_ids[]=#{user.freelancer_user_id}&limit=30&billing_details=true&invoice_details=true"
      expect(freelancer_service).to receive(:make_request).with('GET', expected_path)
      freelancer_service.get_hourly_contracts(limit: 30)
    end
  end

  describe '#get_comprehensive_financial_summary' do
    let(:mock_milestones_response) do
      {
        'result' => {
          'milestones' => [
            {
              'id' => 123,
              'amount' => 500.0,
              'currency' => { 'code' => 'USD' },
              'status' => 'cleared',
              'description' => 'Payment 1',
              'time_created' => 1640995200,
              'time_released' => 1640995800,
              'project_id' => 456,
              'bidder_id' => 789,
              'bidder' => { 'display_name' => 'John Doe' }
            }
          ]
        }
      }
    end

    let(:mock_projects_response) do
      {
        'result' => {
          'projects' => [
            {
              'id' => 456,
              'title' => 'Test Project',
              'description' => 'Test Description',
              'status' => 'complete',
              'budget' => { 'minimum' => 400, 'maximum' => 600 },
              'currency' => { 'code' => 'USD' },
              'submit_date' => 1640995000,
              'selected_bids' => [
                {
                  'amount' => 500,
                  'bidder_id' => 789,
                  'bidder' => { 'display_name' => 'John Doe' }
                }
              ]
            }
          ]
        }
      }
    end

    let(:mock_hourly_response) do
      {
        'result' => {
          'hourly_contracts' => [
            {
              'id' => 321,
              'project_id' => 654,
              'bidder_id' => 987,
              'project' => { 'title' => 'Hourly Project' },
              'bidder' => { 'display_name' => 'Jane Smith' },
              'amount' => 50.0,
              'currency' => { 'code' => 'USD' },
              'status' => 'active',
              'invoices' => [
                {
                  'id' => 111,
                  'amount' => 400.0,
                  'hours' => 8.0,
                  'description' => 'Week 1',
                  'status' => 'paid',
                  'time_created' => 1640995200,
                  'time_paid' => 1640995800
                }
              ]
            }
          ]
        }
      }
    end

    before do
      allow(freelancer_service).to receive(:get_financial_milestones).and_return(mock_milestones_response)
      allow(freelancer_service).to receive(:get_projects_with_financial_details).and_return(mock_projects_response)
      allow(freelancer_service).to receive(:get_hourly_contracts).and_return(mock_hourly_response)
    end

    it 'returns comprehensive financial summary with all data types' do
      result = freelancer_service.get_comprehensive_financial_summary

      expect(result).to have_key(:milestones)
      expect(result).to have_key(:projects)
      expect(result).to have_key(:hourly_contracts)
      expect(result).to have_key(:summary)
    end

    it 'processes milestone data correctly' do
      result = freelancer_service.get_comprehensive_financial_summary

      milestone = result[:milestones].first
      expect(milestone[:id]).to eq(123)
      expect(milestone[:amount]).to eq(500.0)
      expect(milestone[:currency]).to eq('USD')
      expect(milestone[:status]).to eq('cleared')
      expect(milestone[:freelancer_name]).to eq('John Doe')
    end

    it 'processes project data correctly' do
      result = freelancer_service.get_comprehensive_financial_summary

      project = result[:projects].first
      expect(project[:id]).to eq(456)
      expect(project[:title]).to eq('Test Project')
      expect(project[:selected_bid][:amount]).to eq(500)
      expect(project[:selected_bid][:freelancer_name]).to eq('John Doe')
    end

    it 'processes hourly contract data correctly' do
      result = freelancer_service.get_comprehensive_financial_summary

      contract = result[:hourly_contracts].first
      expect(contract[:id]).to eq(321)
      expect(contract[:project_title]).to eq('Hourly Project')
      expect(contract[:freelancer_name]).to eq('Jane Smith')
      expect(contract[:total_hours]).to eq(8.0)
      expect(contract[:total_amount]).to eq(400.0)
    end

    it 'calculates financial summary correctly' do
      result = freelancer_service.get_comprehensive_financial_summary

      summary = result[:summary]
      expect(summary[:total_projects]).to eq(1)
      expect(summary[:total_milestones]).to eq(1)
      expect(summary[:total_hourly_contracts]).to eq(1)
      expect(summary[:milestone_total_paid]).to eq(500.0)
      expect(summary[:hourly_total_paid]).to eq(400.0)
      expect(summary[:grand_total_paid]).to eq(900.0)
      expect(summary[:total_hours_worked]).to eq(8.0)
      expect(summary[:unique_freelancers_paid]).to eq(2)
    end
  end

  describe '#refresh_token!' do
    before do
      ENV['FREELANCER_CLIENT_ID'] = 'test_client_id'
      ENV['FREELANCER_CLIENT_SECRET'] = 'test_client_secret'
    end

    context 'when refresh token is present' do
      it 'successfully refreshes token' do
        mock_connection = double('Faraday::Connection')
        mock_request = double('Faraday::Request')
        mock_response = double('Faraday::Response', success?: true, body: {
          'access_token' => 'new_access_token',
          'refresh_token' => 'new_refresh_token',
          'expires_in' => 2592000,
          'scope' => 'basic 1 2'
        })

        allow(Faraday).to receive(:new).and_return(mock_connection)
        allow(mock_connection).to receive(:post).and_yield(mock_request).and_return(mock_response)
        allow(mock_request).to receive(:body=)

        original_time = Time.current
        allow(Time).to receive(:current).and_return(original_time)

        result = freelancer_service.refresh_token!

        expect(result).to be true
        user.reload
        expect(user.freelancer_access_token).to eq('new_access_token')
        expect(user.freelancer_refresh_token).to eq('new_refresh_token')
        expect(user.freelancer_token_expires_at).to be_within(1.second).of(original_time + 2592000.seconds)
        expect(user.freelancer_scopes).to eq('basic 1 2')
      end

      it 'handles failed token refresh' do
        mock_connection = double('Faraday::Connection')
        mock_request = double('Faraday::Request')
        mock_response = double('Faraday::Response', success?: false, status: 400, body: { 'error' => 'invalid_grant' })

        allow(Faraday).to receive(:new).and_return(mock_connection)
        allow(mock_connection).to receive(:post).and_yield(mock_request).and_return(mock_response)
        allow(mock_request).to receive(:body=)

        result = freelancer_service.refresh_token!

        expect(result).to be false
      end

      it 'handles exceptions during token refresh' do
        allow(Faraday).to receive(:new).and_raise(StandardError, 'Network error')

        result = freelancer_service.refresh_token!

        expect(result).to be false
      end
    end

    context 'when refresh token is not present' do
      before do
        user.update(freelancer_refresh_token: nil)
      end

      it 'returns false without making API call' do
        expect(Faraday).not_to receive(:new)

        result = freelancer_service.refresh_token!

        expect(result).to be false
      end
    end
  end

  describe 'private methods' do
    describe '#freelancer_environment' do
      it 'returns sandbox by default' do
        ENV['FREELANCER_ENVIRONMENT'] = nil
        expect(freelancer_service.send(:freelancer_environment)).to eq('sandbox')
      end

      it 'returns environment variable value when set' do
        ENV['FREELANCER_ENVIRONMENT'] = 'production'
        expect(freelancer_service.send(:freelancer_environment)).to eq('production')
      end
    end

    describe '#freelancer_client_id' do
      it 'returns sandbox client ID for sandbox environment' do
        ENV['FREELANCER_ENVIRONMENT'] = 'sandbox'
        ENV['FREELANCER_SANDBOX_CLIENT_ID'] = 'sandbox_id'
        ENV['FREELANCER_CLIENT_ID'] = 'prod_id'

        expect(freelancer_service.send(:freelancer_client_id)).to eq('sandbox_id')
      end

      it 'falls back to regular client ID when sandbox ID not set' do
        ENV['FREELANCER_ENVIRONMENT'] = 'sandbox'
        ENV['FREELANCER_SANDBOX_CLIENT_ID'] = nil
        ENV['FREELANCER_CLIENT_ID'] = 'prod_id'

        expect(freelancer_service.send(:freelancer_client_id)).to eq('prod_id')
      end

      it 'returns production client ID for production environment' do
        ENV['FREELANCER_ENVIRONMENT'] = 'production'
        ENV['FREELANCER_CLIENT_ID'] = 'prod_id'

        expect(freelancer_service.send(:freelancer_client_id)).to eq('prod_id')
      end
    end

    describe '#process_milestone_data' do
      it 'processes milestone data correctly' do
        response = {
          'result' => {
            'milestones' => [
              {
                'id' => 123,
                'amount' => 500.0,
                'currency' => { 'code' => 'USD' },
                'status' => 'cleared',
                'description' => 'Payment for website',
                'time_created' => 1640995200,
                'time_released' => 1640995800,
                'project_id' => 456,
                'bidder_id' => 789,
                'bidder' => { 'display_name' => 'John Doe' }
              }
            ]
          }
        }

        result = freelancer_service.send(:process_milestone_data, response)

        expect(result).to be_an(Array)
        expect(result.length).to eq(1)

        milestone = result.first
        expect(milestone[:id]).to eq(123)
        expect(milestone[:amount]).to eq(500.0)
        expect(milestone[:currency]).to eq('USD')
        expect(milestone[:status]).to eq('cleared')
        expect(milestone[:description]).to eq('Payment for website')
        expect(milestone[:project_id]).to eq(456)
        expect(milestone[:freelancer_id]).to eq(789)
        expect(milestone[:freelancer_name]).to eq('John Doe')
      end

      it 'returns empty array when no milestones in response' do
        response = { 'result' => {} }
        result = freelancer_service.send(:process_milestone_data, response)
        expect(result).to eq([])
      end

      it 'handles nil response' do
        result = freelancer_service.send(:process_milestone_data, nil)
        expect(result).to eq([])
      end
    end

    describe '#process_project_data' do
      it 'processes project data correctly' do
        response = {
          'result' => {
            'projects' => [
              {
                'id' => 456,
                'title' => 'Build Website',
                'description' => 'Need a modern website',
                'status' => 'complete',
                'budget' => { 'minimum' => 400, 'maximum' => 600 },
                'currency' => { 'code' => 'USD' },
                'submit_date' => 1640995000,
                'selected_bids' => [
                  {
                    'amount' => 500,
                    'bidder_id' => 789,
                    'bidder' => { 'display_name' => 'John Doe' }
                  }
                ]
              }
            ]
          }
        }

        result = freelancer_service.send(:process_project_data, response)

        expect(result).to be_an(Array)
        expect(result.length).to eq(1)

        project = result.first
        expect(project[:id]).to eq(456)
        expect(project[:title]).to eq('Build Website')
        expect(project[:description]).to eq('Need a modern website')
        expect(project[:status]).to eq('complete')
        expect(project[:budget_min]).to eq(400)
        expect(project[:budget_max]).to eq(600)
        expect(project[:currency]).to eq('USD')
        expect(project[:selected_bid][:amount]).to eq(500)
        expect(project[:selected_bid][:freelancer_name]).to eq('John Doe')
      end

      it 'handles projects without selected bids' do
        response = {
          'result' => {
            'projects' => [
              {
                'id' => 456,
                'title' => 'Build Website',
                'description' => 'Need a modern website',
                'status' => 'active',
                'budget' => { 'minimum' => 400, 'maximum' => 600 },
                'currency' => { 'code' => 'USD' },
                'submit_date' => 1640995000,
                'selected_bids' => []
              }
            ]
          }
        }

        result = freelancer_service.send(:process_project_data, response)
        project = result.first
        expect(project[:selected_bid]).to be_nil
      end

      it 'returns empty array when no projects in response' do
        response = { 'result' => {} }
        result = freelancer_service.send(:process_project_data, response)
        expect(result).to eq([])
      end
    end

    describe '#process_hourly_contract_data' do
      it 'processes hourly contract data correctly' do
        response = {
          'result' => {
            'hourly_contracts' => [
              {
                'id' => 321,
                'project_id' => 654,
                'bidder_id' => 987,
                'project' => { 'title' => 'Hourly Development' },
                'bidder' => { 'display_name' => 'Jane Smith' },
                'amount' => 50.0,
                'currency' => { 'code' => 'USD' },
                'status' => 'active',
                'invoices' => [
                  {
                    'id' => 111,
                    'amount' => 400.0,
                    'hours' => 8.0,
                    'description' => 'Week 1 development',
                    'status' => 'paid',
                    'time_created' => 1640995200,
                    'time_paid' => 1640995800
                  },
                  {
                    'id' => 112,
                    'amount' => 200.0,
                    'hours' => 4.0,
                    'description' => 'Week 2 development',
                    'status' => 'pending',
                    'time_created' => 1641081600,
                    'time_paid' => nil
                  }
                ]
              }
            ]
          }
        }

        result = freelancer_service.send(:process_hourly_contract_data, response)

        expect(result).to be_an(Array)
        expect(result.length).to eq(1)

        contract = result.first
        expect(contract[:id]).to eq(321)
        expect(contract[:project_title]).to eq('Hourly Development')
        expect(contract[:freelancer_name]).to eq('Jane Smith')
        expect(contract[:hourly_rate]).to eq(50.0)
        expect(contract[:total_hours]).to eq(12.0)  # 8 + 4
        expect(contract[:total_amount]).to eq(600.0)  # 400 + 200
        expect(contract[:invoices].length).to eq(2)

        first_invoice = contract[:invoices].first
        expect(first_invoice[:id]).to eq(111)
        expect(first_invoice[:amount]).to eq(400.0)
        expect(first_invoice[:hours]).to eq(8.0)
        expect(first_invoice[:description]).to eq('Week 1 development')
        expect(first_invoice[:status]).to eq('paid')
      end

      it 'handles contracts without invoices' do
        response = {
          'result' => {
            'hourly_contracts' => [
              {
                'id' => 321,
                'project_id' => 654,
                'bidder_id' => 987,
                'project' => { 'title' => 'Hourly Development' },
                'bidder' => { 'display_name' => 'Jane Smith' },
                'amount' => 50.0,
                'currency' => { 'code' => 'USD' },
                'status' => 'active',
                'invoices' => []
              }
            ]
          }
        }

        result = freelancer_service.send(:process_hourly_contract_data, response)
        contract = result.first
        expect(contract[:total_hours]).to eq(0)
        expect(contract[:total_amount]).to eq(0)
        expect(contract[:invoices]).to eq([])
      end

      it 'returns empty array when no contracts in response' do
        response = { 'result' => {} }
        result = freelancer_service.send(:process_hourly_contract_data, response)
        expect(result).to eq([])
      end
    end

    describe '#calculate_comprehensive_financial_summary' do
      let(:milestones_response) do
        {
          'result' => {
            'milestones' => [
              { 'id' => 1, 'amount' => 500.0, 'status' => 'cleared', 'project_id' => 100, 'bidder_id' => 200 },
              { 'id' => 2, 'amount' => 300.0, 'status' => 'pending', 'project_id' => 101, 'bidder_id' => 201 }
            ]
          }
        }
      end

      let(:projects_response) do
        {
          'result' => {
            'projects' => [
              { 'id' => 100, 'title' => 'Project 1' },
              { 'id' => 101, 'title' => 'Project 2' }
            ]
          }
        }
      end

      let(:hourly_response) do
        {
          'result' => {
            'hourly_contracts' => [
              {
                'id' => 1,
                'bidder_id' => 202,
                'invoices' => [
                  { 'amount' => 400.0, 'hours' => 8.0 },
                  { 'amount' => 200.0, 'hours' => 4.0 }
                ]
              }
            ]
          }
        }
      end

      it 'calculates comprehensive totals correctly' do
        result = freelancer_service.send(:calculate_comprehensive_financial_summary, milestones_response, projects_response, hourly_response)

        expect(result[:total_projects]).to eq(2)
        expect(result[:total_fixed_projects]).to eq(2)
        expect(result[:total_hourly_projects]).to eq(1)
        expect(result[:total_milestones]).to eq(2)
        expect(result[:milestone_total_paid]).to eq(800.0)  # 500 + 300
        expect(result[:milestone_pending]).to eq(300.0)     # pending milestone
        expect(result[:milestone_released]).to eq(500.0)    # cleared milestone
        expect(result[:hourly_total_paid]).to eq(600.0)     # 400 + 200
        expect(result[:total_hours_worked]).to eq(12.0)     # 8 + 4
        expect(result[:grand_total_paid]).to eq(1400.0)     # 800 + 600
        expect(result[:unique_freelancers_paid]).to eq(3)   # 200, 201, 202
      end
    end
  end
end