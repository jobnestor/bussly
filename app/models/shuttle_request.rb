# A business lead for recurring transport (commuter shuttles, event shuttles, airport runs, school routes)
class ShuttleRequest < ApplicationRecord
  SEGMENTS = %w[commute event airport school other].freeze
  WEEKDAYS = %w[mon tue wed thu fri sat sun].freeze

  validates :company, :contact_name, :route, presence: true
  validates :email, format: { with: /\A\S+@\S+\.\S+\z/ }
  validates :segment, inclusion: { in: SEGMENTS }
  validates :riders, numericality: { in: 1..5000 }, allow_nil: true
end
