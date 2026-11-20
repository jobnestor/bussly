module Pricing
  # Why an operator can't take the trip: :blocked (day off), :radius (too far from depot) or :no_fleet.
  Rejection = Data.define(:reason, :depot_km) do
    def ok? = false
  end
end
