m = RiskAssistant.order(:updated_at).last.messages.where(role: 'assistant').last
if m
  puts "CONTENT_START"
  puts m.content
  puts "CONTENT_END"
else
  puts "No assistant message found."
end
