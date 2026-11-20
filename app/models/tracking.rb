# Simulated live tracking for a booking.
#
# There is no real GPS feed in the prototype. The bus position is worked out from the booked schedule:
# garage → pickup, waiting at pickup, the trip itself, waiting at the destination and the return.
# Each segment knows its start and end place and time, so the position is the share of the segment
# that has passed. The page asks for a new state every 20 seconds (or for any time in demo mode).
class Tracking
  Segment = Data.define(:phase, :from, :to, :starts_at, :ends_at)
  ACTIVE_STATUSES = %w[ok paid].freeze
  POSITION_KMH = 65.0
  ARRIVE_EARLY = 10.minutes

  attr_reader :booking, :now

  def initialize(booking, now = Time.current)
    @booking = booking
    @now = now
  end

  def segments
    @segments ||= build_segments
  end

  def starts_at = segments.first.starts_at
  def ends_at = segments.last.ends_at

  def active? = ACTIVE_STATUSES.include?(booking.status) && !booking.completed?

  def phase
    return :cancelled if booking.cancelled?
    return :declined if booking.declined?
    return :done if booking.completed?
    return :pending unless ACTIVE_STATUSES.include?(booking.status)
    return :scheduled if now < starts_at
    return :done if now >= ends_at
    current.phase
  end

  def current = segments.find { |s| now >= s.starts_at && now < s.ends_at } || segments.last

  def fraction
    return 0.0 if %i[scheduled pending cancelled declined].include?(phase)
    return 1.0 if phase == :done
    s = current
    span = (s.ends_at - s.starts_at).to_f
    span.positive? ? ((now - s.starts_at) / span).clamp(0.0, 1.0) : 1.0
  end

  def moving? = %i[to_pickup onboard returning touring].include?(phase)

  # Where the bus is now, [lat, lng]
  def position
    case phase
    when :scheduled, :pending, :cancelled, :declined then coords(depot)
    when :done then coords(booking.oneway? ? booking.to_place : booking.from_place)
    when :touring
      c = coords(booking.from_place)
      ang = fraction * 2 * Math::PI
      [ c[0] + 0.018 * Math.sin(ang), c[1] + 0.035 * (1 - Math.cos(ang)) ]
    else
      a = coords(current.from); b = coords(current.to); f = fraction
      [ a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f ]
    end
  end

  # Next place the bus will reach and when
  def next_stop
    return nil unless %i[to_pickup at_pickup onboard at_destination returning touring with_group].include?(phase)
    s = current
    s = segments[segments.index(s) + 1] || s if %i[at_pickup at_destination with_group].include?(phase)
    [ s.to, s.ends_at ]
  end

  def to_h
    stop, eta = next_stop
    {
      phase: phase, fraction: fraction.round(4), position: position.map { |v| v.round(5) },
      leg: (moving? ? { from: coords(current.from), to: coords(current.to), from_name: current.from, to_name: current.to } : nil),
      next_stop: stop, eta: eta&.iso8601, now: now.iso8601, starts_at: starts_at.iso8601, ends_at: ends_at.iso8601,
      stops: stops.map { |n| { name: n, at: coords(n) } }, depot: { name: depot, at: coords(depot) }
    }
  end

  def stops = booking.sight? ? [ booking.from_place ] : [ booking.from_place, booking.to_place ]

  def depot = booking.operator&.depot || booking.from_place

  private

  def coords(name) = Pricing::CITIES.fetch(name, Pricing::CITIES["Oslo"])[0, 2]

  def build_segments
    b = booking
    dep = b.departure_at
    trip = Pricing::Trip.new(b.to_query)
    leg = trip.leg.hours
    pos_h = [ Pricing.road_km(depot, b.from_place) / POSITION_KMH, 0.25 ].max
    pickup_at = dep - ARRIVE_EARLY
    list = [ Segment.new(:to_pickup, depot, b.from_place, pickup_at - pos_h.hours, pickup_at),
             Segment.new(:at_pickup, b.from_place, b.from_place, pickup_at, dep) ]
    if b.sight?
      list << Segment.new(:touring, b.from_place, b.from_place, dep, dep + b.hours.to_i.hours)
      return list
    end
    arrive = dep + leg
    list << Segment.new(:onboard, b.from_place, b.to_place, dep, arrive)
    if b.round?
      back = arrive + b.wait_hours.to_i.hours
      list << Segment.new(:at_destination, b.to_place, b.to_place, arrive, back)
      list << Segment.new(:returning, b.to_place, b.from_place, back, back + leg)
    elsif b.multi? && (last = b.return_departure_at) && last > arrive
      list << Segment.new(:with_group, b.to_place, b.to_place, arrive, last)
      list << Segment.new(:returning, b.to_place, b.from_place, last, last + leg)
    end
    list
  end
end
