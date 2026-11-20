require "test_helper"

class TrackingTest < ActiveSupport::TestCase
  setup do
    seed_demo!
    @op = Operator.find_by!(slug: "solvberg")
    @b = Booking.create!(operator: @op, trip_type: "round", from_place: "Oslo", to_place: "Lillehammer", date: Date.current + 20,
                         time: "08:00", wait_hours: 4, pax: 40, vehicle_count: 1, vehicle_class: "coach", subtotal: 20_000,
                         customer_subtotal: 20_000, vat: 2400, total: 22_400, deposit: 4480, status: "ok")
    @dep = @b.departure_at
  end

  def at(t) = @b.tracking(t)

  test "follows the schedule: garage, pickup, out, waiting, back, done" do
    assert_equal :scheduled, at(@dep - 3.hours).phase
    assert_equal :to_pickup, at(@dep - 20.minutes).phase
    assert_equal :at_pickup, at(@dep - 5.minutes).phase
    out = at(@dep + 1.hour)
    assert_equal :onboard, out.phase
    assert_equal "Lillehammer", out.next_stop.first
    assert out.fraction.between?(0.2, 0.6)
    leg = Pricing::Trip.new(@b.to_query).leg.hours
    assert_equal :at_destination, at(@dep + leg + 1.hour).phase
    assert_equal :returning, at(@dep + leg + 4.hours + 10.minutes).phase
    assert_equal :done, at(@dep + 2 * leg + 4.hours + 1.minute).phase
  end

  test "position moves between the stops while on board" do
    lat = at(@dep + 1.hour).position[0]
    assert lat > Pricing::CITIES["Oslo"][0] && lat < Pricing::CITIES["Lillehammer"][0]
  end

  test "unconfirmed, cancelled and completed trips do not move" do
    @b.update!(status: "new")
    assert_equal :pending, at(@dep + 1.hour).phase
    @b.update!(status: "cx")
    assert_equal :cancelled, at(@dep + 1.hour).phase
    @b.update!(status: "ok", completed_at: Time.current)
    assert_equal :done, at(@dep + 1.hour).phase
  end

  test "sightseeing loops in the city for the booked hours" do
    @b.update!(trip_type: "sight", to_place: "Oslo", hours: 4, wait_hours: nil)
    assert_equal :touring, at(@dep + 2.hours).phase
    assert_equal :done, at(@dep + 4.hours + 1.minute).phase
  end
end
