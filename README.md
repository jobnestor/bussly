# Bussly

Bussly is a marketplace for hiring a bus or coach with a driver in Norway (a Norwegian take on CharterUp).
This is the Ruby on Rails version of the Bussly design prototype. The UI is Norwegian by default, with English via the NO/EN toggle or `?lang=en`.

## What's in it

| Area | URL | Notes |
|---|---|---|
| Booking | `/` | Trip form (one way, round trip, multi-day, sightseeing with guide and cruise pickup), instant offers from every operator that can do the trip, "best value" tag, full price breakdown. Landing-page links such as `/?from=Bergen&type=sight&hours=4&guide=EN&cruise=1&lang=en` prefill the form. |
| Checkout | `/bestilling/new` | Opens as a sheet over the results. 20 % deposit, balance 7 days before. The price is always recomputed on the server. No real payment is taken yet. |
| Results tools | `/` | Sort by price, rating or punctuality; filter on instant booking, toilet and electric. Each offer shows on-time %, licence check and "confirmed instantly" badges. |
| Trip page | `/reise/:token` | Secret link from the confirmation. Status timeline (booked → confirmed → driver assigned → completed), live map, schedule with driving and rest time, driver card, payment schedule with "pay balance", self-service cancellation (free up to 14 days before, then the deposit is kept), passenger share link and a review form after the trip. |
| Live tracking | `/spor/:share_token` | Passenger link: map, status, next stop and ETA, driver first name and plate. No prices or customer details. The position is simulated from the booked schedule (`app/models/tracking.rb`); a demo slider moves through the day. Road lines come from the public OSRM demo server, map tiles from OpenStreetMap. |
| My trips | `/mine-turer` | Look up a trip with the booking reference and e-mail. |
| Operator profiles | `/operatorer/:slug` | Fleet, amenities, rating, on-time %, licence and organisation number, customer reviews. |
| Business | `/bedrift` | Recurring shuttles, events, airport and school transport. Lead form stored as `ShuttleRequest`. |
| Price guarantee | | When no operator covers a trip, the customer gets market price + 15 %. The booking becomes an open job any operator can take at market price. |
| Operator portal | `/operator` | Sign-in required. New requests (accept/decline), open guarantee jobs (first to claim gets it), assign driver, phone and plate to confirmed trips, mark trips completed (the customer is then asked for a review), KPIs and payout after the 12 % commission. |
| Prices & fleet | `/operator/priser` | Rate-card editor: depot, radius, positioning, fleet with call-out fee, hourly rate, diesel surcharge per km and minimum hours, surcharges, busy dates. Suggested rates per region, the Bussly minimum (85 % of suggested) and a live preview of price and rank for the operator's last search. |
| Become a partner | `/bli-partner` | Checks the organisation number (MOD11), creates the operator with suggested rates and a login. |
| SEO pages | `/leie-buss/…`, `/anledning/…`, `/en/…` | The 33 prerendered landing pages from the design, plus `sitemap.xml`, `robots.txt` and `llms.txt`, served as static files from `public/`. |

## Pricing engine

`app/models/pricing*.rb` prices a trip the way Norwegian coach companies quote it: a **call-out fee** (oppmøte) per
day, an **hourly rate** for the hours the bus and driver are busy (minimum hours, empty driving to and from the depot
counts towards it), a **diesel surcharge per km** beyond 200 km a day, plus waiting time, second driver, driver hotel
and allowance, large-vehicle tolls and ferries.

- `Pricing::Trip` works out the route facts once: distance, driving time, 45-min breaks per 4.5 h, stops on the way
  (15 min each), second driver above 9 h driving or 13 h duty, ferries, tolls, hotel nights and EV range.
- `Pricing::Engine#price` applies one operator's rate card and picks the cheapest vehicle mix.
- `#market_price` uses the suggested regional rates; `#guarantee` adds the 15 % buffer.
- Suggested rates are calibrated against published Norwegian prices (Oslo Turbuss, Oslobuss, Tide, Trip by Nobina,
  leiebusser.no, AnyBus24): airport transfers, Oslo–Hemsedal, Preikestolen, Dombås–Ålesund and hourly sightseeing come
  out within about ±25 %. `test/models/pricing_test.rb` keeps them there.

### Routes, stops and driving time

`Pricing::Routing` gives distance, bus driving time, large-vehicle tolls and ferries for each leg:

1. **Route table** `db/routes/routes.json` – every pair of the 33 preset places, built with
   `THREADS=4 bin/rails routes:refresh` (only missing pairs; `ALL=1` rebuilds). Quotes between preset places need no
   network.
2. **Live providers** for anything else (custom stops), in `ROUTING_PROVIDERS` order, cached 30 days:
   - `vegvesen` – [Statens vegvesen's route planner](https://dataut.vegvesen.no/en/dataservice/ruteplanlegger-for-bil-og-tungbil)
     on the national road database (NVDB). Free (NLOD), 2 500 requests a day. We send the bus size (15 m, 19 t,
     3.8 m), so it avoids roads a coach can't use, and it returns the large-vehicle toll (`tollLarge`) and ferries.
   - `osrm` – OpenStreetMap routing. `OSRM_URL` points at your own server; the public demo is for testing only
     (1 request/s). No tolls, so those are estimated per km plus city toll rings.
   - `ROUTING_LIVE=0` turns live lookups off (default in tests).
3. **Estimate** – great-circle distance × a regional detour factor, flagged to the customer.

Bus time is the road time with every section capped at 100 km/h (the limit for class III coaches,
[trafikkreglene § 13](https://lovdata.no/dokument/SF/forskrift/1986-03-21-747/%C2%A713)) × 1.1 for a heavy vehicle,
plus the ferry crossing. Driving and rest rules follow
[Statens vegvesen](https://www.vegvesen.no/kjoretoy/yrkestransport/kjore-og-hviletid/regelverk/).

**Stops on the way** (up to 8): the quote form has "+ Legg til stopp" with suggestions from the preset places and
Kartverket's open place-name and address APIs (`/steder`, `Pricing::Places`). A stop is stored as `Label~lat,lng`
so the quote, booking and operator all see the same point. Each leg is routed separately, and 15 minutes are added per
stop.

Not used: Google's large-vehicle routing only covers the US and Japan, and OsmAnd is a navigation app without a
server API. HERE Routing v8 (`transportMode=bus`, toll costs) would be the paid backup if needed; add it as another
provider in `Pricing::Routing#fetch`.

### Landing pages

`bin/rails pages:prices` recalculates the example prices, distances and driving times on the static route and city
pages in `public/leie-buss/` (`DRY=1` to preview). Run it after changing rates or refreshing routes.

## Data

SQLite (Rails 8 "Solid" stack, no separate database server).

- `Operator` holds the rate card (`fleet` JSON, surcharges and busy dates).
- `Booking` holds the trip, the offer snapshot and the status (`new`, `ok`, `no`, `paid`, `src` for an open job).
- `Booking` also holds the customer and passenger link tokens, driver, payment dates, completion and cancellation/refund.
- `Review` belongs to an operator and a booking; new reviews update the operator's rating, review count and on-time %.
- `ShuttleRequest` is a business lead for recurring transport.
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
- **Ferry prices per route:** ferry fares are a typical fare per vehicle size, not the exact fare for each crossing.
- **Verification:** checking licences against Statens vegvesen and organisation numbers against Brønnøysundregistrene.
- **Landing pages:** they are static copies from the design build. `bin/rails pages:prices` keeps the numbers current, but the text is not generated.
# bussly
