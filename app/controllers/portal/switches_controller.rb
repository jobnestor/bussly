module Portal
  class SwitchesController < BaseController
    def create
      session[:operator_id] = params[:operator_id] if current_user.admin?
      redirect_back fallback_location: portal_root_path
    end
  end
end
