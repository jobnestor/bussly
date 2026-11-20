module TripsHelper
  PHASE_KEYS = %i[pending scheduled to_pickup at_pickup onboard at_destination with_group returning touring done cancelled declined].freeze

  def booking_route(b) = b.sight? ? "#{a('sightIn')} #{b.from_place}" : "#{b.from_place} → #{b.to_place}"

  def phase_label(phase) = a("track.#{phase}")

  def clock(t) = t&.in_time_zone&.strftime("%H:%M")

  def stars(rating)
    full = rating.to_f.round
    tag.span("★" * full + "☆" * (5 - full), class: "stars", "aria-label": "#{format('%.1f', rating.to_f)} / 5")
  end

  # One line explaining what is happening right now
  def phase_detail(tracking)
    b = tracking.booking
    case tracking.phase
    when :scheduled then a("trackD.scheduled", depot: tracking.depot, time: clock(tracking.starts_at), date: fmt_date(tracking.starts_at.to_date))
    when :pending then b.guaranteed? ? a("trackD.pendingGuar") : a("trackD.pending")
    when :to_pickup, :onboard, :returning, :at_pickup, :at_destination, :with_group, :touring
      stop, eta = tracking.next_stop
      a("trackD.next", stop: stop, time: clock(eta))
    when :done then a("trackD.done")
    when :cancelled then a("trackD.cancelled")
    when :declined then a("trackD.declined")
    end
  end

  def tracking_json(tracking)
    tracking.to_h.merge(label: phase_label(tracking.phase), detail: phase_detail(tracking), clock: clock(tracking.now))
  end

  def timeline_steps(b)
    [ [ a("trip.stepReq"), b.created_at ], [ a("trip.stepOk"), nil ], [ a("trip.stepDriver"), nil ], [ a("trip.stepDone"), b.completed_at ] ]
  end
end
