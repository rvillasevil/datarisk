class ClientInvitation < ApplicationRecord
  belongs_to :owner, class_name: 'User'
  belongs_to :user, optional: true

  scope :pending, -> { where(accepted_at: nil) }

  validate :owner_must_be_admin

  private

  def owner_must_be_admin
    errors.add(:owner, 'debe ser el administrador') unless owner&.admin?
  end
end
