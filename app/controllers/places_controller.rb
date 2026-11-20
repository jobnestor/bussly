# Autocomplete for stops: preset places, then Kartverket (Geonorge) place names and street addresses
class PlacesController < ApplicationController
  allow_unauthenticated_access

  def index
    render json: Pricing::Places.search(params[:q].to_s.first(80))
  end
end
