class AssistantRunLog < ApplicationRecord
  belongs_to :risk_assistant

  validates :endpoint, presence: true
end