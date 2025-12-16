text = "✅ El campo ##metadata_redactores_informe.telefono## es &&null&&."
regex = /##(?<field_id>[^#()]+?)(?:\s*\((?<item_label>[^)]+)\))?##.*?&&\s*(?<value>.*?)\s*&&/m

scan_result = text.scan(regex)
puts "Scan result: #{scan_result.inspect}"

if scan_result.any?
  puts "Match found!"
else
  puts "No match."
end
