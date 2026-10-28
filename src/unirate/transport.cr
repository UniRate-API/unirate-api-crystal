require "http/client"
require "uri"
require "openssl"

module UniRate
  # HTTPResponse is the minimal result a Transport returns: the HTTP status
  # code and the raw response body.
  struct HTTPResponse
    getter status : Int32
    getter body : String

    def initialize(@status : Int32, @body : String)
    end
  end

  # Transport abstracts the HTTP layer so tests can run without touching the
  # network. Subclass it and implement `send` to perform a GET for the given
  # URL and headers and return an HTTPResponse — including for 4xx/5xx
  # statuses. Only a genuine transport failure should raise.
  abstract class Transport
    abstract def send(url : String, headers : HTTP::Headers, timeout : Int32) : HTTPResponse
  end

  # DefaultTransport is the production Transport, backed by Crystal's stdlib
  # HTTP::Client (TLS included — no third-party shard).
  class DefaultTransport < Transport
    # send performs the HTTP GET. A non-2xx status is returned as a normal
    # HTTPResponse (the client maps it to a typed error); only a genuine
    # transport failure (connection refused, timeout, TLS error) raises a
    # UniRateError.
    def send(url : String, headers : HTTP::Headers, timeout : Int32) : HTTPResponse
      uri = URI.parse(url)
      client = HTTP::Client.new(uri)
      begin
        client.connect_timeout = timeout.seconds
        client.read_timeout = timeout.seconds
        response = client.get(uri.request_target, headers: headers)
        HTTPResponse.new(response.status_code, response.body)
      rescue ex : IO::Error | OpenSSL::Error | Socket::Addrinfo::Error
        raise UniRateError.new("Network error: #{ex.message}")
      ensure
        client.close
      end
    end
  end
end
