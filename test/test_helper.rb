ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    parallelize(workers: 1)

    def seed_demo!
      load Rails.root.join("db/seeds.rb")
    end
  end
end
