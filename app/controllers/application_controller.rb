class ApplicationController < ActionController::Base
  before_action { Current.owner = current_user&.owner || current_user }
  before_action :configure_permitted_parameters, if: :devise_controller?

  private
  
  def risk_assistants_scope
    owner_or_self.risk_assistants
  end
  helper_method :risk_assistants_scope

  def owner_or_self
    current_user.owner || current_user
  end
  helper_method :owner_or_self

  def require_authorized_user!
    redirect_to root_path, alert: 'Acceso no autorizado' unless current_user&.owner? || current_user&.client? || current_user&.guest?
  end
  alias_method :require_client!, :require_authorized_user!

  protected

  def after_sign_in_path_for(resource)
    resource.owner? ? owner_dashboard_path : client_dashboard_path
  end  

  def configure_permitted_parameters
    allowed = [:name, :role, :company_name, :owner_id, :logo]
    devise_parameter_sanitizer.permit(:account_update, keys: %i[name role owner_id company_name logo])
    devise_parameter_sanitizer.permit(:sign_up,        keys: %i[name role owner_id company_name logo])
  end
end
