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
  op.assign_attributes(pos_factor: 0.5, ev: false, instant: false, langs: [], blocked_dates: [],
                       sur_weekend: sur[:weekend], sur_peak: sur[:peak], sur_night: sur[:night], fleet: fleet, **attrs)
  op.save!
  op
end

ops = [
  { slug: "solvberg", name: "Sølvberg Reiser AS", depot: "Oslo", radius: 150, rating: 4.8, reviews_count: 388, model_year: 2022, ev: true, instant: true,
    counts: { mini: 2, midi: 3, coach: 6, dd: 1 }, amenities: %w[WiFi USB Toalett Kjøleskap] },
  { slug: "brattli", name: "Brattli Busstrafikk AS", depot: "Drammen", radius: 120, rating: 4.6, reviews_count: 212, model_year: 2019, pos_factor: 0,
    counts: { midi: 2, coach: 4 }, adj: { coach: { hr: 1150, km: 19 }, midi: { hr: 990, km: 16 } }, sur: { weekend: 5, peak: 10, night: 15 },
    amenities: %w[WiFi USB Toalett] },
  { slug: "mjosa", name: "Mjøsa Turbuss", depot: "Hamar", radius: 220, rating: 4.7, reviews_count: 96, model_year: 2021,
    counts: { mini: 1, coach: 5 }, adj: { coach: { hr: 1220, km: 20 } }, amenities: %w[WiFi USB Toalett Skiboks] },
  { slug: "havbris", name: "Havbris Turvogn", depot: "Bergen", radius: 250, rating: 4.9, reviews_count: 141, model_year: 2024, ev: true,
    counts: { mini: 2, midi: 2, coach: 3 }, adj: { coach: { hr: 1390, km: 23 } }, amenities: %w[WiFi USB Toalett Skinnseter Mikrofon] },
  { slug: "gauldal", name: "Gauldal Turbuss AS", depot: "Trondheim", radius: 200, rating: 4.5, reviews_count: 74, model_year: 2018,
    counts: { midi: 1, coach: 3 }, amenities: %w[WiFi Toalett] },
  { slug: "sunnmore", name: "Sunnmøre Fjordbuss", depot: "Ålesund", radius: 160, rating: 4.8, reviews_count: 203, model_year: 2023, ev: true,
    counts: { mini: 3, midi: 2, coach: 3 }, adj: { midi: { hr: 1150, km: 18 } }, amenities: %w[WiFi USB Toalett Panoramavinduer], langs: %w[EN DE] },
  { slug: "kystlinje", name: "Kystlinje Buss", depot: "Stavanger", radius: 180, rating: 4.7, reviews_count: 120, model_year: 2023,
    counts: { mini: 2, coach: 2, dd: 1 }, amenities: %w[WiFi USB Toalett] }
].map { |a| demo_operator(a) }.index_by(&:slug)

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
