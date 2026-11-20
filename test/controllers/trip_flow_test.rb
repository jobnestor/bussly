require "test_helper"

class TripFlowTest < ActionDispatch::IntegrationTest
  setup { seed_demo! }

  def search(extra = {})
    { type: "round", from: "Oslo", to: "Hemsedal", date: (Date.current + 30).iso8601, time: "07:30", pax: 42, wait: 6 }.merge(extra)
  end

  def book!(date: Date.current + 30)
    post bookings_path, params: search(date: date.iso8601).merge(op: "solvberg",
      booking: { contact_name: "Kari Nordmann", phone: "+47 912 34 567", email: "kari@example.com", payment_method: "card" })
    Booking.last
  end

  test "confirmation links to the trip page, which has tracking and a share link" do
    b = book!
    assert b.token.present? && b.share_token.present?
    assert_not_nil b.deposit_paid_at
    get trip_path(b)
    assert_response :success
    assert_select "h1", /Oslo → Hemsedal/
    assert_select "[data-controller=tracking]"
    assert_select "input[value*='/spor/#{b.share_token}']"
    get position_trip_path(b, at: (b.departure_at + 30.minutes).iso8601)
    assert_equal "onboard", response.parsed_body["phase"]
    assert_equal "Hemsedal", response.parsed_body["next_stop"]
  end

  test "passenger link shows no price or customer contact details" do
    b = book!
    get track_path(b.share_token)
    assert_response :success
    assert_no_match(/kr</, response.body)
    assert_no_match(/kari@example.com/, response.body)
  end

  test "unknown links show the not-found page" do
    get trip_path("nope")
    assert_response :not_found
    get track_path("nope")
    assert_response :not_found
  end

  test "my trips finds a booking by reference and e-mail" do
    b = book!
    post lookup_path, params: { ref: b.ref.downcase, email: "KARI@example.com" }
    assert_redirected_to trip_path(b)
    post lookup_path, params: { ref: b.ref, email: "other@example.com" }
    assert_response :unprocessable_entity
  end

  test "free cancellation refunds everything; late cancellation keeps the deposit" do
    early = book!(date: Date.current + 30)
    patch cancel_trip_path(early)
    early.reload
    assert_equal "cx", early.status
    assert_in_delta early.deposit, early.refund, 0.01

    late = book!(date: Date.current + 10)
    patch pay_balance_trip_path(late)
    assert late.reload.balance_paid?
    patch cancel_trip_path(late)
    assert_in_delta late.reload.balance, late.refund, 0.01
  end

  test "operator assigns a driver, completes the trip and the customer reviews it" do
    b = book!
    post session_path, params: { email_address: "solvberg@demo.bussly.no", password: "bussly-demo" }
    patch assign_portal_request_path(b.ref), params: { booking: { driver_name: "Erik", driver_phone: "+47 900 00 001", vehicle_plate: "EV 12345" } }
    assert_equal "Erik", b.reload.driver_name
    get trip_path(b)
    assert_select ".driver b", "Erik"

    b.update_columns(date: Date.current)
    patch complete_portal_request_path(b.ref)
    assert b.reload.completed?

    op = b.operator
    count = op.reviews_count
    assert_difference -> { Review.count } do
      post review_trip_path(b), params: { review: { rating: 5, on_time: "1", author: "Kari", comment: "Supert" } }
    end
    assert_equal count + 1, op.reload.reviews_count
    assert_no_difference -> { Review.count } do
      post review_trip_path(b), params: { review: { rating: 1, author: "Kari" } }
    end
    get operator_profile_path(op)
    assert_select ".reviews", /Supert/
  end

  test "drivers can only be assigned to the operator's own confirmed trips" do
    b = book!
    post session_path, params: { email_address: "brattli@demo.bussly.no", password: "bussly-demo" }
    patch assign_portal_request_path(b.ref), params: { booking: { driver_name: "X", driver_phone: "+47 900 00 001", vehicle_plate: "AB 1" } }
    assert_response :not_found
    assert_nil b.reload.driver_name
  end

  test "results can be filtered and sorted" do
    get root_path(search)
    assert_select "article.offer", 3
    get root_path(search.merge(instant: "1"))
    assert_select "article.offer", 1
    assert_select "article.offer h3", /Sølvberg/
    get root_path(search.merge(sort: "rating"))
    assert_select "article.offer h3" do |h|
      assert_match(/Sølvberg/, h.first.text)
    end
  end

  test "business page stores a shuttle request" do
    get business_path
    assert_response :success
    assert_difference -> { ShuttleRequest.count } do
      post business_path, params: { shuttle_request: { company: "Equinor", contact_name: "Per", email: "per@example.com",
                                                       segment: "commute", route: "Lysaker → Fornebu", riders: 120, weekdays: %w[mon tue xxx] } }
    end
    assert_equal "mon,tue", ShuttleRequest.last.weekdays
    assert_no_difference -> { ShuttleRequest.count } do
      post business_path, params: { shuttle_request: { company: "", contact_name: "", email: "x", segment: "commute", route: "" } }
    end
    assert_response :unprocessable_entity
  end
end
