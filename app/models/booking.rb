class Booking < ApplicationRecord
  # new request, confirmed, declined, paid out, open guarantee job, cancelled by the customer
  STATUSES = %w[new ok no paid src cx].freeze
  REF_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars.freeze
  FREE_CANCEL_DAYS = 14
  BALANCE_DUE_DAYS = 7

  belongs_to :operator, optional: true
  has_one :review, dependent: :nullify

  validates :ref, :token, :share_token, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :contact_name, presence: true, on: :checkout
  validates :email, format: { with: /\A\S+@\S+\.\S+\z/ }, on: :checkout
  validate :phone_has_digits, on: :checkout
  validates :driver_name, :vehicle_plate, presence: true, on: :assign_driver
  validate :driver_phone_has_digits, on: :assign_driver

  before_validation :assign_ref, :assign_tokens, if: :new_record?

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
      deposit_paid_at: Time.current,
      **attrs
    )
  end

  # Finds a booking from the "my trips" form; ref is case-insensitive, e-mail must match
  def self.lookup(ref, email)
    return nil if ref.blank? || email.blank?
    b = find_by(ref: ref.to_s.strip.upcase)
    b if b && b.email.to_s.casecmp?(email.to_s.strip)
  end

  def to_param = token

  def payout = subtotal * (1 - Pricing::COMMISSION)
  def balance = total - deposit
  def sight? = trip_type == "sight"
  def oneway? = trip_type == "oneway"
  def round? = trip_type == "round"
  def multi? = trip_type == "multi"
  def confirmed? = %w[ok paid].include?(status)
  def cancelled? = status == "cx"
  def declined? = status == "no"
  def completed? = completed_at.present?
  def balance_paid? = balance_paid_at.present?
  def driver_assigned? = driver_name.present?

  def departure_at = Time.zone.parse("#{date.iso8601} #{time.presence || (sight? ? "09:00" : "08:00")}")
  def return_departure_at = multi? && return_date ? Time.zone.parse("#{return_date.iso8601} #{time.presence || "08:00"}") : nil
  def balance_due_on = date - BALANCE_DUE_DAYS
  def free_cancel_until = date - FREE_CANCEL_DAYS
  def paid_so_far = (deposit_paid_at || created_at ? deposit : 0) + (balance_paid? ? balance : 0)
  def balance_payable?(today = Date.current) = !balance_paid? && !cancelled? && !declined? && !completed? && date >= today

  def cancellable?(today = Date.current) = !cancelled? && !declined? && !completed? && date > today

  # Refund the customer would get if they cancelled today.
  # Free cancellation up to 14 days before departure; after that the 20 % deposit is kept.
  def refund_if_cancelled(today = Date.current)
    return 0 unless cancellable?(today)
    today <= free_cancel_until ? paid_so_far : paid_so_far - deposit
  end

  def cancel!(today = Date.current)
    return false unless cancellable?(today)
    update!(refund: refund_if_cancelled(today).round(2), status: "cx", cancelled_at: Time.current)
  end

  def pay_balance!
    return false unless balance_payable?
    update!(balance_paid_at: Time.current)
  end

  def complete!
    return false unless confirmed? && !completed?
    update!(completed_at: Time.current)
  end

  def reviewable? = completed? && operator && review.nil?

  # Customer-facing progress: requested → confirmed → driver assigned → completed
  def progress_step
    return 3 if completed?
    return 2 if confirmed? && driver_assigned?
    return 1 if confirmed?
    0
  end

  # Rebuild the search so the trip facts (driving time, breaks) match what was priced
  def to_query
    Pricing::Query.new(type: trip_type, from: from_place, to: to_place, date: date, time: time, wait: wait_hours || 0,
                       ret: return_date, pax: pax, electric: electric, luggage: luggage, hours: hours || 4,
                       guide: guide.to_s, cruise: cruise, ship: ship, aboard: aboard)
  end

  def tracking(now = Time.current) = Tracking.new(self, now)

  private

  def assign_ref
    self.ref ||= loop do
      candidate = "BS-" + Array.new(4) { REF_CHARS.sample }.join
      break candidate unless Booking.exists?(ref: candidate)
    end
  end

  def assign_tokens
    self.token ||= SecureRandom.urlsafe_base64(18)
    self.share_token ||= SecureRandom.urlsafe_base64(12)
  end

  def phone_has_digits
    errors.add(:phone, :invalid) if phone.to_s.gsub(/\D/, "").length < 8
  end

  def driver_phone_has_digits
    errors.add(:driver_phone, :invalid) if driver_phone.to_s.gsub(/\D/, "").length < 8
  end
end
