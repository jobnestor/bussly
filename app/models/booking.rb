class Booking < ApplicationRecord
  STATUSES = %w[new ok no paid src].freeze # new request, confirmed, declined, paid out, open guarantee job
  REF_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars.freeze

  belongs_to :operator, optional: true

  validates :ref, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :contact_name, presence: true, on: :checkout
  validates :email, format: { with: /\A\S+@\S+\.\S+\z/ }, on: :checkout
  validate :phone_has_digits, on: :checkout

  before_validation :assign_ref, if: :new_record?

  scope :open_jobs, -> { where(status: "src") }
  scope :recent_first, -> { order(date: :asc) }

  def self.build_from_offer(query, offer, attrs = {})
    new(
      trip_type: query.type, from_place: query.from, to_place: query.to, date: query.date, time: query.time,
      return_date: (query.ret if query.multi?), wait_hours: (query.wait if query.round?), pax: query.pax,
      electric: query.electric, luggage: query.luggage, hours: (query.hours if query.sight?), guide: query.guide.presence,
      cruise: query.cruise, ship: query.ship, aboard: query.aboard,
      operator: offer.operator, vehicle_count: offer.n, vehicle_class: offer.vehicle_class.id,
      subtotal: offer.operator_sub.round(2), customer_subtotal: offer.sub.round(2), guide_subtotal: offer.guide_sub.round(2),
      vat: offer.vat.round(2), total: offer.total.round(2), deposit: offer.deposit.round(2),
      guaranteed: offer.guaranteed?,
      status: offer.guaranteed? ? "src" : (offer.operator.instant? ? "ok" : "new"),
      breakdown: offer.lines.transform_values { |v| (v * offer.n).round(2) },
      **attrs
    )
  end

  def payout = subtotal * (1 - Pricing::COMMISSION)
  def balance = total - deposit
  def sight? = trip_type == "sight"
  def confirmed? = %w[ok paid].include?(status)

  private

  def assign_ref
    self.ref ||= loop do
      candidate = "BS-" + Array.new(4) { REF_CHARS.sample }.join
      break candidate unless Booking.exists?(ref: candidate)
    end
  end

  def phone_has_digits
    errors.add(:phone, :invalid) if phone.to_s.gsub(/\D/, "").length < 8
  end
end
