module Pricing
  # Applies rate cards to a trip.
  #
  # A "rate card" is anything responding to: depot, radius, pos_factor, blocked_dates, ev?, surcharges, fleet
  # (fleet is { "coach" => { "count", "hr", "km", "minH" } ... }).
  class Engine
    MarketCard = Struct.new(:depot, :radius, :pos_factor, :blocked_dates, :ev?, :surcharges, :fleet, :id, keyword_init: true)

    attr_reader :query, :trip

    def initialize(query, trip = Trip.new(query))
      @query = query
      @trip = trip
    end

    def offers(operators = Operator.all)
      operators.map { |op| price(op) }.select(&:ok?).sort_by(&:total)
    end

    # Best value = highest rating per krone
    def best_value(offers)
      offers.max_by { |o| (o.operator.rating || 4.5).to_f / o.total }
    end

    # Returns an Offer or a Rejection
    def price(op, ignore_area: false)
      q = query; t = trip
      unless ignore_area
        blocked = Array(op.blocked_dates).map(&:to_s)
        return Rejection.new(reason: :blocked, depot_km: nil) if q.days.any? { |d| blocked.include?(d.iso8601) }
      end
      depot_km = ignore_area ? 0.0 : Pricing.road_km(op.depot, q.from)
      return Rejection.new(reason: :radius, depot_km: depot_km) if !ignore_area && depot_km > op.radius
      pos_km = if ignore_area then 0.0
      elsif q.oneway? then depot_km + Pricing.road_km(q.to, op.depot)
      else 2 * depot_km
      end
      pos_h = pos_km / 65.0
      sur = op.surcharges
      best = nil

      CLASSES.each do |c|
        card = op.fleet[c.id]
        next if card.nil? || card["count"].to_i <= 0
        n = (q.pax.to_f / c.seats).ceil
        next if n > card["count"].to_i
        hr = card["hr"].to_f; km = card["km"].to_f; min_h = card["minH"].to_f
        bill_h = [ t.hours, min_h * t.days ].max
        l = {}
        l[:hours]   = bill_h * hr
        l[:km]      = t.trip_km * km
        l[:pos]     = (pos_km * km + pos_h * hr) * op.pos_factor.to_f
        l[:wait]    = t.wait_h * hr * 0.6
        l[:driver2] = t.two_drivers ? (t.hours + t.wait_h) * 520 : 0
        l[:hotel]   = t.hotel_nights * 1650 * (t.two_drivers ? 2 : 1)
        l[:toll]    = (t.trip_km + pos_km) * 1.9
        l[:ferry]   = t.ferry_count * 1450
        l[:trailer] = q.luggage ? 950 * t.days : 0
        base = l[:hours] + l[:km] + l[:pos] + l[:wait] + l[:driver2]
        pct = (t.weekend ? sur[:weekend] : 0) + (t.peak ? sur[:peak] : 0) + (t.night ? sur[:night] : 0)
        l[:sur] = base * pct / 100.0
        l[:ev]  = (q.electric && op.ev? && t.ev_ok) ? base * 0.08 : 0
        per_bus = l.values.sum
        sub = per_bus * n
        guide_sub = t.guide_h * GUIDE_HOURLY * n
        vat = sub * VAT + guide_sub * GUIDE_VAT
        next if best && sub >= best.sub
        best = Offer.new(operator: op.is_a?(MarketCard) ? nil : op, vehicle_class: c, n: n, lines: l, sub: sub,
                         guide_sub: guide_sub, vat: vat, total: sub + guide_sub + vat, pct: pct,
                         depot_km: depot_km, pos_km: pos_km, bill_h: bill_h, card: card, guaranteed: false, market_sub: nil)
      end
      best || Rejection.new(reason: :no_fleet, depot_km: depot_km)
    end

    # Market price: suggested rates for the origin region, bus starting at the pickup point
    def market_price
      ref = MarketCard.new(id: nil, depot: query.from, radius: 9999, pos_factor: 0, blocked_dates: [], ev?: true,
                           surcharges: DEFAULT_SURCHARGES,
                           fleet: Pricing.suggested_fleet(query.from, CLASS_IDS.index_with(99)))
      price(ref, ignore_area: true)
    end

    # Price guarantee: market price + 15 % buffer
    def guarantee
      m = market_price
      k = GUARANTEE_BUFFER
      sub = m.sub * k
      vat = sub * VAT + m.guide_sub * GUIDE_VAT
      m.with(lines: m.lines.transform_values { |v| v * k }, sub: sub, vat: vat, total: sub + m.guide_sub + vat,
             guaranteed: true, market_sub: m.sub)
    end
  end
end
