class ConversationSnapshotJob < ApplicationJob
  queue_as :default

  def perform(risk_assistant_id:, thread_id:, last_user_message:, last_assistant_message:)
    risk_assistant = RiskAssistant.find(risk_assistant_id)

    # Reconstruct the context needed for normalization
    # Note: We fetch the messages again to ensure we have the latest state, 
    # capturing the conversation context.
    
    # We can reuse the logic from the controller or duplicate/refactor it here.
    # To keep it simple and robust, we'll invoke the Normalizer directly here.

    normalized_payload = ConversationNormalizer.call(
      risk_assistant: risk_assistant,
      last_user_message: last_user_message,
      last_assistant_message: last_assistant_message
    )

    # Collect messages for the dump
    # We can replicate the collect_messages_for_context logic here
    messages_dump = risk_assistant.messages.order(:created_at).pluck(:role, :content).map do |role, content|
      { role: role, content: content }
    end

    ConversationSnapshot.create!(
      risk_assistant: risk_assistant,
      thread_id: thread_id,
      last_user_message: last_user_message,
      last_assistant_message: last_assistant_message,
      messages_dump: messages_dump,
      normalized_payload: normalized_payload,
      status: normalized_payload.present? ? "normalized" : "captured"
    )
  rescue => e
    Rails.logger.error "ConversationSnapshotJob error: #{e.class} – #{e.message}"
  end
end
