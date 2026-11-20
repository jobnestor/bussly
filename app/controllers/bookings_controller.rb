class BookingsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 20, within: 10.minutes, only: :create, with: -> { head :too_many_requests }

  before_action :load_offer

  def new
    @booking = Booking.new(payment_method: "card")
  end

  def create
    @booking = Booking.build_from_offer(@query, @offer, booking_params.merge(locale: I18n.locale.to_s))
    if @booking.save(context: :checkout)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.update("modal", partial: "bookings/confirmation", locals: { booking: @booking }) }
        format.html { render :show }
      end
    else
      @error = helpers.a("mErr")
      render :new, status: :unprocessable_entity
    end
  end

  private

  # The price is always recomputed on the server from the search + operator; nothing price-related comes from the browser.
  def load_offer
    @query = Pricing::Query.from_params(params)
    @offer = nil
    if @query.valid?
      engine = Pricing::Engine.new(@query)
      if params[:op] == "garanti"
        @offer = engine.guarantee if engine.offers.empty?
      elsif (op = Operator.find_by(slug: params[:op]))
        result = engine.price(op)
        @offer = result if result.ok?
      end
    end
    render :gone, status: :unprocessable_entity unless @offer
  end

  def booking_params
    params.fetch(:booking, {}).permit(:contact_name, :phone, :email, :organisation, :payment_method).tap do |p|
      p[:payment_method] = "card" unless %w[card invoice].include?(p[:payment_method])
    end
  end
end
