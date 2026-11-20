require "test_helper"

# Snapshot of the engine for typical trips, using the demo operators (db/seeds.rb) and the route table in
# db/routes/routes.json (no network in tests). The engine follows the Norwegian price model – call-out fee,
# hourly rate, diesel surcharge beyond 200 km, real large-vehicle tolls and ferries – so these values changed
# from the original JavaScript prototype on purpose. Update them only when a pricing change is intended.
class PricingTest < ActiveSupport::TestCase
  setup { seed_demo! }

  CASES = [
    [ { type: "round", from: "Oslo", to: "Hemsedal", date: "2026-11-25", time: "07:30", pax: 50, wait: 6 },
      [ [ "solvberg", "coach", 1, 25028 ], [ "brattli", "coach", 1, 25429 ], [ "mjosa", "coach", 1, 32616 ] ], nil ],
    [ { type: "round", from: "Oslo", to: "Hemsedal", date: "2026-12-19", time: "07:30", pax: 42, wait: 6, electric: true },
      [ [ "brattli", "coach", 1, 29034 ], [ "solvberg", "coach", 1, 31502 ], [ "mjosa", "coach", 1, 39297 ] ], nil ],
    [ { type: "oneway", from: "Bergen", to: "Ålesund", date: "2026-12-03", time: "23:00", pax: 120, luggage: true },
      [ [ "havbris", "coach", 3, 125301 ] ], nil ],
    [ { type: "multi", from: "Oslo", to: "Trondheim", date: "2026-12-03", ret: "2026-12-06", time: "08:00", pax: 30 },
      [ [ "brattli", "midi", 1, 51113 ], [ "solvberg", "midi", 1, 52215 ], [ "mjosa", "coach", 1, 67831 ] ], nil ],
    [ { type: "oneway", from: "Tromsø", to: "Narvik", date: "2026-12-10", time: "08:00", pax: 35 }, [], 16081 ],
    [ { type: "sight", from: "Bergen", to: "Bergen", date: "2026-12-10", time: "09:00", pax: 16, hours: 4, guide: "EN", cruise: true, aboard: "17:30" },
      [ [ "havbris", "mini", 1, 10023 ] ], nil ],
    [ { type: "round", from: "Stavanger", to: "Bergen", date: "2026-06-06", time: "05:00", pax: 79, wait: 4 },
      [ [ "kystlinje", "dd", 1, 52679 ], [ "havbris", "coach", 2, 146405 ] ], nil ],
    [ { type: "oneway", from: "Oslo", to: "Bergen", stops: "Flåm", date: "2026-12-10", time: "08:00", pax: 40 },
      [ [ "brattli", "coach", 1, 24660 ], [ "solvberg", "coach", 1, 34523 ], [ "mjosa", "coach", 1, 37457 ] ], nil ]
  ].freeze

  # Published fixed prices incl. VAT for one coach, one way, off-peak weekday:
  # Oslobuss (oslobuss.no/leie-av-buss), Tide (tide.no/leie-buss), Trip by Nobina (tripbynobina.com/no/leie-buss)
  BENCHMARKS = [
    [ "Oslo", "Oslo lufthavn Gardermoen", 4000 ],
    [ "Oslo", "Hemsedal", 13_500 ],
    [ "Bergen lufthavn Flesland", "Bergen", 3444 ],
    [ "Trondheim lufthavn Værnes", "Trondheim", 3640 ],
    [ "Stavanger", "Preikestolen", 4990 ],
    [ "Dombås", "Ålesund", 15_990 ]
  ].freeze

  test "offers match the pricing snapshot" do
    CASES.each do |attrs, expected, guarantee|
      engine = Pricing::Engine.new(Pricing::Query.new(attrs))
      offers = engine.offers
      assert_equal expected, offers.map { |o| [ o.operator.slug, o.vehicle_class.id, o.n, o.total.round ] }, attrs.inspect
      assert_equal guarantee, engine.guarantee.total.round if guarantee
    end
  end

  test "market prices stay within 25 % of published operator prices" do
    BENCHMARKS.each do |from, to, published|
      q = Pricing::Query.new(type: "oneway", from: from, to: to, date: "2027-02-03", time: "10:00", pax: 45)
      market = Pricing::Engine.new(q).market_price.total
      assert_in_delta 1.0, market / published, 0.25, "#{from} → #{to}: #{market.round} vs #{published}"
    end
    # Hourly sightseeing in Oslo: leiebusser.no quotes 7 000–10 000 kr for a 4–5 hour local trip
    q = Pricing::Query.new(type: "sight", from: "Oslo", to: "Oslo", date: "2027-02-03", time: "10:00", pax: 50, hours: 4)
    assert_includes 6000..10_000, Pricing::Engine.new(q).market_price.total
  end

  test "routes come from the table, with real tolls and ferries" do
    r = Pricing::Routing.route("Bergen", "Stavanger")
    assert_equal "vegvesen", r.source
    assert_equal 2, r.ferry_count
    assert r.toll.positive?
    assert_equal r.km, Pricing::Routing.route("Stavanger", "Bergen").km
    assert Pricing::Routing.route("Oslo", "Hemsedal").km.between?(190, 215)
  end

  test "stops add their legs and 15 minutes each" do
    base = { type: "oneway", from: "Oslo", to: "Bergen", date: "2026-12-10", time: "08:00", pax: 40 }
    direct = Pricing::Trip.new(Pricing::Query.new(base))
    via = Pricing::Trip.new(Pricing::Query.new(base.merge(stops: "Flåm")))
    legs = Pricing::Routing.route("Oslo", "Flåm").km + Pricing::Routing.route("Flåm", "Bergen").km
    assert_in_delta legs, via.km, 0.01
    assert via.hours > direct.hours + Pricing::STOP_DWELL_H - 0.01
    assert(via.flags.any? { |f| f[1] == :stops })
  end

  test "a custom stop from the place search is a valid point" do
    stop = "Borgund stavkyrkje, Lærdal~61.04653,7.8123"
    p = Pricing::Places.resolve(stop)
    assert_equal "Borgund stavkyrkje, Lærdal", p.name
    assert_equal "W", p.region
    assert_equal stop, p.to_param
    assert_nil Pricing::Places.resolve("Somewhere~12.0,-40.0") # outside Norway
    assert_nil Pricing::Places.resolve("Atlantis")
  end

  test "guarantee jobs pay operators the market price, not the buffered price" do
    q = Pricing::Query.new(type: "oneway", from: "Tromsø", to: "Narvik", date: "2026-12-10", time: "08:00", pax: 35)
    g = Pricing::Engine.new(q).guarantee
    assert_in_delta g.sub / Pricing::GUARANTEE_BUFFER, g.operator_sub, 0.01
  end

  test "query validation" do
    tomorrow = Date.current + 1
    assert Pricing::Query.new(type: "oneway", from: "Oslo", to: "Bergen", date: tomorrow, pax: 10).valid?
    refute Pricing::Query.new(type: "oneway", from: "Oslo", to: "Oslo", date: tomorrow, pax: 10).valid?
    refute Pricing::Query.new(type: "oneway", from: "Atlantis", to: "Oslo", date: tomorrow, pax: 10).valid?
    refute Pricing::Query.new(type: "oneway", from: "Oslo", to: "Bergen", date: Date.current, pax: 10).valid?
    refute Pricing::Query.new(type: "multi", from: "Oslo", to: "Bergen", date: tomorrow, ret: tomorrow, pax: 10).valid?
    refute Pricing::Query.new(type: "oneway", from: "Oslo", to: "Bergen", date: tomorrow, pax: 401).valid?
    assert Pricing::Query.new(type: "oneway", from: "Oslo", to: "Bergen", stops: "Flåm|Voss", date: tomorrow, pax: 10).valid?
    refute Pricing::Query.new(type: "oneway", from: "Oslo", to: "Bergen", stops: "Atlantis", date: tomorrow, pax: 10).valid?
  end

  test "organisation number check digit (MOD11)" do
    assert Operator.org_number_valid?("123 456 785")
    refute Operator.org_number_valid?("123 456 784")
    refute Operator.org_number_valid?("12345")
  end

  test "rates below the Bussly minimum can't be saved" do
    op = Operator.find_by!(slug: "solvberg")
    op.fleet["coach"]["hr"] = 800
    refute op.save
    assert op.below_floor.dig("coach", "hr")
  end
end
