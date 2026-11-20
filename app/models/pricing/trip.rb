module Pricing
  # Facts about a trip that are the same for every operator.
  class Trip
    attr_reader :query, :km, :speed, :drive, :leg, :hours, :trip_km, :wait_h, :days, :hotel_nights,
                :two_drivers, :ferry_count, :flags, :ev_ok, :guide_h, :weekend, :peak, :night

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

    def build_route
      q = query
      @km = Pricing.road_km(q.from, q.to)
      @speed = Pricing.speed_for(q.from, q.to)
      @drive = km / speed
      breaks = (drive / 4.5).floor * 0.75
      @leg = drive + breaks
      @wait_h = 0
      @days = 1
      @hotel_nights = 0
      @guide_h = 0
      case q.type
      when "oneway"
        @hours = leg + 0.5; @trip_km = km; daily_drive = drive
      when "round"
        @wait_h = q.wait.to_i; @hours = 2 * leg + 0.5; @trip_km = 2 * km; daily_drive = 2 * drive
      else # multi
        @days = q.days.length
        mid = days - 2
        @hours = 2 * (leg + 0.5) + mid * 6
        @trip_km = 2 * km + mid * 80
        @hotel_nights = days - 1
        daily_drive = drive
      end
      duty = q.round? ? 2 * leg + 1 + wait_h : leg + 1
      @two_drivers = daily_drive > 9 || duty > 13
      @ferry_count = Pricing.ferry?(q.from, q.to) ? (q.oneway? ? 1 : 2) : 0
      @ev_ok = km <= 220 && !q.multi?
      @flags << [ "", :multi, { days: days } ] if q.multi?
      @flags << [ "warn", :two_drivers ] if two_drivers
      @flags << [ "", :break ] if breaks > 0
      @flags << [ "", :ferry ] if ferry_count > 0
      @flags << [ "warn", :ev_no ] if q.electric && !ev_ok
    end

    # Hourly sightseeing hire in one place, optionally from a cruise pier
    def build_sight
      q = query
      @km = 0; @speed = 30; @drive = 0; @leg = 0
      @hours = q.hours + 0.5
      @trip_km = q.hours * 22
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
