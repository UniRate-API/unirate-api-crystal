# UniRate is the official Crystal client for the UniRate API
# (https://unirateapi.com) — free currency exchange rates, historical data, and
# VAT rates.
#
# It depends only on the Crystal standard library (`HTTP::Client` for HTTP,
# `JSON` for decoding, `URI` for query escaping) — zero third-party shards. The
# HTTP layer is injectable via the `Transport` abstract class so tests run
# offline.
#
# ```
# client = UniRate::Client.new("your-api-key")
# rate = client.get_rate(to: "EUR")        # => 0.92
# total = client.convert(100.0, to: "EUR") # => 92.5
# ```
require "json"
require "uri"
require "./unirate/errors"
require "./unirate/transport"
require "./unirate/models"

module UniRate
  # Client is a UniRate API client. Create one with `new`, then call any of the
  # public methods. A Client is immutable and safe to reuse.
  class Client
    # VERSION is the client version, kept in sync with shard.yml.
    VERSION = "0.1.0"

    # DEFAULT_BASE_URL is the UniRate API base URL.
    DEFAULT_BASE_URL = "https://api.unirateapi.com"

    # DEFAULT_TIMEOUT is the default request timeout, in seconds.
    DEFAULT_TIMEOUT = 30

    # new creates a client with the given API key. Optional settings are passed
    # as named arguments:
    #   client = UniRate::Client.new("key")
    #   client = UniRate::Client.new("key", timeout: 10)
    def initialize(
      api_key : String,
      base_url : String = DEFAULT_BASE_URL,
      @timeout : Int32 = DEFAULT_TIMEOUT,
      @transport : Transport = DefaultTransport.new,
    )
      raise AuthenticationError.new("api_key is required") if api_key.empty?
      @api_key = api_key
      @base_url = base_url.rstrip("/")
      @user_agent = "unirate-crystal/#{VERSION}"
    end

    # ---------------------------------------------------------------------
    # Current rates and conversion (free tier)
    # ---------------------------------------------------------------------

    # get_rate returns the current exchange rate from `from` to `to` (how many
    # `to` one `from` buys).
    def get_rate(to : String, from : String = "USD") : Float64
      raise InvalidCurrencyError.new("to is required") if to.empty?
      body = request("/api/rates", [
        {"from", up_or_default(from)},
        {"to", to.upcase},
      ])
      to_f64(get_field(body, "rate"), "rate")
    end

    # get_all_rates returns every current exchange rate for a base currency as
    # a hash of currency code to rate.
    def get_all_rates(from : String = "USD") : Hash(String, Float64)
      body = request("/api/rates", [{"from", up_or_default(from)}])
      to_f64_map(get_field(body, "rates"), "rates")
    end

    # convert converts `amount` from `from` to `to` at the current rate.
    def convert(amount : Float64, to : String, from : String = "USD") : Float64
      raise InvalidCurrencyError.new("to is required") if to.empty?
      body = request("/api/convert", [
        {"from", up_or_default(from)},
        {"to", to.upcase},
        {"amount", format_amount(amount)},
      ])
      to_f64(get_field(body, "result"), "result")
    end

    # get_supported_currencies returns the list of supported currency codes.
    def get_supported_currencies : Array(String)
      body = request("/api/currencies", [] of Tuple(String, String))
      arr = get_field(body, "currencies").as_a?
      raise UniRateError.new("Malformed response: 'currencies' is not an array") unless arr
      arr.map(&.as_s)
    end

    # ---------------------------------------------------------------------
    # Historical data (Pro-gated: returns a 403 APIError on the free tier)
    # ---------------------------------------------------------------------

    # get_historical_rate returns the historical exchange rate from `from` to
    # `to` on `date` (YYYY-MM-DD). Pro-gated.
    def get_historical_rate(date : String, to : String, from : String = "USD") : Float64
      raise InvalidDateError.new("date is required") if date.empty?
      raise InvalidCurrencyError.new("to is required") if to.empty?
      body = request("/api/historical/rates", [
        {"date", date},
        {"amount", "1"},
        {"from", up_or_default(from)},
        {"to", to.upcase},
      ])
      to_f64(get_field(body, "rate"), "rate")
    end

    # get_historical_rates returns every historical exchange rate for a base
    # currency on `date` (YYYY-MM-DD). Pro-gated.
    def get_historical_rates(date : String, base : String = "USD") : Hash(String, Float64)
      raise InvalidDateError.new("date is required") if date.empty?
      body = request("/api/historical/rates", [
        {"date", date},
        {"amount", "1"},
        {"from", up_or_default(base)},
      ])
      to_f64_map(get_field(body, "rates"), "rates")
    end

    # convert_historical converts `amount` from `from` to `to` using the rate
    # on `date` (YYYY-MM-DD). Pro-gated.
    def convert_historical(amount : Float64, from : String, to : String, date : String) : Float64
      if from.empty? || to.empty? || date.empty?
        raise InvalidDateError.new("from, to and date are required")
      end
      body = request("/api/historical/rates", [
        {"date", date},
        {"amount", format_amount(amount)},
        {"from", from.upcase},
        {"to", to.upcase},
      ])
      to_f64(get_field(body, "result"), "result")
    end

    # get_time_series returns a time series of exchange rates between
    # `start_date` and `end_date` (YYYY-MM-DD, up to a 5-year span) as a nested
    # hash {date => {currency => rate}}. Pass an empty `currencies` for every
    # currency, and `amount` <= 0 to default to 1. Pro-gated.
    def get_time_series(
      start_date : String,
      end_date : String,
      base : String = "USD",
      currencies : Array(String) = [] of String,
      amount : Float64 = 1.0,
    ) : Hash(String, Hash(String, Float64))
      if start_date.empty? || end_date.empty?
        raise InvalidDateError.new("start_date and end_date are required")
      end
      amt = amount <= 0 ? 1.0 : amount
      params = [
        {"start_date", start_date},
        {"end_date", end_date},
        {"amount", format_amount(amt)},
        {"base", up_or_default(base)},
      ]
      params << {"currencies", currencies.map(&.upcase).join(",")} unless currencies.empty?
      body = request("/api/historical/timeseries", params)
      data = get_field(body, "data").as_h?
      raise UniRateError.new("Malformed response: missing 'data'") unless data
      out = {} of String => Hash(String, Float64)
      data.each { |date_key, day| out[date_key] = to_f64_map(day, date_key) }
      out
    end

    # get_historical_limits returns per-currency historical-data coverage.
    # Pro-gated.
    def get_historical_limits : HistoricalLimitsResponse
      body = request("/api/historical/limits", [] of Tuple(String, String))
      currencies = {} of String => HistoricalLimit
      if (cur = body["currencies"]?) && (cur_h = cur.as_h?)
        cur_h.each do |code, entry|
          e = entry.as_h
          currencies[code] = HistoricalLimit.new(
            earliest_date: str_field(e, "earliest_date"),
            latest_date: str_field(e, "latest_date"),
            total_days: int_field(e, "total_days"),
            description: str_field(e, "description"),
          )
        end
      end
      HistoricalLimitsResponse.new(
        total_currencies: int_field(body.as_h, "total_currencies"),
        data_source: str_field(body.as_h, "data_source"),
        currencies: currencies,
      )
    end

    # ---------------------------------------------------------------------
    # VAT (free tier)
    # ---------------------------------------------------------------------

    # get_vat_rates returns VAT rates for every supported country.
    def get_vat_rates : VatRatesResponse
      body = request("/api/vat/rates", [] of Tuple(String, String))
      rates = {} of String => VatRate
      if (vr = body["vat_rates"]?) && (vr_h = vr.as_h?)
        vr_h.each { |code, entry| rates[code] = parse_vat_rate(entry) }
      end
      VatRatesResponse.new(
        total_countries: int_field(body.as_h, "total_countries"),
        date: str_field(body.as_h, "date"),
        vat_rates: rates,
      )
    end

    # get_vat_rate returns VAT data for a single ISO-3166 alpha-2 country code
    # (e.g. "DE").
    def get_vat_rate(country : String) : VatCountryResponse
      raise InvalidCurrencyError.new("country is required") if country.empty?
      body = request("/api/vat/rates", [{"country", country.upcase}])
      VatCountryResponse.new(
        country: str_field(body.as_h, "country"),
        vat_data: parse_vat_rate(get_field(body, "vat_data")),
      )
    end

    # ---------------------------------------------------------------------
    # Internals
    # ---------------------------------------------------------------------

    # request performs a GET to `path` with `params` (plus the api_key), maps a
    # non-2xx status to a typed error, and returns the decoded top-level JSON.
    private def request(path : String, params : Array(Tuple(String, String))) : JSON::Any
      url = build_url(path, params)
      headers = HTTP::Headers{"Accept" => "application/json", "User-Agent" => @user_agent}
      resp = @transport.send(url, headers, @timeout)
      unless 200 <= resp.status < 300
        raise UniRate.error_for_status(resp.status, resp.body)
      end
      begin
        JSON.parse(resp.body)
      rescue ex : JSON::ParseException
        raise UniRateError.new("Failed to parse response JSON: #{ex.message}")
      end
    end

    # build_url assembles the request URL, url-encoding every name and value,
    # skipping empty values, and appending the api_key last.
    private def build_url(path : String, params : Array(Tuple(String, String))) : String
      parts = [] of String
      params.each do |(name, value)|
        next if value.empty?
        parts << "#{URI.encode_www_form(name)}=#{URI.encode_www_form(value)}"
      end
      parts << "api_key=#{URI.encode_www_form(@api_key)}"
      "#{@base_url}#{path}?#{parts.join("&")}"
    end

    # get_field returns obj[key] or raises a malformed-response error if the
    # top-level value is not an object or the key is absent.
    private def get_field(obj : JSON::Any, key : String) : JSON::Any
      h = obj.as_h?
      raise UniRateError.new("Malformed response: expected a JSON object") unless h
      h[key]? || raise UniRateError.new("Malformed response: missing '#{key}'")
    end

    # to_f64 coerces a JSON value (string like "0.92" or a JSON number) to
    # Float64.
    private def to_f64(v : JSON::Any, field : String) : Float64
      case raw = v.raw
      when Float64
        raw
      when Int64
        raw.to_f64
      when String
        s = raw.strip
        raise UniRateError.new("Malformed response: '#{field}' is empty") if s.empty?
        s.to_f64? || raise UniRateError.new("Malformed response: '#{field}' is not numeric")
      else
        raise UniRateError.new("Malformed response: '#{field}' is not numeric")
      end
    end

    # to_f64_map coerces a JSON object of {code => number-or-string} to
    # Hash(String, Float64).
    private def to_f64_map(v : JSON::Any, field : String) : Hash(String, Float64)
      h = v.as_h?
      raise UniRateError.new("Malformed response: missing or invalid '#{field}' map") unless h
      out = {} of String => Float64
      h.each { |k, val| out[k] = to_f64(val, k) }
      out
    end

    # parse_vat_rate decodes a single VAT-rate object.
    private def parse_vat_rate(v : JSON::Any) : VatRate
      o = v.as_h?
      raise UniRateError.new("Malformed response: missing VAT data") unless o
      VatRate.new(
        country_code: str_field(o, "country_code"),
        country_name: str_field(o, "country_name"),
        vat_rate: to_f64(get_field(v, "vat_rate"), "vat_rate"),
      )
    end

    # str_field returns h[key] coerced to a string, or "" if absent.
    private def str_field(h : Hash(String, JSON::Any), key : String) : String
      v = h[key]?
      return "" unless v
      v.as_s? || v.raw.to_s
    end

    # int_field returns h[key] coerced to an Int32, or 0 if absent.
    private def int_field(h : Hash(String, JSON::Any), key : String) : Int32
      v = h[key]?
      return 0 unless v
      case raw = v.raw
      when Int64   then raw.to_i32
      when Float64 then raw.to_i32
      when String  then raw.to_i?(whitespace: true) || 0
      else              0
      end
    end

    # up_or_default upper-cases a currency code, defaulting an empty value to
    # "USD".
    private def up_or_default(s : String) : String
      s.empty? ? "USD" : s.upcase
    end

    # format_amount renders a number for a query string without a spurious
    # trailing ".0" for whole values.
    private def format_amount(v : Float64) : String
      v == v.to_i64 ? v.to_i64.to_s : v.to_s
    end
  end
end
