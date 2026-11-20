class Operator < ApplicationRecord
  AMENITIES_EN = { "Toalett" => "Toilet", "Kjøleskap" => "Fridge", "Skinnseter" => "Leather seats", "Mikrofon" => "Microphone",
                   "Skiboks" => "Ski box", "Panoramavinduer" => "Panoramic windows" }.freeze
  POS_OPTIONS = [ [ 0, :pos0 ], [ 0.5, :pos50 ], [ 1, :pos100 ] ].freeze

  has_many :bookings, dependent: :nullify
  has_many :users, dependent: :destroy
  has_many :reviews, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :depot, inclusion: { in: Pricing::CITIES.keys }
  validates :radius, numericality: { in: 10..1500 }
  validates :pos_factor, inclusion: { in: [ 0, 0.5, 1 ] }
  validates :sur_weekend, :sur_peak, :sur_night, numericality: { in: 0..100 }
  validates :org_number, uniqueness: true, allow_nil: true
  validate :rates_not_below_floor

  before_validation :ensure_slug, :normalise_fleet

  def to_param = slug
  def licence_verified? = licence_number.present?
  def has_amenity?(name) = Array(amenities).include?(name)
  def fleet_size = fleet.values.sum { |f| f["count"].to_i }

  def surcharges = { weekend: sur_weekend.to_i, peak: sur_peak.to_i, night: sur_night.to_i }
  def suggested_fleet = Pricing.suggested_fleet(depot)

  def apply_suggested_rates!
    sug = suggested_fleet
    self.fleet = Pricing::CLASS_IDS.to_h { |id| [ id, sug[id].merge("count" => fleet.dig(id, "count").to_i) ] }
    self.sur_weekend, self.sur_peak, self.sur_night = Pricing::DEFAULT_SURCHARGES.values_at(:weekend, :peak, :night)
  end

  # Field-level floor check: { "coach" => { "hr" => true } } means coach hourly is below the Bussly minimum
  def below_floor
    sug = suggested_fleet
    Pricing::CLASS_IDS.each_with_object({}) do |id, out|
      f = fleet[id] || {}
      next unless f["count"].to_i > 0
      %w[hr km].each { |k| (out[id] ||= {})[k] = true if f[k].to_f < sug[id][k] * Pricing::FLOOR }
    end
  end

  def below_floor? = below_floor.any?

  def amenity_label(a, locale = I18n.locale) = locale.to_s == "en" ? AMENITIES_EN.fetch(a, a) : a

  def self.org_number_valid?(s)
    d = s.to_s.gsub(/\s/, "")
    return false unless d.match?(/\A\d{9}\z/)
    w = [ 3, 2, 7, 6, 5, 4, 3, 2 ]
    sum = 8.times.sum { |i| d[i].to_i * w[i] }
    k = 11 - (sum % 11)
    k = 0 if k == 11
    return false if k == 10
    k == d[8].to_i
  end

  private

  def ensure_slug
    return if slug.present? || name.blank?
    base = name.parameterize.presence || "operator"
    self.slug = base
    i = 1
    self.slug = "#{base}-#{i += 1}" while Operator.where.not(id: id).exists?(slug: slug)
  end

  def normalise_fleet
    sug = depot.present? && Pricing.city?(depot) ? suggested_fleet : {}
    self.fleet = Pricing::CLASS_IDS.to_h do |id|
      f = (fleet || {})[id] || sug[id] || { "count" => 0, "hr" => 0, "km" => 0, "minH" => 4 }
      [ id, { "count" => f["count"].to_i.clamp(0, 99), "hr" => f["hr"].to_i, "km" => f["km"].to_i, "minH" => f["minH"].to_i.clamp(1, 12) } ]
    end
    self.blocked_dates = Array(blocked_dates).map(&:to_s).select { |d| d.match?(/\A\d{4}-\d{2}-\d{2}\z/) }.uniq.sort
  end

  def rates_not_below_floor
    errors.add(:fleet, :below_minimum) if depot.present? && Pricing.city?(depot) && below_floor?
  end
end
