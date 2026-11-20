# Bussly pricing engine (ported 1:1 from the prototype's trip() / priceOp()).
#
#   Pricing::Trip   – facts that are the same for every operator (route, hours, breaks, ferries ...)
#   Pricing::Engine – applies one operator's rate card to those facts
module Pricing
  # name => [lat, lng, region]   E = Østlandet, S = Sørlandet, W = Vestlandet, M = Trøndelag, N = Nord-Norge
  CITIES = {
    "Oslo" => [ 59.9139, 10.7522, "E" ], "Oslo lufthavn Gardermoen" => [ 60.1976, 11.1004, "E" ], "Drammen" => [ 59.7439, 10.2045, "E" ],
    "Fredrikstad" => [ 59.2181, 10.9298, "E" ], "Sarpsborg" => [ 59.2840, 11.1096, "E" ], "Moss" => [ 59.4340, 10.6577, "E" ],
    "Tønsberg" => [ 59.2675, 10.4076, "E" ], "Sandefjord Torp" => [ 59.1312, 10.2166, "E" ], "Kongsberg" => [ 59.6689, 9.6502, "E" ],
    "Hamar" => [ 60.7945, 11.0680, "E" ], "Lillehammer" => [ 61.1153, 10.4662, "E" ], "Gjøvik" => [ 60.7957, 10.6916, "E" ],
    "Trysil" => [ 61.3150, 12.2640, "E" ], "Geilo" => [ 60.5340, 8.2060, "E" ], "Hemsedal" => [ 60.8640, 8.5530, "E" ],
    "Kristiansand" => [ 58.1467, 7.9956, "S" ], "Stavanger" => [ 58.9700, 5.7331, "W" ], "Haugesund" => [ 59.4138, 5.2680, "W" ],
    "Bergen" => [ 60.3913, 5.3221, "W" ], "Bergen lufthavn Flesland" => [ 60.2934, 5.2181, "W" ], "Voss" => [ 60.6280, 6.4180, "W" ],
    "Flåm" => [ 60.8628, 7.1137, "W" ], "Ålesund" => [ 62.4722, 6.1495, "W" ], "Geiranger" => [ 62.1015, 7.2060, "W" ], "Molde" => [ 62.7375, 7.1591, "W" ],
    "Trondheim" => [ 63.4305, 10.3951, "M" ], "Røros" => [ 62.5747, 11.3842, "M" ], "Bodø" => [ 67.2804, 14.4049, "N" ],
    "Narvik" => [ 68.4385, 17.4273, "N" ], "Tromsø" => [ 69.6492, 18.9553, "N" ]
  }.freeze

  FERRY = [ %w[Bergen Stavanger], %w[Haugesund Stavanger], %w[Bergen Ålesund], %w[Bergen Molde],
            %w[Ålesund Molde], %w[Bodø Narvik], %w[Bodø Tromsø], %w[Stavanger Ålesund], %w[Ålesund Geiranger] ].freeze

  # Market reference rates (NOK excl. VAT) used for suggestions, the floor and the price guarantee
  VehicleClass = Data.define(:id, :seats, :hr, :km)
  CLASSES = [
    VehicleClass.new(id: "mini",  seats: 16, hr: 850,  km: 13),
    VehicleClass.new(id: "midi",  seats: 35, hr: 1050, km: 17),
    VehicleClass.new(id: "coach", seats: 53, hr: 1250, km: 21),
    VehicleClass.new(id: "dd",    seats: 79, hr: 1650, km: 27)
  ].freeze
  CLASS_IDS = CLASSES.map(&:id).freeze

  REGION_FACTOR = { "E" => 1.0, "S" => 0.97, "W" => 1.05, "M" => 0.97, "N" => 1.1 }.freeze
  FLOOR = 0.85          # Bussly minimum: 85 % of suggested rate
  GUARANTEE_BUFFER = 1.15 # price guarantee = market price + 15 %
  COMMISSION = 0.12
  VAT = 0.12
  GUIDE_HOURLY = 650
  GUIDE_VAT = 0.25
  NOK_PER_EUR = 11.7
  GUIDE_LANGS = %w[EN DE ES FR IT ZH].freeze
  DEFAULT_SURCHARGES = { weekend: 10, peak: 12, night: 15 }.freeze
  DEPOSIT_SHARE = 0.2

  module_function

  def city?(name) = CITIES.key?(name)
  def region(name) = CITIES.fetch(name)[2]
  def vehicle_class(id) = CLASSES.find { |c| c.id == id.to_s }

  # Suggested rate card for a depot: market rates × regional factor
  def suggested_fleet(depot, counts = {})
    f = REGION_FACTOR.fetch(region(depot))
    CLASSES.to_h do |c|
      [ c.id, { "count" => (counts[c.id] || counts[c.id.to_sym] || 0).to_i,
                "hr" => ((c.hr * f) / 10.0).round * 10, "km" => (c.km * f).round, "minH" => 4 } ]
    end
  end

  def haversine(a, b)
    r = ->(x) { x * Math::PI / 180 }
    d_la = r.(b[0] - a[0]); d_lo = r.(b[1] - a[1])
    s = Math.sin(d_la / 2)**2 + Math.cos(r.(a[0])) * Math.cos(r.(b[0])) * Math.sin(d_lo / 2)**2
    2 * 6371 * Math.asin(Math.sqrt(s))
  end

  # Approximate road distance: great-circle distance × detour factor by region
  def road_km(from, to)
    return 0.0 if from == to
    a = CITIES.fetch(from); b = CITIES.fetch(to)
    f = 1.3
    if a[2] == "W" && b[2] == "W" then f = 1.55
    elsif a[2] == "W" || b[2] == "W" then f = 1.4
    end
    f = [ f, 1.45 ].max if a[2] == "N" || b[2] == "N"
    [ 8.0, haversine(a, b) * f ].max
  end

  def ferry?(from, to)
    base = ->(s) { s.sub(/ lufthavn.*/, "") }
    FERRY.any? { |x, y| (base.(from) == x && base.(to) == y) || (base.(from) == y && base.(to) == x) }
  end

  def speed_for(from, to) = (region(from) == "E" && region(to) == "E") ? 72 : 62
end
