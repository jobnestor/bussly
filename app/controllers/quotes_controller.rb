class QuotesController < ApplicationController
  allow_unauthenticated_access

  SORTS = %w[price rating ontime].freeze
  FILTERS = %w[instant toilet ev].freeze

  def index
    @query = Pricing::Query.from_params(params)
    @op_count = Operator.count
    @sort = params[:sort].presence_in(SORTS) || "price"
    @filters = FILTERS.select { |f| params[f] == "1" }
    return unless @query.valid?

    session[:last_query] = @query.to_param_hash.transform_values(&:to_s)
    engine = Pricing::Engine.new(@query)
    @trip = engine.trip
    @all_offers = engine.offers(Operator.all)
    @offers = sort_offers(filter_offers(@all_offers))
    @best = engine.best_value(@offers)
    @guarantee = engine.guarantee if @all_offers.empty?
  end

  private

  def filter_offers(offers)
    offers.select do |o|
      op = o.operator
      (!@filters.include?("instant") || op.instant?) &&
        (!@filters.include?("toilet") || op.has_amenity?("Toalett")) &&
        (!@filters.include?("ev") || (op.ev? && @trip.ev_ok))
    end
  end

  def sort_offers(offers)
    case @sort
    when "rating" then offers.sort_by { |o| [ -(o.operator.rating || 0).to_f, o.total ] }
    when "ontime" then offers.sort_by { |o| [ -(o.operator.on_time_pct || 0), o.total ] }
    else offers
    end
  end
end
