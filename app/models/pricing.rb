# Bussly pricing engine.
#
#   Pricing::Trip   – facts that are the same for every operator (route, hours, breaks, ferries ...)
#   Pricing::Engine – applies one operator's rate card to those facts
module Pricing
  # name => [lat, lng, region]   E = Østlandet, S = Sørlandet, W = Vestlandet, M = Trøndelag, N = Nord-Norge
  CITIES = {
    "Oslo" => [ 59.9139, 10.7522, "E" ], "Oslo lufthavn Gardermoen" => [ 60.1940, 11.0910, "E" ], "Drammen" => [ 59.7439, 10.2045, "E" ],
    "Fredrikstad" => [ 59.2181, 10.9298, "E" ], "Sarpsborg" => [ 59.2840, 11.1096, "E" ], "Moss" => [ 59.4340, 10.6577, "E" ],
    "Tønsberg" => [ 59.2675, 10.4076, "E" ], "Sandefjord Torp" => [ 59.1312, 10.2166, "E" ], "Kongsberg" => [ 59.6689, 9.6502, "E" ],
    "Dombås" => [ 62.0748, 9.1250, "E" ],
    "Hamar" => [ 60.7945, 11.0680, "E" ], "Lillehammer" => [ 61.1153, 10.4662, "E" ], "Gjøvik" => [ 60.7957, 10.6916, "E" ],
    "Trysil" => [ 61.3150, 12.2640, "E" ], "Geilo" => [ 60.5340, 8.2060, "E" ], "Hemsedal" => [ 60.8640, 8.5530, "E" ],
    "Kristiansand" => [ 58.1467, 7.9956, "S" ], "Stavanger" => [ 58.9700, 5.7331, "W" ], "Haugesund" => [ 59.4138, 5.2680, "W" ],
    "Preikestolen" => [ 58.9917, 6.1886, "W" ],
    "Bergen" => [ 60.3913, 5.3221, "W" ], "Bergen lufthavn Flesland" => [ 60.2934, 5.2181, "W" ], "Voss" => [ 60.6280, 6.4180, "W" ],
    "Flåm" => [ 60.8628, 7.1137, "W" ], "Ålesund" => [ 62.4722, 6.1495, "W" ], "Geiranger" => [ 62.1015, 7.2060, "W" ], "Molde" => [ 62.7375, 7.1591, "W" ],
    "Trondheim" => [ 63.4305, 10.3951, "M" ], "Trondheim lufthavn Værnes" => [ 63.4578, 10.9240, "M" ], "Røros" => [ 62.5747, 11.3842, "M" ], "Bodø" => [ 67.2804, 14.4049, "N" ],
    "Narvik" => [ 68.4385, 17.4273, "N" ], "Tromsø" => [ 69.6492, 18.9553, "N" ]
  }.freeze

  # Fallback only: pairs assumed to need a ferry when no real route is available
  FERRY = [ %w[Bergen Stavanger], %w[Haugesund Stavanger], %w[Bergen Ålesund], %w[Bergen Molde],
            %w[Ålesund Molde], %w[Bodø Narvik], %w[Bodø Tromsø], %w[Stavanger Ålesund], %w[Ålesund Geiranger] ].freeze

  # Market reference rates (NOK excl. VAT) used for suggestions, the floor and the price guarantee.
  # Built the way Norwegian operators publish their prices: a call-out fee (oppmøte) per day, an hourly rate,
  # and a diesel surcharge per km beyond FREE_KM a day. Tolls, ferries and driver hotel come on top.
  #   start/hr: Oslo Turbuss price list (minibus 1 500 + 850/h, 50-seat coach 2 900 + 1 000/h,
  #             79-seat double-decker 3 900 + 1 200/h; https://www.oslo-turbuss.no/priser/) and leiebusser.no
  #             (coach 900–1 400/h; https://www.leiebusser.no/leie-turbuss-pris/). Calibrated so fixed trip prices
  #             published by Oslobuss, Tide and Trip by Nobina come out within ~15 % (see test/models/pricing_test.rb).
  #   km:       Oslo Turbuss diesel surcharge 9 kr/km beyond 200 km (coach); other classes scaled by fuel use.
  #   ferry:    AutoPASS fares by vehicle length 2026, e.g. Mortavika–Arsvågen 6–8 m 390, 8–10 m 514,
  #             12.5–14.5 m 678 kr (https://www.fergeruter.info/priser/mortavika-arsvagen).
  VehicleClass = Data.define(:id, :seats, :start, :hr, :km, :ferry)
  CLASSES = [
    VehicleClass.new(id: "mini",  seats: 16, start: 900,  hr: 850,  km: 4,  ferry: 390),
    VehicleClass.new(id: "midi",  seats: 35, start: 1000, hr: 950,  km: 6,  ferry: 515),
    VehicleClass.new(id: "coach", seats: 53, start: 1200, hr: 1100, km: 9,  ferry: 680),
    VehicleClass.new(id: "dd",    seats: 79, start: 1800, hr: 1300, km: 11, ferry: 680)
  ].freeze
  CLASS_IDS = CLASSES.map(&:id).freeze

  REGION_FACTOR = { "E" => 1.0, "S" => 0.97, "W" => 1.05, "M" => 0.97, "N" => 1.1 }.freeze
  FLOOR = 0.85          # Bussly minimum: 85 % of suggested rate
  GUARANTEE_BUFFER = 1.15 # price guarantee = market price + 15 %
  COMMISSION = 0.12
  VAT = 0.12
  FREE_KM = 200         # km per day included before the diesel surcharge (Oslo Turbuss: "utover 20 mil")
  WAIT_SHARE = 0.6      # waiting time billed at 60 % of the hourly rate (Bussly policy)
  DRIVER2_HOURLY = 520  # second driver, NOK/h (estimate)
  # Driver overnight: average hotel room in Norway ~1 400–1 570 kr excl. VAT (SSB / NHO Reiseliv 2026)
  # plus the state's per-day meal allowance with overnight stay, 1 012 kr in 2026 (statens særavtale).
  HOTEL_ROOM = 1500
  DRIVER_DIET = 1012
  # Tolls for vehicles over 3 500 kg (AutoPASS rate group 2; buses get no tag discount). City rings per pass:
  # Oslo 109 kr (Euro 6, off-peak, Fjellinjen 2026, https://www.fjellinjen.no/bompenger); other cities ≈ 2× the
  # car rate (https://www.1850.no/trafikk/bompenger). Zero-emission heavy vehicles pass free in Oslo.
  CITY_TOLL = { "Oslo" => 109, "Bergen" => 64, "Trondheim" => 44, "Stavanger" => 60, "Kristiansand" => 50, "Tromsø" => 28 }.freeze
  EV_TOLL_SHARE = 0.3   # zero-emission heavy vehicles: free in Oslo, reduced elsewhere (estimate)
  STOP_DWELL_H = 0.25   # extra stop on the way: pull in, let people on/off (estimate)
  MAX_STOPS = 8
  TOLL_PER_KM = 0.9     # toll roads between cities, NOK/km for rate group 2 (estimate)
  GUIDE_HOURLY = 750    # leiebusser.no: guide 750 kr/h (https://www.leiebusser.no/leie-buss/oslo/)
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
                "start" => ((c.start * f) / 100.0).round * 100, "hr" => ((c.hr * f) / 10.0).round * 10,
                "km" => (c.km * f).round, "minH" => 2 } ]
    end
  end

  def haversine(a, b)
    r = ->(x) { x * Math::PI / 180 }
    d_la = r.(b[0] - a[0]); d_lo = r.(b[1] - a[1])
    s = Math.sin(d_la / 2)**2 + Math.cos(r.(a[0])) * Math.cos(r.(b[0])) * Math.sin(d_lo / 2)**2
    2 * 6371 * Math.asin(Math.sqrt(s))
  end

  # Road distance and bus driving time come from real routes (see Pricing::Routing)
  def road_km(from, to) = Routing.route(from, to).km
  def drive_h(from, to) = Routing.route(from, to).drive_h

  def base_city(name) = name.to_s.sub(/ lufthavn.*/, "")

  def ferry?(from, to)
    a = base_city(from); b = base_city(to)
    FERRY.any? { |x, y| (a == x && b == y) || (a == y && b == x) }
  end
end
