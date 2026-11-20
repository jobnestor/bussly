require "net/http"
require "json"

module Pricing
  # A point a bus can drive to: one of the preset places in Pricing::CITIES, or any Norwegian place name or
  # street address found through Kartverket's open Geonorge APIs (stedsnavn and adresser, NLOD licence).
  #
  # Preset places are referred to by name ("Hemsedal"). Other places are encoded as "Label~lat,lng" so that a
  # quote, a booking and a shared link all point at exactly the spot the customer picked from the list.
  Place = Data.define(:name, :lat, :lng, :region) do
    def preset? = CITIES.key?(name)
    def to_param = preset? ? name : "#{name}~#{lat.round(5)},#{lng.round(5)}"
  end

  module Places
    STEDSNAVN_URL = "https://ws.geonorge.no/stedsnavn/v1/navn"
    ADRESSER_URL = "https://ws.geonorge.no/adresser/v1/sok"
    ENCODED = /\A(?<name>[^~|]{1,120})~(?<lat>-?\d{1,2}(?:\.\d+)?),(?<lng>-?\d{1,2}(?:\.\d+)?)\z/
    # Mainland Norway incl. Finnmark; Svalbard has no road connection
    LAT = (57.8..71.3)
    LNG = (4.4..31.3)
    # Name types a bus cannot drive to
    SKIP_TYPES = [ "Øy i sjø", "Holme i sjø", "Fjord", "Innsjø", "Vann", "Elv", "Bekk", "Havområde", "Sund", "Bre", "Skjær", "Grunne", "Havdyp" ].freeze

    module_function

    def resolve(str)
      s = str.to_s.strip
      return nil if s.empty?
      if (c = CITIES[s])
        return Place.new(name: s, lat: c[0], lng: c[1], region: c[2])
      end
      m = ENCODED.match(s) or return nil
      lat = m[:lat].to_f; lng = m[:lng].to_f
      return nil unless LAT.cover?(lat) && LNG.cover?(lng)
      Place.new(name: m[:name].strip, lat: lat, lng: lng, region: region_near(lat, lng))
    end

    def label(str) = str.to_s.split("~").first.to_s.strip

    # Pricing region of the nearest preset place (W fjord country, M Trøndelag, N north, E east/south)
    def region_near(lat, lng)
      CITIES.values.min_by { |c| Pricing.haversine(c, [ lat, lng ]) }[2]
    end

    # Autocomplete: preset places first, then Geonorge place names, then street addresses.
    # Returns [{ label:, value: }]. Network failures just mean fewer suggestions.
    def search(query, limit: 8)
      q = query.to_s.strip
      return [] if q.length < 2
      down = q.downcase
      out = CITIES.keys.select { |n| n.downcase.start_with?(down) || n.downcase.include?(" #{down}") }
                  .map { |n| { label: n, value: n } }
      return out.first(limit) unless Routing.live?
      remote = Rails.cache.fetch([ "places", down ], expires_in: 1.day, skip_nil: true) do
        (q.match?(/\d/) ? addresses(q) : []) + place_names(q)
      end
      (out + Array(remote)).uniq { |h| h[:value] }.first(limit)
    end

    def place_names(q)
      data = get_json(STEDSNAVN_URL, sok: "#{q}*", treffPerSide: 10, utkoordsys: 4258) or return []
      Array(data["navn"]).filter_map do |n|
        next if SKIP_TYPES.include?(n["navneobjekttype"])
        pt = n["representasjonspunkt"] or next
        kommune = Array(n["kommuner"]).first&.dig("kommunenavn")
        name = [ n["skrivemåte"], kommune ].compact.uniq.join(", ")
        place_hash(name, pt["nord"], pt["øst"])
      end
    end

    def addresses(q)
      data = get_json(ADRESSER_URL, sok: q, treffPerSide: 5, utkoordsys: 4258) or return []
      Array(data["adresser"]).filter_map do |a|
        pt = a["representasjonspunkt"] or next
        place_hash("#{a["adressetekst"]}, #{a["poststed"].to_s.capitalize}", pt["lat"], pt["lon"])
      end
    end

    def place_hash(name, lat, lng)
      return nil unless lat && lng && LAT.cover?(lat.to_f) && LNG.cover?(lng.to_f)
      p = Place.new(name: name.to_s.delete("~|").strip, lat: lat.to_f, lng: lng.to_f, region: nil)
      { label: p.name, value: p.to_param }
    end

    def get_json(url, params)
      uri = URI(url)
      uri.query = URI.encode_www_form(params)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 5) do |http|
        http.get(uri.request_uri, "User-Agent" => "Bussly/1.0")
      end
      res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body) : nil
    rescue StandardError => e
      Rails.logger.warn("[places] #{uri&.host} failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
