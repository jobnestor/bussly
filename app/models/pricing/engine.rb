module Pricing
  # Applies rate cards to a trip.
  #
  # A "rate card" is anything responding to: depot, radius, pos_factor, blocked_dates, ev?, surcharges, fleet
  # (fleet is { "coach" => { "count", "start", "hr", "km", "minH" } ... }).
  #
  # Per bus: call-out fee per day + billed hours + empty driving to/from the depot (time) + waiting +
  # diesel surcharge per km beyond FREE_KM a day + second driver + driver hotel and allowance + tolls + ferries.
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
      # Empty driving. Operators: depot → pickup and back from the drop-off. Market price: a one-way bus
      # still has to get home, so the return to the pickup point is charged (Oslo Turbuss and others do the same).
      depot_km = ignore_area ? 0.0 : Pricing.road_km(op.depot, q.from)
      return Rejection.new(reason: :radius, depot_km: depot_km) if !ignore_area && depot_km > op.radius
      back_from = q.oneway? ? q.to : q.from
      pos = if ignore_area
        q.oneway? ? [ Routing.route(q.to, q.from) ] : []
      else
        [ Routing.route(op.depot, q.from), Routing.route(back_from, op.depot) ]
      end
      pos_km = pos.sum(&:km); pos_h = pos.sum(&:drive_h); pos_toll = pos.sum(&:toll)
      pos_f = ignore_area ? 1.0 : op.pos_factor.to_f
      sur = op.surcharges
      best = nil

      CLASSES.each do |c|
        card = op.fleet[c.id]
        next if card.nil? || card["count"].to_i <= 0
        n = (q.pax.to_f / c.seats).ceil
        next if n > card["count"].to_i
        start = card["start"].to_f; hr = card["hr"].to_f; km = card["km"].to_f; min_h = card["minH"].to_f
        # The minimum applies to the whole job, so empty driving counts towards it
        pos_bill = pos_h * pos_f
        bill_h = [ t.hours, min_h * t.days - pos_bill ].max
        drivers = t.two_drivers ? 2 : 1
        green = q.electric && op.ev? && t.ev_ok
        l = {}
        l[:start]   = start * t.days
        l[:hours]   = bill_h * hr
        l[:km]      = [ t.trip_km + pos_km * pos_f - FREE_KM * t.days, 0 ].max * km
        l[:pos]     = pos_bill * hr
        l[:wait]    = t.wait_h * hr * WAIT_SHARE
        l[:driver2] = t.two_drivers ? (t.hours + t.wait_h) * DRIVER2_HOURLY : 0
        l[:hotel]   = t.hotel_nights * (HOTEL_ROOM + DRIVER_DIET) * drivers
        # Large-vehicle toll rates from Statens vegvesen. Zero-emission buses pay far less (0 in Oslo's ring).
        l[:toll]    = (t.toll + pos_toll) * (green ? EV_TOLL_SHARE : 1)
        l[:ferry]   = t.ferry_count * c.ferry
        l[:trailer] = q.luggage ? 950 * t.days : 0
        base = l[:start] + l[:hours] + l[:km] + l[:pos] + l[:wait] + l[:driver2]
        pct = (t.weekend ? sur[:weekend] : 0) + (t.peak ? sur[:peak] : 0) + (t.night ? sur[:night] : 0)
        l[:sur] = base * pct / 100.0
        l[:ev]  = green ? base * 0.08 : 0
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
