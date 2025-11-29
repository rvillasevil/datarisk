class RegistrationsController < Devise::RegistrationsController
  def create

    invitation_token = params[:invitation_token].to_s.strip

    return super if invitation_token.blank?

    build_resource(sign_up_params)

    invitation = ClientInvitation.find_by(token: invitation_token, accepted_at: nil)

    unless invitation
      resource.errors.add(:base, 'La invitación es inválida o ha expirado.')
      clean_up_passwords resource
      set_minimum_password_length
      return respond_with resource
    end

    if invitation.email.present? && !invitation.email.to_s.casecmp?(resource.email.to_s)
      resource.errors.add(:email, 'no coincide con la invitación.')
      clean_up_passwords resource
      set_minimum_password_length
      return respond_with resource
    end

    resource.owner_id = invitation.owner_id
    resource.role = :guest   

    resource.save
    yield resource if block_given?
    if resource.persisted?
      invitation.update!(accepted_at: Time.current)

      if resource.active_for_authentication?
        set_flash_message! :notice, :signed_up
        sign_up(resource_name, resource)
        respond_with resource, location: after_sign_up_path_for(resource)
      else
        set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
        expire_data_after_sign_in!
        respond_with resource, location: after_inactive_sign_up_path_for(resource)
      end
    else
      clean_up_passwords resource
      set_minimum_password_length
      respond_with resource
    end
  end
end