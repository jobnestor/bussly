class QuotesController < ApplicationController
  allow_unauthenticated_access

  def index
    @query = Pricing::Query.from_params(params)
    @op_count = Operator.count
    return unless @query.valid?

    session[:last_query] = @query.to_param_hash.transform_values(&:to_s)
    engine = Pricing::Engine.new(@query)
    @trip = engine.trip
    @offers = engine.offers(Operator.all)
    @best = engine.best_value(@offers)
    @guarantee = engine.guarantee if @offers.empty?
  end
end
