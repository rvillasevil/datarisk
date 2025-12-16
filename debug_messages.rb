ra = RiskAssistant.order(:updated_at).last
puts "RA ID: #{ra.id}"
ra.messages.order(:created_at).last(10).each do |m|
  puts "ID: #{m.id} | Role: #{m.role} | Key: #{m.key.inspect} | Content: #{m.content.to_s.truncate(30)}"
end
