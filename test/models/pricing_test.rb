require "test_helper"

# Expected values were produced by the original JavaScript prototype (src/app.html) for the same inputs,
# so these tests guard that the Ruby engine stays identical to the design.
class PricingTest < ActiveSupport::TestCase
  setup { seed_demo! }

  CASES = [
    [ { type: "round", from: "Oslo", to: "Hemsedal", date: "2026-11-25", time: "07:30", pax: 50, wait: 6 },
      [ [ "brattli", "coach", 1, 22712 ], [ "solvberg", "coach", 1, 24556 ], [ "mjosa", "coach", 1, 29920 ] ], nil ],
    [ { type: "round", from: "Oslo", to: "Hemsedal", date: "2026-12-19", time: "07:30", pax: 42, wait: 6, electric: true },
      [ [ "brattli", "coach", 1, 25955 ], [ "solvberg", "coach", 1, 31656 ], [ "mjosa", "coach", 1, 36185 ] ], nil ],
    [ { type: "oneway", from: "Bergen", to: "Ålesund", date: "2026-12-03", time: "23:00", pax: 120, luggage: true },
      [ [ "havbris", "coach", 3, 125465 ] ], nil ],
    [ { type: "multi", from: "Oslo", to: "Trondheim", date: "2026-12-03", ret: "2026-12-06", time: "08:00", pax: 30 },
      [ [ "brattli", "midi", 1, 69176 ], [ "solvberg", "midi", 1, 73889 ], [ "mjosa", "coach", 1, 91752 ] ], nil ],
    [ { type: "oneway", from: "Tromsø", to: "Narvik", date: "2026-12-10", time: "08:00", pax: 35 }, [], 13087 ],
    [ { type: "sight", from: "Bergen", to: "Bergen", date: "2026-12-10", time: "09:00", pax: 16, hours: 4, guide: "EN", cruise: true, aboard: "17:30" },
      [ [ "havbris", "mini", 1, 10007 ] ], nil ],
    [ { type: "round", from: "Stavanger", to: "Bergen", date: "2026-06-06", time: "05:00", pax: 79, wait: 4 },
      [ [ "kystlinje", "dd", 1, 54470 ], [ "havbris", "coach", 2, 125811 ] ], nil ]
  ].freeze

  test "offers match the prototype's pricing engine" do
    CASES.each do |attrs, expected, guarantee|
      engine = Pricing::Engine.new(Pricing::Query.new(attrs))
      offers = engine.offers
      assert_equal expected, offers.map { |o| [ o.operator.slug, o.vehicle_class.id, o.n, o.total.round ] }, attrs.inspect
      assert_equal guarantee, engine.guarantee.total.round if guarantee
    end
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
  end

  test "organisation number check digit (MOD11)" do
    assert Operator.org_number_valid?("123 456 785")
    refute Operator.org_number_valid?("123 456 784")
    refute Operator.org_number_valid?("12345")
  end

  test "rates below the Bussly minimum can't be saved" do
    op = Operator.find_by!(slug: "solvberg")
    op.fleet["coach"]["hr"] = 900
    refute op.save
    assert op.below_floor.dig("coach", "hr")
  end
end
