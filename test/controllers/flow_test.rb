require "test_helper"

class FlowTest < ActionDispatch::IntegrationTest
  setup { seed_demo! }

  def search(extra = {})
    { type: "round", from: "Oslo", to: "Hemsedal", date: (Date.current + 30).iso8601, time: "07:30", pax: 42, wait: 6 }.merge(extra)
  end

  test "home page shows offers in Norwegian and English" do
    get root_path(search)
    assert_response :success
    assert_select "article.offer", 3
    assert_select "h1", /Lei buss med sjåfør/
    get root_path(search.merge(lang: "en"))
    assert_select "h1", /Charter a bus/
  end

  test "invalid search shows the error" do
    get root_path(search.merge(to: "Oslo"))
    assert_select "#err", /samme sted/
  end

  test "customer books an operator; price is computed on the server" do
    assert_difference -> { Booking.count } do
      post bookings_path, params: search.merge(op: "solvberg", total: 1,
        booking: { contact_name: "Kari", phone: "+47 912 34 567", email: "kari@example.com", payment_method: "card" })
    end
    b = Booking.last
    assert_equal "ok", b.status # Sølvberg confirms instantly
    assert_operator b.total, :>, 20_000
    assert_in_delta b.total * 0.2, b.deposit, 0.02
  end

  test "checkout requires contact details" do
    assert_no_difference -> { Booking.count } do
      post bookings_path, params: search.merge(op: "solvberg", booking: { contact_name: "" })
    end
    assert_response :unprocessable_entity
  end

  test "guarantee booking becomes an open job an operator can claim" do
    post bookings_path, params: search.merge(type: "oneway", from: "Tromsø", to: "Narvik", op: "garanti",
      booking: { contact_name: "Ola", phone: "+47 912 34 567", email: "ola@example.com" })
    b = Booking.last
    assert_equal "src", b.status
    assert b.guaranteed

    post session_path, params: { email_address: "gauldal@demo.bussly.no", password: "bussly-demo" }
    patch claim_portal_request_path(b.ref)
    assert_equal Operator.find_by(slug: "gauldal"), b.reload.operator
    assert_equal "ok", b.status
  end

  test "operator portal requires login" do
    get portal_root_path
    assert_redirected_to new_session_path
  end

  test "partner signup creates operator with suggested rates and logs in" do
    post partner_path, params: { name: "Fjordekspress AS", org: "123 456 785", licence: "L-1", depot: "Tromsø",
                                 mini: 1, coach: 2, email: "post@fjordekspress.no", password: "hemmelig123" }
    assert_redirected_to portal_rate_card_path
    op = Operator.find_by!(org_number: "123456785")
    assert_equal 2, op.fleet["coach"]["count"]
    assert_equal Pricing.suggested_fleet("Tromsø")["coach"]["hr"], op.fleet["coach"]["hr"]
  end

  test "operator saves rate card; below-minimum is rejected" do
    post session_path, params: { email_address: "solvberg@demo.bussly.no", password: "bussly-demo" }
    patch portal_rate_card_path, params: { operator: { radius: 200, fleet: { coach: { count: 6, hr: 900, km: 21, minH: 4 } } } }
    assert_response :unprocessable_entity
    patch portal_rate_card_path, params: { operator: { radius: 200, fleet: { coach: { count: 6, hr: 1300, km: 21, minH: 4 } } } }
    assert_redirected_to portal_rate_card_path
    assert_equal 1300, Operator.find_by(slug: "solvberg").fleet["coach"]["hr"]
  end
end

class AdminFlowTest < ActionDispatch::IntegrationTest
  test "admin can switch between operators in the portal" do
    load Rails.root.join("db/seeds.rb")
    User.create!(email_address: "admin@example.com", password: "adminpass123", admin: true)
    post session_path, params: { email_address: "admin@example.com", password: "adminpass123" }
    havbris = Operator.find_by!(slug: "havbris")
    post portal_switch_path, params: { operator_id: havbris.id }
    get portal_root_path
    assert_select ".opSel option[selected]", "Havbris Turvogn"
  end
end
