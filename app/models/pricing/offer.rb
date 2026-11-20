module Pricing
  # One priced option: an operator (or the guarantee) carrying the group with n × vehicle class.
  Offer = Data.define(:operator, :vehicle_class, :n, :lines, :sub, :guide_sub, :vat, :total, :pct,
                      :depot_km, :pos_km, :bill_h, :card, :guaranteed, :market_sub) do
    def ok? = true
    def guaranteed? = guaranteed
    def per_pax(pax) = total / pax
    def deposit = total * DEPOSIT_SHARE
    # What the operator is paid on (excl. VAT). Guarantee jobs go out at market price; the buffer stays with Bussly.
    def operator_sub = guaranteed ? market_sub : sub
    def payout = operator_sub * (1 - COMMISSION)
    def operator_id = operator&.id
  end
end
