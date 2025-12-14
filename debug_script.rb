ra = RiskAssistant.order(:updated_at).last
if ra
  puts "ID: #{ra.id}"
  puts "MsgCount: #{ra.messages.count}"
  puts "ValidMsgCount: #{ra.messages.where.not(key: [nil, ""]).count}"
  puts "Data: #{ra.data.to_json}"
  puts "LastMsg: #{ra.messages.last.inspect}"
else
  puts "No RiskAssistant found."
end
