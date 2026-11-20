# Demo operators and bookings from the Bussly prototype. Safe to run more than once.
# Demo operator logins: <slug>@demo.bussly.no / bussly-demo  (only created outside production,
# or in production when SEED_DEMO_USERS=1)

def demo_operator(attrs)
  counts = attrs.delete(:counts) || {}
  adj = attrs.delete(:adj) || {}
  sur = attrs.delete(:sur) || Pricing::DEFAULT_SURCHARGES
  fleet = Pricing.suggested_fleet(attrs[:depot], counts)
  adj.each { |k, v| fleet[k.to_s].merge!(v.transform_keys(&:to_s)) }
  op = Operator.find_or_initialize_by(slug: attrs[:slug])
  op.assign_attributes(pos_factor: 1, ev: false, instant: false, langs: [], blocked_dates: [],
                       sur_weekend: sur[:weekend], sur_peak: sur[:peak], sur_night: sur[:night], fleet: fleet, **attrs)
  op.save!
  op
end

ops = [
  { slug: "solvberg", name: "Sølvberg Reiser AS", depot: "Oslo", radius: 150, rating: 4.8, reviews_count: 388, model_year: 2022, ev: true, instant: true,
    counts: { mini: 2, midi: 3, coach: 6, dd: 1 }, amenities: %w[WiFi USB Toalett Kjøleskap] },
  { slug: "brattli", name: "Brattli Busstrafikk AS", depot: "Drammen", radius: 120, rating: 4.6, reviews_count: 212, model_year: 2019, pos_factor: 0.5,
    counts: { midi: 2, coach: 4 }, adj: { coach: { start: 1600, hr: 990, km: 8 }, midi: { hr: 900 } }, sur: { weekend: 5, peak: 10, night: 15 },
    amenities: %w[WiFi USB Toalett] },
  { slug: "mjosa", name: "Mjøsa Turbuss", depot: "Hamar", radius: 220, rating: 4.7, reviews_count: 96, model_year: 2021,
    counts: { mini: 1, coach: 5 }, adj: { coach: { hr: 1080 } }, amenities: %w[WiFi USB Toalett Skiboks] },
  { slug: "havbris", name: "Havbris Turvogn", depot: "Bergen", radius: 250, rating: 4.9, reviews_count: 141, model_year: 2024, ev: true,
    counts: { mini: 2, midi: 2, coach: 3 }, adj: { coach: { start: 2200, hr: 1190, km: 10 } }, amenities: %w[WiFi USB Toalett Skinnseter Mikrofon] },
  { slug: "gauldal", name: "Gauldal Turbuss AS", depot: "Trondheim", radius: 200, rating: 4.5, reviews_count: 74, model_year: 2018,
    counts: { midi: 1, coach: 3 }, amenities: %w[WiFi Toalett] },
  { slug: "sunnmore", name: "Sunnmøre Fjordbuss", depot: "Ålesund", radius: 160, rating: 4.8, reviews_count: 203, model_year: 2023, ev: true,
    counts: { mini: 3, midi: 2, coach: 3 }, adj: { midi: { hr: 1050, km: 7 } }, amenities: %w[WiFi USB Toalett Panoramavinduer], langs: %w[EN DE] },
  { slug: "kystlinje", name: "Kystlinje Buss", depot: "Stavanger", radius: 180, rating: 4.7, reviews_count: 120, model_year: 2023,
    counts: { mini: 2, coach: 2, dd: 1 }, amenities: %w[WiFi USB Toalett] }
].map { |a| demo_operator(a) }.index_by(&:slug)

# Trust stats shown on offers and operator profiles (demo values)
{
  "solvberg" => [ 97, "912345602", "FL-0301-0142", 1994, "Familieeid turbusselskap i Oslo med 40 sjåfører. Kjører konferanser, skiturer og flyplasstransport." ],
  "brattli" => [ 93, "923456708", "FL-3005-0088", 1978, nil ],
  "mjosa" => [ 95, "934567803", "FL-3403-0031", 2001, "Turbuss fra Hamar med skiboks på alle busser. Mye kjøring til Trysil, Hafjell og Kvitfjell." ],
  "havbris" => [ 98, "945678909", "FL-4601-0217", 2009, "Bergen-basert operatør med ny flåte. Cruisekunder, fjordturer og Flåm." ],
  "gauldal" => [ 91, "956789001", "FL-5001-0064", 1986, nil ],
  "sunnmore" => [ 96, "967890103", "FL-1507-0019", 1999, "Fjordturer fra Ålesund og Geiranger med engelsk- og tysktalende guider." ],
  "kystlinje" => [ 94, "978901204", "FL-1103-0102", 2012, nil ]
}.each do |slug, (on_time, org, licence, founded, about)|
  ops[slug].update_columns(on_time_pct: on_time, org_number: org, licence_number: licence, founded_year: founded, about: about,
                           trips_count: ops[slug].reviews_count * 3)
end

# A few written reviews per operator. Stored directly so the seeded rating and counts above stay as they are.
if Review.none?
  texts = [
    [ 5, "Ingrid", "Oslo → Hemsedal", "Presis henting og en sjåfør som kjente veien. Bussen var ren og varm." ],
    [ 5, "Martin", "Firmatur", "Enkel bestilling og god oppfølging. Vi fikk sjåførens nummer dagen før." ],
    [ 4, "Siri", "Skoletur", "Alt gikk fint, litt trangt med bagasje til 50 personer." ],
    [ 5, "Jonas", "Bryllup", "Sjåføren ventet tålmodig og hjalp med pyntingen. Anbefales." ],
    [ 3, "Kari", "Flyplass", "Kom 15 minutter for sent pga. kø, men ga beskjed underveis." ]
  ]
  now = Time.current
  rows = ops.values.flat_map.with_index do |op, i|
    texts.rotate(i).first(3).map.with_index do |(r, who, label, text), j|
      { operator_id: op.id, rating: r, on_time: r > 3, author: who, trip_label: label, comment: text,
        created_at: now - (j * 9 + i).days, updated_at: now }
    end
  end
  Review.insert_all(rows)
end

if Booking.none?
  [
    [ "BS-7HQ9", "solvberg", "Oslo lufthavn Gardermoen", "Trysil", "2026-12-19", 110, 3, "coach", 68400, "new" ],
    [ "BS-9TRE", "solvberg", "Oslo", "Drammen", "2026-11-14", 14, 1, "mini", 6890, "paid" ],
    [ "BS-3LDN", "solvberg", "Oslo", "Lillehammer", "2026-12-04", 40, 1, "coach", 24100, "ok" ],
    [ "BS-4K2P", "gauldal", "Trondheim", "Røros", "2026-12-12", 48, 1, "coach", 21840, "new" ],
    [ "BS-2MXA", "havbris", "Bergen", "Flåm", "2026-12-05", 30, 1, "midi", 15620, "ok" ],
    [ "BS-5WBC", "kystlinje", "Stavanger", "Bergen", "2026-11-29", 60, 1, "dd", 38200, "no" ],
    [ "BS-8NRV", nil, "Tromsø", "Narvik", "2026-12-10", 35, 1, "midi", 31500, "src" ],
    [ "BS-6BRG", nil, "Bergen lufthavn Flesland", "Voss", "2026-12-18", 150, 3, "coach", 52800, "src" ]
  ].each do |ref, op, from, to, date, pax, n, cls, sub, status|
    customer_sub = status == "src" ? sub * Pricing::GUARANTEE_BUFFER : sub
    vat = customer_sub * Pricing::VAT
    Booking.create!(ref: ref, operator: op && ops[op], trip_type: "oneway", from_place: from, to_place: to, date: date, pax: pax,
                    vehicle_count: n, vehicle_class: cls, subtotal: sub, customer_subtotal: customer_sub, vat: vat,
                    total: customer_sub + vat, deposit: (customer_sub + vat) * Pricing::DEPOSIT_SHARE, status: status,
                    guaranteed: status == "src", contact_name: "Demo", email: "demo@example.com", phone: "+4790000000")
  end
end

# Demo trip lifecycle: one confirmed trip with a driver, one completed trip waiting for a review
if (b = Booking.find_by(ref: "BS-3LDN")) && !b.driver_assigned?
  b.update_columns(driver_name: "Erik Haugen", driver_phone: "+47 915 22 384", vehicle_plate: "EV 48213", time: "08:00")
end
if (b = Booking.find_by(ref: "BS-9TRE")) && !b.completed?
  b.update_columns(completed_at: b.date.to_time.change(hour: 18), balance_paid_at: (b.date - 7).to_time, time: "09:00",
                   driver_name: "Nora Lie", driver_phone: "+47 934 10 552", vehicle_plate: "EL 20871")
end
Booking.where(deposit_paid_at: nil).where.not(status: "src").update_all("deposit_paid_at = created_at")

if !Rails.env.production? || ENV["SEED_DEMO_USERS"] == "1"
  ops.each_value do |op|
    User.find_or_create_by!(email_address: "#{op.slug}@demo.bussly.no") do |u|
      u.password = "bussly-demo"
      u.operator = op
    end
  end
end

if ENV["ADMIN_EMAIL"].present? && ENV["ADMIN_PASSWORD"].present?
  User.find_or_create_by!(email_address: ENV["ADMIN_EMAIL"]) { |u| u.password = ENV["ADMIN_PASSWORD"]; u.admin = true }
end
