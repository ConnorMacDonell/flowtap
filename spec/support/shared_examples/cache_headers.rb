# Shared examples for testing cache-control headers
# Required by Intuit security requirements for QBO integration
#
# Usage:
#   it_behaves_like 'sets security cache headers' do
#     let(:make_request) { get :index }
#   end

RSpec.shared_examples 'sets security cache headers' do
  it 'sets Cache-Control header to prevent caching' do
    make_request
    expect(response.headers['Cache-Control']).to eq('no-cache, no-store, must-revalidate')
  end

  it 'sets Pragma header to no-cache for HTTP/1.0 compatibility' do
    make_request
    expect(response.headers['Pragma']).to eq('no-cache')
  end

  it 'sets Expires header to 0 to prevent caching' do
    make_request
    expect(response.headers['Expires']).to eq('0')
  end
end
