class Review < ApplicationRecord
  belongs_to :operator
  belongs_to :booking, optional: true

  validates :rating, inclusion: { in: 1..5 }
  validates :author, presence: true, length: { maximum: 60 }
  validates :comment, length: { maximum: 1000 }
  validates :booking_id, uniqueness: true, allow_nil: true

  scope :latest, -> { order(created_at: :desc) }

  after_create :update_operator_stats

  private

  # Running averages so the stored rating, review count and on-time share stay in step with new reviews
  def update_operator_stats
    op = operator
    n = op.reviews_count.to_i
    rating = op.rating ? ((op.rating.to_f * n) + self.rating) / (n + 1) : self.rating
    on_time = op.on_time_pct ? ((op.on_time_pct.to_f * n) + (self.on_time ? 100 : 0)) / (n + 1) : (self.on_time ? 100 : 0)
    op.update_columns(rating: rating.round(1), reviews_count: n + 1, on_time_pct: on_time.round, updated_at: Time.current)
  end
end
