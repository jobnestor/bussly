class PartnersController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 10.minutes, only: :create, with: -> { redirect_to partner_path, alert: helpers.a("loginRate") }

  def new
    @form = default_form
  end

  def create
    @form = default_form.merge(params.permit(*default_form.keys).to_h.symbolize_keys)
    @error = validate(@form)
    return render(:new, status: :unprocessable_entity) if @error

    operator = nil
    ActiveRecord::Base.transaction do
      operator = ::Operator.create!(
        name: @form[:name].strip, depot: @form[:depot], radius: 150, rating: nil, reviews_count: 0,
        org_number: @form[:org].gsub(/\s/, ""), licence_number: @form[:licence].strip, email: @form[:email].strip,
        amenities: [ "Toalett" ],
        fleet: Pricing.suggested_fleet(@form[:depot], "mini" => @form[:mini].to_i, "coach" => @form[:coach].to_i)
      )
      User.create!(email_address: @form[:email], password: @form[:password], operator: operator)
    end
    start_new_session_for operator.users.first
    redirect_to portal_rate_card_path, notice: helpers.a("pCreated").sub(" (demo)", "")
  end

  private

  def default_form
    { name: "", org: "", licence: "", depot: "Oslo", mini: "2", coach: "4", email: "", password: "" }
  end

  def validate(f)
    return helpers.a("peName") if f[:name].blank?
    return helpers.a("peOrg") unless ::Operator.org_number_valid?(f[:org])
    return helpers.a("peOrgTaken") if ::Operator.exists?(org_number: f[:org].gsub(/\s/, ""))
    return helpers.a("peLic") if f[:licence].blank?
    return helpers.a("peEmail") unless f[:email].to_s.match?(/\A\S+@\S+\.\S+\z/)
    return helpers.a("peEmailTaken") if User.exists?(email_address: f[:email].strip.downcase)
    return helpers.a("pePassword") if f[:password].to_s.length < 8
    return helpers.a("peName") unless Pricing.city?(f[:depot])
    nil
  end
end
