module UniRate
  # VatRate is VAT data for a single country.
  struct VatRate
    getter country_code : String
    getter country_name : String
    getter vat_rate : Float64

    def initialize(@country_code : String, @country_name : String, @vat_rate : Float64)
    end
  end

  # VatRatesResponse is the result of `get_vat_rates` — VAT data for every
  # supported country, keyed by ISO-3166 alpha-2 country code.
  struct VatRatesResponse
    getter total_countries : Int32
    getter date : String
    getter vat_rates : Hash(String, VatRate)

    def initialize(@total_countries : Int32, @date : String, @vat_rates : Hash(String, VatRate))
    end
  end

  # VatCountryResponse is the result of `get_vat_rate(country)` — VAT data for
  # one country.
  struct VatCountryResponse
    getter country : String
    getter vat_data : VatRate

    def initialize(@country : String, @vat_data : VatRate)
    end
  end

  # HistoricalLimit is the historical-data coverage for a single currency.
  struct HistoricalLimit
    getter earliest_date : String
    getter latest_date : String
    getter total_days : Int32
    getter description : String

    def initialize(@earliest_date : String, @latest_date : String, @total_days : Int32, @description : String)
    end
  end

  # HistoricalLimitsResponse is the result of `get_historical_limits` —
  # per-currency coverage, keyed by currency code.
  struct HistoricalLimitsResponse
    getter total_currencies : Int32
    getter data_source : String
    getter currencies : Hash(String, HistoricalLimit)

    def initialize(@total_currencies : Int32, @data_source : String, @currencies : Hash(String, HistoricalLimit))
    end
  end
end
