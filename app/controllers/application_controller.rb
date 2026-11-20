class ApplicationController < ActionController::Base
  include Authentication
  allow_browser versions: :modern

  before_action :set_locale

  private

  def set_locale
    if (lang = params[:lang].presence)
      locale = lang == "en" ? "en" : "nb"
      cookies[:lang] = { value: locale, expires: 1.year }
    end
    I18n.locale = (locale || cookies[:lang]).presence_in(%w[nb en]) || I18n.default_locale
  end

  def default_url_options = {}
end
