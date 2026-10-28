module UniRate
  # UniRateError is the base class for every error raised by the client.
  #
  # `status` carries the HTTP status code (0 when there was no HTTP response,
  # e.g. a transport failure or a malformed body) and `body` the raw response
  # body when the server returned one for a non-2xx status. Rescue the base
  # class to catch everything, or a subclass to branch on the kind of failure.
  class UniRateError < Exception
    getter status : Int32
    getter body : String?

    def initialize(message : String, @status : Int32 = 0, @body : String? = nil)
      super(message)
    end
  end

  # 401 — missing or invalid API key.
  class AuthenticationError < UniRateError; end

  # 404 — currency/country not found or no data available.
  class InvalidCurrencyError < UniRateError; end

  # 400 — invalid request parameters (bad date, etc.).
  class InvalidDateError < UniRateError; end

  # 429 — rate limit exceeded.
  class RateLimitError < UniRateError; end

  # 403 / 503 / any other non-2xx status.
  class APIError < UniRateError; end

  # error_for_status maps a non-2xx HTTP status to the matching error,
  # mirroring the shared error-mapping table across all UniRate clients.
  def self.error_for_status(status : Int32, body : String) : UniRateError
    case status
    when 400
      InvalidDateError.new("Invalid request parameters", status, body)
    when 401
      AuthenticationError.new("Missing or invalid API key", status, body)
    when 403
      APIError.new("Endpoint requires a Pro subscription", status, body)
    when 404
      InvalidCurrencyError.new("Currency not found or no data available", status, body)
    when 429
      RateLimitError.new("Rate limit exceeded", status, body)
    when 503
      APIError.new("Service unavailable", status, body)
    else
      APIError.new("API error (status #{status}): #{body}", status, body)
    end
  end
end
