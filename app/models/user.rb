class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  belongs_to :operator, optional: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  validates :email_address, presence: true, uniqueness: true, format: { with: /\A\S+@\S+\.\S+\z/ }
  validates :password, length: { minimum: 8 }, allow_nil: true
end
