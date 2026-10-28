require "spec"
require "../src/unirate"

# Live tests hit the real UniRate API and run only when UNIRATE_API_KEY is set.
# They exercise free-tier endpoints only (rate / convert / currencies / vat) —
# never the Pro-gated historical endpoints, which 403 on the free tier.
#
# Run them explicitly (they are NOT part of the default `crystal spec` mock
# run, which targets spec/unirate_spec.cr):
#
#   UNIRATE_API_KEY=... crystal spec spec/live_spec.cr
API_KEY = ENV["UNIRATE_API_KEY"]?

private def live_client : UniRate::Client
  UniRate::Client.new(API_KEY.not_nil!)
end

describe "UniRate live (free tier)" do
  if API_KEY.nil? || API_KEY.not_nil!.empty?
    pending "requires UNIRATE_API_KEY" { }
  else
    it "fetches a single rate" do
      live_client.get_rate(to: "EUR").should be > 0.0
    end

    it "fetches all rates for a base" do
      rates = live_client.get_all_rates("USD")
      rates.size.should be > 0
      rates.has_key?("EUR").should be_true
    end

    it "converts an amount" do
      live_client.convert(100.0, to: "EUR").should be > 0.0
    end

    it "lists supported currencies" do
      currencies = live_client.get_supported_currencies
      currencies.should contain("USD")
      currencies.should contain("EUR")
    end

    it "fetches VAT rates for all countries" do
      resp = live_client.get_vat_rates
      resp.vat_rates.size.should be > 0
    end

    it "fetches VAT data for a single country" do
      resp = live_client.get_vat_rate("DE")
      resp.country.should eq("DE")
      resp.vat_data.vat_rate.should be > 0.0
    end
  end
end
