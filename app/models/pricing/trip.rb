module Pricing
  # Facts about a trip that are the same for every operator.
  class Trip
    attr_reader :query, :route, :back, :ferries, :km, :speed, :drive, :leg, :hours, :trip_km, :wait_h, :days, :hotel_nights,
                :two_drivers, :ferry_count, :flags, :ev_ok, :guide_h, :weekend, :peak, :night, :toll, :stops, :dwell_h

    def initialize(query)
      @query = query
      @flags = []
      query.sight? ? build_sight : build_route
      d = query.date
      @weekend = d.saturday? || d.sunday?
      @peak = [ 5, 6, 12 ].include?(d.month)
      hr = (query.time.presence || (query.sight? ? "09" : "08")).to_i
      @night = hr < 6 || hr >= 22
    end

    def sight? = query.sight?

    private

    # Outbound: pickup → stops → destination. Return trips drive straight back (stops are on the way out).
    def build_route
      q = query
      @stops = q.stop_list
      @route = Routing.path([ q.from, *stops, q.to ])
      @back = q.oneway? ? nil : Routing.route(q.to, q.from)
      @km = route.km
      @drive = route.drive_h
      @speed = drive.positive? ? km / drive : 0
      back_drive = back&.drive_h.to_f
      # Driving-time rules: 45 min rest after 4.5 h behind the wheel (EU 561/2006, Statens vegvesen)
      brk = ->(h) { (h / 4.5).floor * 0.75 }
      breaks = brk.(drive) + brk.(back_drive)
      @leg = drive + brk.(drive)
      back_leg = back_drive + brk.(back_drive)
      @dwell_h = stops.size * STOP_DWELL_H
      @wait_h = 0
      @days = 1
      @hotel_nights = 0
      @guide_h = 0
      @toll = route.toll + back&.toll.to_i
      case q.type
      when "oneway"
        @hours = leg + dwell_h + 0.5; @trip_km = km; daily_drive = drive
      when "round"
        @wait_h = q.wait.to_i; @hours = leg + back_leg + dwell_h + 0.5; @trip_km = km + back.km
        daily_drive = drive + back_drive
      else # multi
        @days = q.days.length
        mid = days - 2
        @hours = leg + dwell_h + 0.5 + back_leg + 0.5 + mid * 6
        @trip_km = km + back.km + mid * 80
        @toll += (mid * 80 * TOLL_PER_KM).round
        @hotel_nights = days - 1
        daily_drive = [ drive, back_drive ].max
      end
      duty = q.round? ? leg + back_leg + dwell_h + 1 + wait_h : leg + dwell_h + 1
      @two_drivers = daily_drive > 9 || duty > 13
      @ferries = route.ferries + Array(back&.ferries)
      @ferry_count = ferries.size
      @ev_ok = km <= 220 && !q.multi?
      @flags << [ "", :multi, { days: days } ] if q.multi?
      @flags << [ "", :stops, { n: stops.size, list: stops.map { |x| Places.label(x) }.join(" → ") } ] if stops.any?
      @flags << [ "warn", :two_drivers ] if two_drivers
      @flags << [ "", :break ] if breaks > 0
      @flags << [ "", :ferry, { names: ferries.uniq.join(", ") } ] if ferry_count > 0
      @flags << [ "", :route_estimate ] if route.estimate? || back&.estimate?
      @flags << [ "warn", :ev_no ] if q.electric && !ev_ok
    end

    # Hourly sightseeing hire in one place, optionally from a cruise pier
    def build_sight
      q = query
      @km = 0; @speed = 30; @drive = 0; @leg = 0; @ferries = []; @stops = []; @dwell_h = 0
      @hours = q.hours + 0.5
      @trip_km = q.hours * 12 # city sightseeing: AnyBus24 reference day is 8 h / 80–100 km
      @toll = (trip_km * TOLL_PER_KM + CITY_TOLL.fetch(Pricing.base_city(q.from), 0)).round
      @wait_h = 0; @days = 1; @hotel_nights = 0
      @two_drivers = q.hours > 12
      @ferry_count = 0
      @ev_ok = true
      @guide_h = q.guide.present? ? q.hours : 0
      @flags << [ "", :guide, { lang: q.guide } ] if q.guide.present?
      if q.cruise && q.aboard.present?
        to_min = ->(s) { h, m = s.split(":").map(&:to_i); h * 60 + m.to_i }
        slack = to_min.(q.aboard) - (to_min.(q.time.presence || "09:00") + q.hours * 60)
        @flags << (slack >= 60 ? [ "good", :ship_ok ] : [ "warn", :ship_bad ])
      end
    end
  end
end
