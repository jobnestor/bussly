# The customer's own trip page, reached through the secret link in the confirmation (or "my trips").
class TripsController < ApplicationController
  allow_unauthenticated_access
  before_action :load_booking

  def show
    @tracking = @booking.tracking
    @review = Review.new(author: @booking.contact_name.to_s.split.first, rating: 5)
  end

  def position
    render json: helpers.tracking_json(@booking.tracking(demo_time))
  end

  def cancel
    if @booking.cancel!
      redirect_to trip_path(@booking), notice: helpers.a("trip.cancelled", amount: helpers.nok(@booking.refund))
    else
      redirect_to trip_path(@booking), alert: helpers.a("trip.cancelNo")
    end
  end

  def pay_balance
    if @booking.pay_balance!
      redirect_to trip_path(@booking), notice: helpers.a("trip.balancePaid")
    else
      redirect_to trip_path(@booking)
    end
  end

  def review
    return redirect_to(trip_path(@booking)) unless @booking.reviewable?
    @review = @booking.operator.reviews.new(review_params.merge(booking: @booking, trip_label: helpers.booking_route(@booking)))
    if @review.save
      redirect_to trip_path(@booking), notice: helpers.a("trip.reviewThanks")
    else
      @tracking = @booking.tracking
      render :show, status: :unprocessable_entity
    end
  end

  private

  def load_booking
    @booking = Booking.find_by(token: params[:token].to_s)
    render "trips/missing", status: :not_found unless @booking
  end

  # Demo: ?at=<ISO time> shows where the bus would be at that moment
  def demo_time
    Time.zone.parse(params[:at].to_s) || Time.current
  rescue ArgumentError
    Time.current
  end

  def review_params
    params.require(:review).permit(:rating, :on_time, :author, :comment)
  end
end
