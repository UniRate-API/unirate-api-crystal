require "spec"
require "../src/unirate"

# MockTransport is a test double for UniRate::Transport. It records the last
# request URL and headers and returns whatever its handler block produces, so
# tests exercise the full client (URL building, status mapping, JSON decoding)
# without touching the network.
class MockTransport < UniRate::Transport
  getter last_url : String = ""
  getter last_headers : HTTP::Headers = HTTP::Headers.new

  def initialize(&@handler : String -> UniRate::HTTPResponse)
  end

  def send(url : String, headers : HTTP::Headers, timeout : Int32) : UniRate::HTTPResponse
    @last_url = url
    @last_headers = headers
    @handler.call(url)
  end
end

# ok builds a 200 response with the given JSON body.
def ok(body : String) : UniRate::HTTPResponse
  UniRate::HTTPResponse.new(200, body)
end

# client_for builds a client wired to a mock returning a single canned 200
# body for every request, and yields both so the test can assert on the mock.
def client_for(body : String) : {UniRate::Client, MockTransport}
  mock = MockTransport.new { |_| ok(body) }
  {UniRate::Client.new("test-key", transport: mock), mock}
end

# error_client builds a client whose transport always returns the given
# non-2xx status and body.
def error_client(status : Int32, body : String = "{}") : UniRate::Client
  mock = MockTransport.new { |_| UniRate::HTTPResponse.new(status, body) }
  UniRate::Client.new("test-key", transport: mock)
end
