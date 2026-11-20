module Pricing
  # A customer's search. Built from request params; validates itself.
  class Query
    include ActiveModel::Model
    include ActiveModel::Attributes

    TYPES = %w[oneway round multi sight].freeze
    WAIT_OPTIONS = [ 1, 2, 3, 4, 5, 6, 8, 10 ].freeze
    HOUR_OPTIONS = [ 3, 4, 5, 6, 7, 8, 10 ].freeze

    attribute :type, :string, default: "round"
    attribute :from, :string
    attribute :to, :string
    attribute :date, :date
    attribute :time, :string
    attribute :wait, :integer, default: 6
    attribute :ret, :date
    attribute :pax, :integer
    attribute :electric, :boolean, default: false
    attribute :luggage, :boolean, default: false
    attribute :hours, :integer, default: 4
    attribute :guide, :string, default: ""
    attribute :cruise, :boolean, default: false
    attribute :ship, :string
    attribute :aboard, :string
    # Extra stops on the way out, "|"-separated place params (preset names or "Label~lat,lng")
    attribute :stops, :string, default: ""

    PARAMS = %i[type from to stops date time wait ret pax electric luggage hours guide cruise ship aboard].freeze
    STOP_SEP = "|"

    validate :validate_trip

    def self.default(today = Date.current)
      d = today + 21
      d += 1 until d.saturday?
      new(type: "round", from: "Oslo", to: "Hemsedal", date: d, ret: d + 1, time: "07:30", pax: 42, wait: 6)
    end

    # Defaults, then landing-page prefill params (?from=..&to=..&type=..&pax=..&hours=..&guide=..&cruise=1)
    def self.from_params(params, today = Date.current)
      q = default(today)
      raw = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      raw = raw.symbolize_keys
      raw[:stops] = Array(raw[:stops]).map(&:to_s).compact_blank.join(STOP_SEP) if raw[:stops].is_a?(Array)
      p = raw.slice(*PARAMS).compact_blank
      p.delete(:from) if p[:from] && !Pricing.city?(p[:from])
      p.delete(:to) if p[:to] && !Pricing.city?(p[:to])
      p.delete(:type) unless TYPES.include?(p[:type]) || p[:type].nil?
      q.assign_attributes(p)
      q.time = "09:00" if q.sight? && p[:time].blank?
      q.aboard ||= "17:30" if q.cruise
      q.to = q.from if q.sight?
      q
    end

    def sight? = type == "sight"
    def multi? = type == "multi"
    def round? = type == "round"
    def oneway? = type == "oneway"

    def stop_list
      return [] if sight?
      stops.to_s.split(STOP_SEP).map(&:strip).compact_blank.first(Pricing::MAX_STOPS)
    end

    def to_param_hash
      PARAMS.to_h { |k| [ k, public_send(k) ] }.compact_blank
    end

    # Calendar days the bus is booked
    def days
      return [ date ] unless multi?
      (date..ret).to_a
    end

    private

    def validate_trip
      tomorrow = Date.current + 1
      return errors.add(:from, :pick_from) unless Pricing.city?(from)
      unless sight?
        return errors.add(:to, :pick_to) unless Pricing.city?(to)
        return errors.add(:to, :same) if from == to
        return errors.add(:stops, :pick_stop) if stop_list.any? { |x| Pricing::Places.resolve(x).nil? }
      end
      return errors.add(:pax, :range) unless pax && pax.between?(1, 400)
      return errors.add(:date, :future) if date.nil? || date < tomorrow
      errors.add(:ret, :after) if multi? && (ret.nil? || ret <= date)
    end
  end
end
