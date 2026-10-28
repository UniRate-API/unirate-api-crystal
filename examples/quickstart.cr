# Runnable quick-start example for the UniRate Crystal client.
#
#   UNIRATE_API_KEY=your-key crystal run examples/quickstart.cr
#
# Uses free-tier endpoints only (rate / convert / currencies).
require "../src/unirate"

api_key = ENV["UNIRATE_API_KEY"]?
if api_key.nil? || api_key.empty?
  STDERR.puts "Set UNIRATE_API_KEY to run this example."
  exit 1
end

client = UniRate::Client.new(api_key)

# 1. Current rate: how many EUR is one USD?
rate = client.get_rate(to: "EUR", from: "USD")
puts "1 USD = #{rate} EUR"

# 2. Convert an amount.
total = client.convert(100.0, to: "EUR", from: "USD")
puts "100 USD = #{total} EUR"

# 3. List the supported currency codes.
currencies = client.get_supported_currencies
puts "#{currencies.size} currencies supported (e.g. #{currencies.first(5).join(", ")})"
