module Portal
  # Base for the operator portal. Operators see their own data; admins can switch between operators.
  class BaseController < ApplicationController
    before_action :set_operator
    helper_method :current_user, :current_operator

    private

    def current_user = Current.session&.user

    def current_operator = @operator

    def set_operator
      @operator = if current_user.admin?
        ::Operator.find_by(id: session[:operator_id]) || ::Operator.order(:id).first
      else
        current_user.operator
      end
      redirect_to root_path, alert: helpers.a("noOperator") unless @operator
    end
  end
end
