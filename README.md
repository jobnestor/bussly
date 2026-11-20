# Bussly

Bussly is a marketplace for hiring a bus or coach with a driver in Norway (a Norwegian take on CharterUp).
This is the Ruby on Rails version of the Bussly design prototype. The UI is Norwegian by default, with English via the NO/EN toggle or `?lang=en`.

## What's in it

| Area | URL | Notes |
|---|---|---|
| Booking | `/` | Trip form (one way, round trip, multi-day, sightseeing with guide and cruise pickup), instant offers from every operator that can do the trip, "best value" tag, full price breakdown. Landing-page links such as `/?from=Bergen&type=sight&hours=4&guide=EN&cruise=1&lang=en` prefill the form. |
| Checkout | `/bestilling/new` | Opens as a sheet over the results. 20 % deposit, balance 7 days before. The price is always recomputed on the server. No real payment is taken yet. |
| Price guarantee | | When no operator covers a trip, the customer gets market price + 15 %. The booking becomes an open job any operator can take at market price. |
| Operator portal | `/operator` | Sign-in required. New requests (accept/decline), open guarantee jobs (first to claim gets it), KPIs and payout after the 12 % commission. |
| Prices & fleet | `/operator/priser` | Rate-card editor: depot, radius, positioning, fleet with hourly/km/min-hours, surcharges, busy dates. Suggested rates per region, the Bussly minimum (85 % of suggested) and a live preview of price and rank for the operator's last search. |
| Become a partner | `/bli-partner` | Checks the organisation number (MOD11), creates the operator with suggested rates and a login. |
| SEO pages | `/leie-buss/…`, `/anledning/…`, `/en/…` | The 33 prerendered landing pages from the design, plus `sitemap.xml`, `robots.txt` and `llms.txt`, served as static files from `public/`. |

## Pricing engine

`app/models/pricing*.rb` is a line-by-line port of the prototype's `trip()` and `priceOp()`:

- `Pricing::Trip` works out the route facts once: distance, driving time, 45-min breaks per 4.5 h, second driver, ferries, hotel nights and EV range.
- `Pricing::Engine#price` applies one operator's rate card and picks the cheapest vehicle mix.
- `#guarantee` returns the market price plus the 15 % buffer.

`test/models/pricing_test.rb` checks the Ruby engine against prices produced by the original JavaScript for the same trips.

## Data

SQLite (Rails 8 "Solid" stack, no separate database server).

- `Operator` holds the rate card (`fleet` JSON, surcharges and busy dates).
- `Booking` holds the trip, the offer snapshot and the status (`new`, `ok`, `no`, `paid`, `src` for an open job).
- `User` is an operator login, or an admin who can switch between operators.

`db/seeds.rb` loads the seven demo operators and sample bookings.

## Run locally

```sh
bundle install
bin/rails db:prepare     # creates the database and seeds demo data
bin/dev                  # http://localhost:3000
bin/rails test
```

Demo operator logins in development: `solvberg@demo.bussly.no` / `bussly-demo` (also `brattli`, `mjosa`, `havbris`, `gauldal`, `sunnmore`, `kystlinje`).

## Deploy to 193.243.189.77 with Kamal

The deploy config is `config/deploy.yml`. Kamal builds the Docker image on your machine and pushes it through an SSH tunnel to a registry on the server, so you don't need a Docker Hub account.

You need:

- Docker running locally;
- SSH access as `root` to the server with your key;
- Ubuntu or Debian on the server.

```sh
export SECRET_KEY_BASE=$(bin/rails secret)   # generate once and store it safely
export ADMIN_EMAIL=you@example.com
export ADMIN_PASSWORD='a-long-password'

bin/kamal setup      # first time: installs Docker on the server, boots kamal-proxy and the app
bin/kamal deploy     # every later deploy
```

The app then answers on `http://193.243.189.77`. On first boot the database is created and seeded, including your admin login. Data lives in the `bussly_storage` Docker volume.

Useful commands: `bin/kamal logs`, `bin/kamal console`, `bin/kamal shell`, `bin/kamal seed`.

### When the domain is ready

1. Point the domain's A record at `193.243.189.77`.
2. In `config/deploy.yml`, set `proxy.host` to the domain and `proxy.ssl: true` (Let's Encrypt). Set `FORCE_SSL: "true"` and set `APP_HOST` to the domain.
3. If the landing pages should use a domain other than `bussly.no`, replace `https://bussly.no` in `public/` (canonical, hreflang, sitemap, llms.txt) and in `app/views/shared/_seo_home.html.erb`.
4. Run `bin/kamal deploy`.

## Not built yet

- **Payments:** Vipps MobilePay or Stripe for the deposit and balance, and invoicing for companies.
- **Email and SMS:** booking confirmations, and password-reset mail (needs SMTP settings in `config/environments/production.rb`).
- **Routing:** real distances, tolls (AutoPASS) and ferry prices. Distances are currently great-circle × a regional detour factor, as in the prototype.
- **Verification:** checking licences against Statens vegvesen and organisation numbers against Brønnøysundregistrene.
- **Landing pages:** they are static copies from the design build. Regenerate them with the original `scripts/build.mjs` if prices change.
# bussly
