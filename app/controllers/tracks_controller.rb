# Passenger tracking link: map, status and pickup time only. No prices, no contact details except the driver's.
class TracksController < ApplicationController
  allow_unauthenticated_access
  before_action :load_booking

  def show
    @tracking = @booking.tracking
  end

  def position
    at = (Time.zone.parse(params[:at].to_s) rescue nil) || Time.current
    render json: helpers.tracking_json(@booking.tracking(at))
  end

  private

  def load_booking
    @booking = Booking.find_by(share_token: params[:share_token].to_s)
    render "trips/missing", status: :not_found unless @booking
  end
end
