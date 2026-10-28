# UniRate API — Crystal client

Official [Crystal](https://crystal-lang.org) client for the [UniRate API](https://unirateapi.com) —
free currency exchange rates, historical data, and VAT rates.

- **Zero dependencies.** HTTP via `HTTP::Client`, JSON via `JSON`, URL encoding
  via `URI` — all in the Crystal standard library. No third-party shards are
  pulled in (there is no `dependencies:` key in `shard.yml`).
- **Injectable transport**, so your tests never touch the network.
- Typed error classes you can rescue individually.

## Install

Add the shard to your `shard.yml`:

```yaml
dependencies:
  unirate-api:
    github: UniRate-API/unirate-api-crystal
    version: ~> 0.1.0
```

Then `shards install` and `require "unirate"` in your code.

Get a free API key at [unirateapi.com](https://unirateapi.com).

## Quick start

```crystal
require "unirate"

client = UniRate::Client.new("your-api-key")

# Current rate: how many EUR is one USD?
rate = client.get_rate(to: "EUR", from: "USD") # => 0.92

# Convert an amount
eur = client.convert(100.0, to: "EUR", from: "USD") # => 92.5

# All rates for a base currency
all = client.get_all_rates("USD") # => Hash(String, Float64)

# Supported currency codes
codes = client.get_supported_currencies # => ["USD", "EUR", ...]
```

## API

Construct a client with your API key, plus optional named settings (base URL,
timeout in seconds, and a custom `Transport`):

```crystal
client = UniRate::Client.new("your-api-key", timeout: 10)
```

### Current rates & conversion (free tier)

| Method | Returns |
|---|---|
| `get_rate(to, from = "USD")` | `Float64` — rate from `from` to `to` |
| `get_all_rates(from = "USD")` | `Hash(String, Float64)` — every rate for a base |
| `convert(amount, to, from = "USD")` | `Float64` — converted amount |
| `get_supported_currencies` | `Array(String)` — supported currency codes |

### Historical data (Pro tier)

These require a UniRate Pro subscription and raise a `UniRate::APIError`
(`status: 403`) on the free tier.

| Method | Returns |
|---|---|
| `get_historical_rate(date, to, from = "USD")` | `Float64` |
| `get_historical_rates(date, base = "USD")` | `Hash(String, Float64)` |
| `convert_historical(amount, from, to, date)` | `Float64` |
| `get_time_series(start_date, end_date, base = "USD", currencies = [], amount = 1.0)` | `Hash(String, Hash(String, Float64))` |
| `get_historical_limits` | `UniRate::HistoricalLimitsResponse` |

### VAT (free tier)

| Method | Returns |
|---|---|
| `get_vat_rates` | `UniRate::VatRatesResponse` — every supported country |
| `get_vat_rate(country)` | `UniRate::VatCountryResponse` — one ISO-3166 alpha-2 country |

Currency and country codes are upper-cased before they are sent, and an empty
`from`/`base` defaults to `USD`.

## Error handling

Every method raises a `UniRate::UniRateError` (or a subclass) on failure.
Rescue the base class to catch everything, or a subclass to branch:

```crystal
require "unirate"

client = UniRate::Client.new("your-api-key")

begin
  rate = client.get_rate(to: "ZZZ")
rescue ex : UniRate::AuthenticationError
  STDERR.puts "check your API key"
rescue ex : UniRate::InvalidCurrencyError
  STDERR.puts "unknown currency"
rescue ex : UniRate::RateLimitError
  STDERR.puts "slow down"
rescue ex : UniRate::UniRateError
  STDERR.puts "API error #{ex.status}: #{ex.message}"
end
```

| Error class | HTTP | Meaning |
|---|---|---|
| `InvalidDateError` | 400 | Invalid request parameters |
| `AuthenticationError` | 401 | Missing or invalid API key |
| `APIError` | 403 | Endpoint requires a Pro subscription |
| `InvalidCurrencyError` | 404 | Currency/country not found |
| `RateLimitError` | 429 | Rate limit exceeded |
| `APIError` | 503 / other | Service unavailable / generic |
| `UniRateError` | — | Transport failure or malformed response body |

All subclasses inherit from `UniRate::UniRateError`, which carries `status`
(the HTTP status, or `0` for a non-HTTP failure) and `body` (the raw response
body when the server returned one).

## Rate limits

The free tier is rate-limited; a `429` surfaces as `UniRate::RateLimitError`.
See [unirateapi.com](https://unirateapi.com) for current limits and Pro plans.

## Testing

```sh
crystal spec spec/unirate_spec.cr                        # mock suite, no network
UNIRATE_API_KEY=... crystal spec spec/live_spec.cr       # live suite (free tier)
```

The HTTP layer is the `UniRate::Transport` abstract class, so your own tests
can inject a fake and stay offline.

## Related clients

UniRate ships official clients for many languages and platforms — Python,
Node.js, Go, Rust, Java, Swift, Ruby, PHP, Elixir, Haxe, V, and more. See
[unirateapi.com](https://unirateapi.com).

## License

MIT — see [LICENSE](LICENSE). Copyright © 2026 Unirate Team.
