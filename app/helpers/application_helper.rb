module ApplicationHelper
  CLASS_NAMES = {
    nb: { "mini" => "Minibuss", "midi" => "Midibuss", "coach" => "Turbuss", "dd" => "Dobbeltdekker" },
    en: { "mini" => "Minibus", "midi" => "Midibus", "coach" => "Coach", "dd" => "Double-decker" }
  }.freeze
  NBSP = " ".freeze

  def en? = I18n.locale == :en
  def a(key, **opts) = t("app.#{key}", **opts)

  def nok(n)
    s = number_with_delimiter(n.to_f.round, delimiter: en? ? "," : NBSP)
    en? ? "#{s}#{NBSP}NOK" : "#{s}#{NBSP}kr"
  end

  def eur(n)
    return "".html_safe unless en?
    v = ((n.to_f / Pricing::NOK_PER_EUR) / 10).round * 10
    tag.span("≈ €#{number_with_delimiter(v, delimiter: ',')}", class: "eur")
  end

  def fmt_date(d)
    d = d.is_a?(String) ? Date.parse(d) : d
    day = a("days_short")[d.wday]
    mon = a("months_short")[d.month - 1]
    en? ? "#{day} #{d.day} #{mon}" : "#{day} #{d.day}. #{mon}"
  end

  def hm(h)
    hh = h.floor
    mm = (((h - hh) * 60) / 5.0).round * 5
    mm.positive? ? "#{hh} #{a('h')} #{mm} #{a('min')}" : "#{hh} #{a('h')}"
  end

  def class_name(id) = CLASS_NAMES.fetch(I18n.locale, CLASS_NAMES[:nb]).fetch(id.to_s, id.to_s)

  # "Oslo → Borgund stavkyrkje, Lærdal → Bergen"
  def place_chain(from, stops, to) = [ from, *stops.map { |x| Pricing::Places.label(x) }, to ].join(" → ")

  def route_label(q)
    q.sight? ? "#{a('sightIn')} #{q.from}, #{q.hours} #{a('h')}" : place_chain(q.from, q.stop_list, q.to)
  end

  def flag_text(flag)
    _cls, key, vars = flag
    a("flags.#{key}", **(vars || {}))
  end

  QUERY_ERRORS = { pick_from: "eFrom", pick_to: "eTo", same: "eSame", pick_stop: "eStop", range: "ePax", future: "eDate", after: "eRet" }.freeze
  def query_error(query)
    err = query.errors.first
    err && a(QUERY_ERRORS.fetch(err.type, "eFrom"))
  end

  # Same page, other language
  def lang_url(locale) = url_for(request.query_parameters.merge(lang: locale == :en ? "en" : "no", only_path: true))

  def nav_current(*names)
    names.any? { |n| current_page_group == n } ? { "aria-current": "page" } : {}
  end

  def current_page_group
    case controller_path
    when "quotes", "bookings", "operator_profiles" then :book
    when "trips", "tracks", "lookups" then :trips
    when "business" then :business
    when %r{\Aportal/} then :operator
    when "partners" then :partner
    end
  end
end
