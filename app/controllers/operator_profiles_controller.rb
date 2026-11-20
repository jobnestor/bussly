# Public profile for an operator: fleet, ratings, on-time record, licence and reviews
class OperatorProfilesController < ApplicationController
  allow_unauthenticated_access

  def show
    @operator = Operator.find_by!(slug: params[:slug])
    @reviews = @operator.reviews.latest.limit(20)
  end
end
