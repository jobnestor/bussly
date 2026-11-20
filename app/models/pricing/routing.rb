require "net/http"
require "json"

module Pricing
  # Road routes for a bus: distance, driving time, tolls for large vehicles and ferry crossings.
  #
  # Lookup order for one leg (A → B)
  #   1. db/routes/routes.json – precomputed routes between every pair of preset places (Pricing::CITIES),
  #      built with `bin/rails routes:refresh`. No network needed at quote time.
  #   2. Live providers, in ROUTING_PROVIDERS order (default "vegvesen,osrm"), cached for 30 days:
  #      - vegvesen: Statens vegvesen's route planner (open NVDB road network, NLOD licence). Knows bus
  #        length/weight/height limits, toll stations with the large-vehicle rate (takstStorBil) and ferries.
  #      - osrm: OpenStreetMap routing (OSRM_URL; the public demo server is for testing only). No tolls, so
  #        those are estimated.
  #      Live lookups are on by default except in tests; ROUTING_LIVE=0 turns them off.
  #   3. An estimate: great-circle distance × detour factor (the original prototype model).
  #
  # Multi-stop trips are priced leg by leg (Routing.path), so stops between preset places never need a
  # live call, and each leg is cached on its own.
  #
  # Bus time: the provider's road time with each section capped at the bus speed limit (class III coaches
  # 100 km/h, trafikkreglene § 13) × BUS_TIME_FACTOR for heavier acceleration and climbs. Ferry time is the
  # provider's crossing time; OSRM adds FERRY_WAIT_H per ferry because it only knows the sailing.
  module Routing
    Route = Data.define(:km, :drive_h, :ferries, :toll, :source) do
      def ferry_count = ferries.size
      def estimate? = source == "estimate"
      def toll_estimated? = source != "vegvesen"
    end

    TABLE_PATH = Rails.root.join("db/routes/routes.json")
    OSRM_URL = ENV.fetch("OSRM_URL", "https://router.project-osrm.org")
    VEGVESEN_URL = ENV.fetch("VEGVESEN_ROUTE_URL",
                             "https://www.vegvesen.no/ws/no/vegvesen/ruteplan/routingservice_v3_0/open/routingservice/api/Route/best")
    # 15 m coach, 19 t, 3.8 m – the largest vehicle we sell, so the route works for all classes
    BUS = { Length: 15, Weight: 19, Height: 3.8 }.freeze
    BUS_MAX_KMH = 100
    BUS_TIME_FACTOR = 1.1
    FERRY_WAIT_H = 0.25

    module_function

    def key(a, b) = [ a, b ].sort.join("|")

    def table
      @table ||= TABLE_PATH.exist? ? JSON.parse(TABLE_PATH.read) : {}
    end

    def reload! = @table = nil

    def providers = ENV.fetch("ROUTING_PROVIDERS", "vegvesen,osrm").split(",").map(&:strip)

    def live? = ENV.fetch("ROUTING_LIVE") { Rails.env.test? ? "0" : "1" } == "1"

    # One leg. from/to are place params: a preset name or an encoded "Label~lat,lng" (see Pricing::Places).
    def route(from, to)
      return Route.new(km: 0.0, drive_h: 0.0, ferries: [], toll: 0, source: "same") if from == to
      a = Places.resolve(from) or raise ArgumentError, "unknown place #{from.inspect}"
      b = Places.resolve(to) or raise ArgumentError, "unknown place #{to.inspect}"
      row = table[key(from, to)]
      row ||= Rails.cache.fetch([ "route", key(a.to_param, b.to_param) ], expires_in: 30.days, skip_nil: true) { fetch(a, b) } if live?
      row ? from_row(row, a, b) : estimate(a, b)
    end

    # Several legs: [A, stop1, stop2, B]
    def path(points)
      legs = points.each_cons(2).map { |x, y| route(x, y) }
      return route(points.first, points.first) if legs.empty?
      src = legs.map(&:source).uniq
      Route.new(km: legs.sum(&:km), drive_h: legs.sum(&:drive_h), ferries: legs.flat_map(&:ferries),
                toll: legs.sum(&:toll), source: src.size == 1 ? src.first : (src.include?("estimate") ? "estimate" : "mixed"))
    end

    def from_row(row, a, b)
      toll = row["toll"] || estimated_toll(a, b, row["km"])
      Route.new(km: row["km"], drive_h: row["h"], ferries: row["ferries"], toll: toll, source: row["src"] || "osrm")
    end

    # Tries the live providers in order. Returns a row hash or nil.
    def fetch(a, b)
      providers.each do |p|
        row = case p
        when "vegvesen" then fetch_vegvesen(a, b)
        when "osrm" then fetch_osrm(a, b)
        end
        return row if row
      end
      nil
    end

    # Original prototype model, used when no real route is available
    def estimate(a, b)
      f = 1.3
      if a.region == "W" && b.region == "W" then f = 1.55
      elsif a.region == "W" || b.region == "W" then f = 1.4
      end
      f = [ f, 1.45 ].max if a.region == "N" || b.region == "N"
      km = [ 8.0, Pricing.haversine([ a.lat, a.lng ], [ b.lat, b.lng ]) * f ].max
      speed = (a.region == "E" && b.region == "E") ? 72 : 62
      ferries = Pricing.ferry?(a.name, b.name) ? [ "ferje" ] : []
      Route.new(km: km, drive_h: km / speed + ferries.size * (0.5 + FERRY_WAIT_H), ferries: ferries,
                toll: estimated_toll(a, b, km), source: "estimate")
    end

    # Without toll data: a per-km average plus one pass of each city toll ring at the ends
    def estimated_toll(a, b, km)
      ring = ->(p) { CITY_TOLL.fetch(Pricing.base_city(p.name), 0) }
      (km * TOLL_PER_KM + ring.(a) + ring.(b)).round
    end

    # --- Statens vegvesen route planner ------------------------------------------------------------------

    def fetch_vegvesen(a, b)
      params = { Stops: "#{a.lng},#{a.lat};#{b.lng},#{b.lat}", InputSRS: "EPSG_4326", **BUS }
      data = get_json(VEGVESEN_URL, params, "vegvesen") or return nil
      r = Array(data["routes"]).first or return nil
      return nil if r["isObstructed"]
      summarise_vegvesen(r)
    end

    def summarise_vegvesen(r)
      cap = BUS_MAX_KMH / 3.6 # m/s
      drive_s = 0.0; ferry_s = 0.0; ferries = []
      Array(r["features"]).each do |f|
        p = f["properties"] || {}
        t = p["time"].to_f; d = p["length"].to_f
        crossing = Array(p.dig("roadFeatures", "ferger")).first
        if crossing
          ferry_s += t
          ferries << crossing["navn"].to_s.gsub(/\s*ferjekai/i, "").sub("-", "–").strip
        else
          drive_s += [ t, d / cap ].max
        end
      end
      st = r["statistic"] || {}
      h = drive_s / 3600 * BUS_TIME_FACTOR + ferry_s / 3600
      { "km" => (st["totalLength"].to_f / 1000).round(1), "h" => h.round(3), "ferries" => ferries,
        "toll" => st["tollLarge"].to_i, "src" => "vegvesen" }
    end

    # --- OSRM (OpenStreetMap) -------------------------------------------------------------------------------

    def fetch_osrm(a, b)
      url = "#{OSRM_URL}/route/v1/driving/#{a.lng},#{a.lat};#{b.lng},#{b.lat}"
      data = get_json(url, { overview: "false", steps: "true" }, "osrm") or return nil
      return nil unless data["code"] == "Ok"
      summarise_osrm(data["routes"].first)
    end

    def summarise_osrm(r)
      cap = BUS_MAX_KMH / 3.6 # m/s
      drive_s = 0.0; ferry_s = 0.0; ferries = []
      r["legs"].each do |leg|
        leg["steps"].each do |s|
          d = s["distance"].to_f; t = s["duration"].to_f
          next if t <= 0 && d <= 0
          if s["mode"] == "ferry"
            ferry_s += t
            name = s["name"].to_s.strip
            ferries << (name.empty? ? "ferje" : name) unless ferries.last == name && name.present?
          else
            drive_s += [ t, d / cap ].max
          end
        end
      end
      h = drive_s / 3600 * BUS_TIME_FACTOR + ferry_s / 3600 + ferries.size * FERRY_WAIT_H
      { "km" => (r["distance"] / 1000.0).round(1), "h" => h.round(3), "ferries" => ferries, "src" => "osrm" }
    end

    def get_json(url, params, tag)
      uri = URI(url)
      uri.query = URI.encode_www_form(params)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 20) do |http|
        http.get(uri.request_uri, "User-Agent" => "Bussly/1.0 (bus quotes)")
      end
      return JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("[routing] #{tag} HTTP #{res.code}")
      nil
    rescue StandardError => e
      Rails.logger.warn("[routing] #{tag} failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
