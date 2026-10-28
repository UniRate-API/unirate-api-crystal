require "./spec_helper"

describe UniRate::Client do
  describe "construction" do
    it "rejects an empty api_key" do
      expect_raises(UniRate::AuthenticationError, "api_key is required") do
        UniRate::Client.new("")
      end
    end

    it "sends the api_key, Accept and User-Agent on every request" do
      client, mock = client_for(%({"rate": "0.92"}))
      client.get_rate(to: "EUR")
      mock.last_url.should contain("api_key=test-key")
      mock.last_headers["Accept"].should eq("application/json")
      mock.last_headers["User-Agent"].should eq("unirate-crystal/#{UniRate::Client::VERSION}")
    end
  end

  describe "#get_rate" do
    it "parses a string rate and upper-cases the currency codes" do
      client, mock = client_for(%({"rate": "0.92"}))
      client.get_rate(to: "eur", from: "usd").should eq(0.92)
      mock.last_url.should contain("from=USD")
      mock.last_url.should contain("to=EUR")
    end

    it "defaults `from` to USD" do
      client, mock = client_for(%({"rate": "0.92"}))
      client.get_rate(to: "EUR")
      mock.last_url.should contain("from=USD")
    end

    it "rejects an empty `to`" do
      client, _ = client_for(%({"rate": "0.92"}))
      expect_raises(UniRate::InvalidCurrencyError) { client.get_rate(to: "") }
    end
  end

  describe "#get_all_rates" do
    it "parses the rates map" do
      client, _ = client_for(%({"rates": {"EUR": "0.92", "GBP": "0.79"}}))
      rates = client.get_all_rates
      rates["EUR"].should eq(0.92)
      rates["GBP"].should eq(0.79)
    end
  end

  describe "#convert" do
    it "parses the result and formats a whole amount without a trailing .0" do
      client, mock = client_for(%({"result": "92.50"}))
      client.convert(100.0, to: "EUR").should eq(92.5)
      mock.last_url.should contain("amount=100")
      mock.last_url.should_not contain("amount=100.0")
    end

    it "keeps a fractional amount" do
      client, mock = client_for(%({"result": "2.30"}))
      client.convert(2.5, to: "EUR")
      mock.last_url.should contain("amount=2.5")
    end
  end

  describe "#get_supported_currencies" do
    it "parses the currencies array" do
      client, _ = client_for(%({"currencies": ["USD", "EUR", "GBP"]}))
      client.get_supported_currencies.should eq(["USD", "EUR", "GBP"])
    end
  end

  describe "#get_historical_rate" do
    it "parses a historical rate" do
      client, mock = client_for(%({"rate": "0.88"}))
      client.get_historical_rate("2024-01-01", to: "EUR").should eq(0.88)
      mock.last_url.should contain("date=2024-01-01")
    end
  end

  describe "#get_historical_rates" do
    it "parses the historical rates map" do
      client, _ = client_for(%({"rates": {"EUR": "0.88", "GBP": "0.75"}}))
      client.get_historical_rates("2024-01-01")["EUR"].should eq(0.88)
    end
  end

  describe "#convert_historical" do
    it "parses the historical conversion result" do
      client, _ = client_for(%({"result": "88.00"}))
      client.convert_historical(100.0, "USD", "EUR", "2024-01-01").should eq(88.0)
    end
  end

  describe "#get_time_series" do
    it "parses numeric nested data" do
      body = %({"data": {"2024-01-01": {"EUR": 0.92, "GBP": 0.79}, "2024-01-02": {"EUR": 0.93}}})
      client, mock = client_for(body)
      ts = client.get_time_series("2024-01-01", "2024-01-02", currencies: ["eur", "gbp"])
      ts["2024-01-01"]["EUR"].should eq(0.92)
      ts["2024-01-02"]["EUR"].should eq(0.93)
      mock.last_url.should contain("currencies=EUR%2CGBP")
    end
  end

  describe "#get_historical_limits" do
    it "parses the limits struct" do
      body = %({"total_currencies": 2, "data_source": "src", "currencies": {"USD": {"earliest_date": "1999-01-01", "latest_date": "2026-04-22", "total_days": 9000, "description": "US Dollar"}}})
      client, _ = client_for(body)
      limits = client.get_historical_limits
      limits.total_currencies.should eq(2)
      limits.data_source.should eq("src")
      limits.currencies["USD"].earliest_date.should eq("1999-01-01")
      limits.currencies["USD"].total_days.should eq(9000)
    end
  end

  describe "#get_vat_rates" do
    it "parses the vat_rates map" do
      body = %({"total_countries": 1, "date": "2026-04-22", "vat_rates": {"DE": {"country_code": "DE", "country_name": "Germany", "vat_rate": 19.0}}})
      client, _ = client_for(body)
      resp = client.get_vat_rates
      resp.total_countries.should eq(1)
      resp.vat_rates["DE"].country_name.should eq("Germany")
      resp.vat_rates["DE"].vat_rate.should eq(19.0)
    end
  end

  describe "#get_vat_rate" do
    it "parses a single-country vat_data object" do
      body = %({"country": "DE", "vat_data": {"country_code": "DE", "country_name": "Germany", "vat_rate": 19.0}})
      client, mock = client_for(body)
      resp = client.get_vat_rate("de")
      resp.country.should eq("DE")
      resp.vat_data.vat_rate.should eq(19.0)
      mock.last_url.should contain("country=DE")
    end

    it "rejects an empty country" do
      client, _ = client_for("{}")
      expect_raises(UniRate::InvalidCurrencyError) { client.get_vat_rate("") }
    end
  end

  describe "error mapping" do
    it "maps 400 to InvalidDateError" do
      expect_raises(UniRate::InvalidDateError, "Invalid request parameters") do
        error_client(400).get_rate(to: "EUR")
      end
    end

    it "maps 401 to AuthenticationError" do
      expect_raises(UniRate::AuthenticationError, "Missing or invalid API key") do
        error_client(401).get_rate(to: "EUR")
      end
    end

    it "maps 403 to APIError with a Pro-subscription message" do
      ex = expect_raises(UniRate::APIError, "Endpoint requires a Pro subscription") do
        error_client(403).get_historical_rate("2024-01-01", to: "EUR")
      end
      ex.status.should eq(403)
    end

    it "maps 404 to InvalidCurrencyError" do
      expect_raises(UniRate::InvalidCurrencyError, "Currency not found or no data available") do
        error_client(404).get_rate(to: "ZZZ")
      end
    end

    it "maps 429 to RateLimitError" do
      expect_raises(UniRate::RateLimitError, "Rate limit exceeded") do
        error_client(429).get_rate(to: "EUR")
      end
    end

    it "maps 503 to APIError" do
      ex = expect_raises(UniRate::APIError, "Service unavailable") do
        error_client(503).get_rate(to: "EUR")
      end
      ex.status.should eq(503)
    end

    it "maps an unknown status to APIError carrying the status and body" do
      ex = expect_raises(UniRate::APIError) do
        error_client(418, %({"error": "teapot"})).get_rate(to: "EUR")
      end
      ex.status.should eq(418)
      ex.body.should eq(%({"error": "teapot"}))
    end

    it "raises UniRateError on a malformed body" do
      expect_raises(UniRate::UniRateError, "Failed to parse response JSON") do
        client, _ = client_for("not json")
        client.get_rate(to: "EUR")
      end
    end

    it "raises UniRateError when an expected field is missing" do
      expect_raises(UniRate::UniRateError, "missing 'rate'") do
        client, _ = client_for(%({"wrong": "1"}))
        client.get_rate(to: "EUR")
      end
    end
  end
end
