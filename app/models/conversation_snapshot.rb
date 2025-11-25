class ConversationSnapshot < ApplicationRecord
  belongs_to :risk_assistant

  validates :status, presence: true

  def normalized?
    status == "normalized"
  end
end