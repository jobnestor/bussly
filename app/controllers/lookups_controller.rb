# "My trips": find a booking from its reference and the e-mail address used at checkout
class LookupsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 5.minutes, only: :create, with: -> { redirect_to lookup_path, alert: helpers.a("loginRate") }

  def new; end

  def create
    if (booking = Booking.lookup(params[:ref], params[:email]))
      redirect_to trip_path(booking)
    else
      flash.now[:alert] = helpers.a("lookup.notFound")
      render :new, status: :unprocessable_entity
    end
  end
end
