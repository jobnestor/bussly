# Keeps the example prices on the static landing pages in public/ in step with the pricing engine and the
# route table. Run after changing rates or refreshing routes:  bin/rails pages:prices  (DRY=1 to preview)
module PagePrices
  NB_SP = "\u00a0"
  DATE = -> { d = Date.new(Date.current.year + (Date.current.month > 3 ? 1 : 0), 3, 8); d += 1 until d.wednesday?; d }
  CLASS_NB = { "mini" => "minibuss", "midi" => "midibuss", "coach" => "turbuss", "dd" => "dobbeltdekker" }.freeze
  ROUTE_PAX = [ 16, 35, 53, 79 ].freeze

  # Route pages: one route, a row per vehicle size
  ROUTES = {
    "oslo-hemsedal" => [ "Oslo", "Hemsedal", "round", { wait: 6 } ],
    "alesund-geiranger" => [ "Ålesund", "Geiranger", "round", { wait: 4 } ],
    "bergen-flam" => [ "Bergen", "Flåm", "round", { wait: 4 } ],
    "bergen-voss" => [ "Bergen", "Voss", "round", { wait: 5 } ],
    "gardermoen-oslo" => [ "Oslo lufthavn Gardermoen", "Oslo", "oneway", {} ],
    "oslo-lillehammer" => [ "Oslo", "Lillehammer", "round", { wait: 5 } ],
    "oslo-trysil" => [ "Oslo", "Trysil", "multi", { days: 3 } ],
    "trondheim-roros" => [ "Trondheim", "Røros", "round", { wait: 5 } ]
  }.freeze

  # City pages: example trips in table order [from, to, type, pax, wait or hours]
  CITIES = {
    "alesund" => [ [ "Ålesund", "Geiranger", "round", 40, 4 ], [ "Ålesund", "Molde", "round", 45, 4 ] ],
    "bergen" => [ [ "Bergen", "Bergen lufthavn Flesland", "oneway", 40 ], [ "Bergen", "Voss", "round", 45, 5 ],
                  [ "Bergen", "Flåm", "round", 35, 4 ], [ "Bergen", "Stavanger", "oneway", 50 ] ],
    "drammen" => [ [ "Drammen", "Oslo lufthavn Gardermoen", "oneway", 40 ], [ "Drammen", "Hemsedal", "round", 45, 6 ],
                   [ "Drammen", "Kongsberg", "round", 30, 4 ] ],
    "kristiansand" => [ [ "Kristiansand", "Stavanger", "oneway", 45 ], [ "Kristiansand", "Oslo", "oneway", 50 ] ],
    "oslo" => [ [ "Oslo", "Oslo lufthavn Gardermoen", "oneway", 45 ], [ "Oslo", "Hemsedal", "round", 42, 6 ],
                [ "Oslo", "Lillehammer", "round", 50, 5 ], [ "Oslo", "Drammen", "round", 30, 4 ] ],
    "stavanger" => [ [ "Stavanger", "Haugesund", "round", 45, 4 ], [ "Stavanger", "Bergen", "oneway", 50 ],
                     [ "Stavanger", "Kristiansand", "oneway", 40 ] ],
    "tromso" => [ [ "Tromsø", "Narvik", "oneway", 35 ], [ "Tromsø", "Tromsø", "sight", 16, 5 ] ],
    "trondheim" => [ [ "Trondheim", "Røros", "round", 48, 5 ], [ "Trondheim", "Ålesund", "oneway", 40 ],
                     [ "Trondheim", "Oslo", "oneway", 50 ] ]
  }.freeze

  CLASS_EN = { "mini" => "minibus", "midi" => "midibus", "coach" => "coach", "dd" => "double-decker" }.freeze
  EUR = 11.7 # NOK per euro, as stated on the English pages

  # English private-sightseeing pages: [place, start time]; rows are [hours, pax, guide]
  SIGHT_EN = {
    "alesund-geiranger" => [ "Ålesund", "09:00" ], "bergen" => [ "Bergen", "09:00" ], "flam" => [ "Flåm", "09:00" ],
    "oslo" => [ "Oslo", "09:00" ], "stavanger" => [ "Stavanger", "09:00" ], "tromso" => [ "Tromsø", "19:00" ]
  }.freeze
  SIGHT_ROWS = [ [ 4, 16, "" ], [ 4, 16, "EN" ], [ 6, 35, "EN" ], [ 8, 53, "EN" ] ].freeze

  # Worked examples in the text of the occasion pages: [from, to, type, pax, date, time, opts]
  OCCASIONS = {
    "bryllup" => [ "Bergen", "Voss", "oneway", 60, "2027-06-19", "23:00", {} ],
    "julebord" => [ "Oslo", "Drammen", "round", 50, "2026-12-04", "18:00", { wait: 5 } ],
    "skoletur" => [ "Oslo", "Lillehammer", "round", 53, "2027-05-05", "09:00", { wait: 6 } ]
  }.freeze

  module_function

  def eur(n) = "€#{en(r10(n / EUR))}"

  def query(from, to, type, pax, opt = {})
    d = opt[:date] || DATE.()
    attrs = { type: type, from: from, to: to, date: d, time: opt[:time] || (type == "sight" ? "09:00" : "08:00"), pax: pax }
    attrs[:wait] = opt[:wait] if opt[:wait]
    attrs[:ret] = d + (opt[:days] - 1) if opt[:days]
    attrs[:hours] = opt[:hours] if opt[:hours]
    attrs[:guide] = opt[:guide] if opt[:guide]
    Pricing::Query.new(attrs)
  end

  def quote(*args)
    e = Pricing::Engine.new(query(*args))
    [ e.market_price, e.trip ]
  end

  def r10(x) = (x / 10.0).round * 10
  def nb(n) = n.round.to_s.reverse.scan(/\d{1,3}/).join(NB_SP).reverse
  def en(n) = n.round.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
  def kr(n) = "#{nb(n)} kr"
  def dur(h) = "#{h.floor} t #{((h - h.floor) * 60 / 5).round * 5} min".sub(/(\d+) t 60 min/) { "#{$1.to_i + 1} t 0 min" }

  def cells(tr) = tr.scan(%r{<td[^>]*>(.*?)</td>}m).flatten

  # Replaces every old value with its new value in one pass, so a new value is never replaced again
  def swap(html, map)
    map = map.reject { |k, v| k == v }
    return html if map.empty?
    html.gsub(Regexp.union(map.keys.sort_by(&:length).reverse)) { |m| map.fetch(m) }
  end

  # Price rows look like: <td>…</td><td>1 × turbuss</td><td class="r">24 560 kr</td><td class="r">460 kr</td>
  def price_rows(html) = html.scan(%r{<tr>(?:(?!</tr>).)*?×(?:(?!</tr>).)*?</tr>}m)

  def update_rows(html, specs)
    map = {}
    price_rows(html).zip(specs).each do |tr, spec|
      next unless spec
      offer, _trip = spec
      pax = spec[2]
      c = cells(tr)
      klass = c.find { |x| x.include?("×") }
      old_total, old_pp = c.last(2)
      total = r10(offer.total); pp = r10(offer.total / pax)
      new_tr = tr.sub(klass, "#{offer.n} × #{CLASS_NB.fetch(offer.vehicle_class.id)}")
                 .sub(">#{old_total}<", ">#{kr(total)}<").sub(">#{old_pp}</td>", ">#{kr(pp)}</td>")
      html = html.sub(tr, new_tr)
      map[old_total] = kr(total)
      map["#{old_pp} per person"] = "#{kr(pp)} per person"
    end
    [ html, map ]
  end

  def facts_map(html, trip)
    rows = html.scan(%r{<tr>(?:(?!</tr>).)*?</tr>}m).map { |tr| cells(tr) }
    get = ->(label) { rows.find { |c| c.first.to_s.start_with?(label) }&.last }
    map = {}
    if (km = get.("Distanse")) then map[km] = "#{trip.km.round} km" end
    if (t = get.("Kjøretid")) then map[t] = dur(trip.leg) end
    if (f = get.("Ferje"))
      html = html.sub(">#{f}</td>", ">#{trip.ferries.any? ? "Ja" : "Nei"}</td>")
    end
    [ html, map ]
  end
end

namespace :pages do
  desc "Recalculate example prices on the static landing pages (public/leie-buss, price guides, llms.txt)"
  task prices: :environment do
    pp_ = PagePrices
    dry = ENV["DRY"] == "1"
    write = ->(path, html) do
      old = File.read(path)
      next puts("  unchanged #{path}") if old == html
      dry ? puts("  would update #{path}") : File.write(path, html)
      puts "  updated #{path}" unless dry
    end
    global = {} # old → new coach prices and distances, reused on the price guides
    pp_::ROUTES.each do |slug, (from, to, type, opt)|
      path = Rails.root.join("public/leie-buss/#{slug}/index.html")
      html = File.read(path)
      specs = pp_::ROUTE_PAX.map { |pax| o, t = pp_.quote(from, to, type, pax, opt); [ o, t, pax ] }
      html, map = pp_.update_rows(html, specs)
      html, fmap = pp_.facts_map(html, specs.first[1])
      map.merge!(fmap)
      puts format("%-20s %s", slug, specs.map { |o, _t, pax| "#{pax}: #{pp_.r10(o.total)}" }.join("  "))
      global.merge!(map)
      write.(path, pp_.swap(html, map))
    end
    pp_::CITIES.each do |slug, rows|
      path = Rails.root.join("public/leie-buss/#{slug}/index.html")
      html = File.read(path)
      specs = rows.map do |from, to, type, pax, x|
        opt = type == "sight" ? { hours: x } : { wait: x }
        o, t = pp_.quote(from, to, type, pax, opt.compact)
        [ o, t, pax ]
      end
      html, map = pp_.update_rows(html, specs)
      puts format("%-20s %s", slug, specs.map { |o, _t, pax| "#{pax}p #{pp_.r10(o.total)}" }.join("  "))
      write.(path, pp_.swap(html, map))
    end
    # English sightseeing pages: hours | pax | vehicle | guide | NOK | €
    pp_::SIGHT_EN.each do |slug, (place, time)|
      path = Rails.root.join("public/en/private-sightseeing/#{slug}/index.html")
      html = File.read(path)
      map = {}
      pp_.price_rows(html).zip(pp_::SIGHT_ROWS).each do |tr, (hours, pax, guide)|
        o, _t = pp_.quote(place, place, "sight", pax, { hours: hours, guide: guide, time: time })
        c = pp_.cells(tr)
        klass = c.find { |x| x.include?("×") }
        old_nok, old_eur = c.last(2)
        nok = "#{pp_.en(pp_.r10(o.total))} NOK"
        new_tr = tr.sub(klass, "#{o.n} × #{pp_::CLASS_EN.fetch(o.vehicle_class.id)}")
                   .sub(">#{old_nok}<", ">#{nok}<").sub(">#{old_eur}<", ">#{pp_.eur(o.total)}<")
        html = html.sub(tr, new_tr)
        map[old_nok] = nok
        map["(#{old_eur})"] = "(#{pp_.eur(o.total)})"
      end
      puts format("%-20s %s", "en/#{slug}", map.select { |k, _| k.end_with?("NOK") }.values.join("  "))
      write.(path, pp_.swap(html, map))
    end

    # Cruise page: one card per port, 4 h for 30 people with an English guide
    path = Rails.root.join("public/en/shore-excursions/index.html")
    html = File.read(path).gsub(%r{(private-sightseeing/([a-z-]+)/">[^<]+</a></h3><p>4 hours for 30 people with an English guide: about )([\d,]+ NOK) \((€[\d,]+)\), (€[\d,]+) per person}) do
      head = $1; place = pp_::SIGHT_EN.fetch($2).first
      o, _t = pp_.quote(place, place, "sight", 30, { hours: 4, guide: "EN" })
      "#{head}#{pp_.en(pp_.r10(o.total))} NOK (#{pp_.eur(o.total)}), #{pp_.eur(o.total / 30)} per person"
    end
    write.(path, html)

    # Tour operators: Bergen → Ålesund, 4 days, coach stays with the group, 40 passengers
    path = Rails.root.join("public/en/tour-operators/index.html")
    o, _t = pp_.quote("Bergen", "Ålesund", "multi", 40, { days: 4 })
    html = File.read(path).sub(%r{about <b>[\d,]+ NOK</b> \(€[\d,]+\)}, "about <b>#{pp_.en(pp_.r10(o.total))} NOK</b> (#{pp_.eur(o.total)})")
    write.(path, html)

    # Occasion pages: "… kl. 23:00: 15 200 kr inkl. mva (250 kr per person) med 1 × dobbeltdekker. Inkluderer 37 % tillegg"
    pp_::OCCASIONS.each do |slug, (from, to, type, pax, date, time, opt)|
      path = Rails.root.join("public/anledning/#{slug}/index.html")
      o, _t = pp_.quote(from, to, type, pax, opt.merge(date: Date.parse(date), time: time))
      html = File.read(path)
      re = /(\d[\d\u00a0]*) kr(<\/b>)? inkl\. mva \((\d[\d\u00a0]*) kr per person\) med (\d+) × ([a-zæøå]+)\. Inkluderer (\d+) %/
      m = html.match(re) or next warn("  no example on #{path}")
      total = pp_.r10(o.total)
      map = { "#{m[1]} kr" => pp_.kr(total) }
      html = html.sub(re, "#{pp_.nb(total)} kr#{m[2]} inkl. mva (#{pp_.nb(pp_.r10(o.total / pax))} kr per person) med #{o.n} × " \
                          "#{pp_::CLASS_NB.fetch(o.vehicle_class.id)}. Inkluderer #{o.pct.round} %")
      puts format("%-20s %s (%d %%)", "anledning/#{slug}", pp_.kr(total), o.pct.round)
      write.(path, pp_.swap(html, map))
    end
    File.write(Rails.root.join("tmp/page_prices.json"), JSON.pretty_generate(global))
  end
end
