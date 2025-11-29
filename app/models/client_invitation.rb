class ClientInvitation < ApplicationRecord
  belongs_to :owner, class_name: 'User'

  scope :pending, -> { where(accepted_at: nil) }
end