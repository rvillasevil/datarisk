class RiskDataSyncService
  # Synchronizes all messages for a RiskAssistant into the structured `data` JSONB column.
  def self.call(risk_assistant)
    new.call(risk_assistant)
  end

  def call(risk_assistant)
    begin
      # Start with an empty hash
      data_map = {}

      # Iterate over all confirmed/valid messages
      # We order by created_at to ensure latest values overwrite if there are duplicates (though keys should be unique)
      msgs = risk_assistant.messages.where.not(key: [nil, ""]).order(:created_at)
      Rails.logger.info "RiskDataSyncService: Syncing #{msgs.count} messages for RA ##{risk_assistant.id}"
      
      msgs.each do |message|
        # Rails.logger.debug "RiskDataSyncService: processing key='#{message.key}' value='#{message.value}'"
        deep_set!(data_map, message.key, message.value)
      end

      Rails.logger.info "RiskDataSyncService: Final data_map keys: #{data_map.keys}"

      # Save to the JSONB column
      risk_assistant.update_column(:data, data_map)
    rescue StandardError => e
      Rails.logger.error "RiskDataSyncService Error: #{e.message}\n#{e.backtrace.join("\n")}"
    end
  end

  private

  # Recursively sets a value in a nested hash structure based on a dot-separated key.
  # Handles numeric segments as array indices.
  # Example: "constr_edificios_detalles_array.0.edif_nombre_uso"
  def deep_set!(hash, key_path, value)
    segments = key_path.split(".")
    current  = hash

    segments.each_with_index do |seg, index|
      is_last = (index == segments.size - 1)

      # Determine if the NEXT segment is an integer => we need an Array here
      # Or if CURRENT segment implies we are inside an array (logic handling below)
      
      if is_last
        # Assign value
        current[seg] = value
      else
        next_seg = segments[index + 1]
        
        # Check if next segment is a number (array index)
        if next_seg =~ /\A\d+\z/
          # Ensure current[seg] is an array of hashes
          current[seg] ||= []
          
          # Now we need to move `current` to that specific index in the array
          # But wait, the standard Ruby iteration is tricky with arrays.
          # Let's simplify: we'll treat arrays as sparsely populated if needed, 
          # but `RiskFieldSet` keys usually guarantee sequential access or valid structure.
          
          # Initialize the array element if missing
          array_index = next_seg.to_i
          current[seg][array_index] ||= {}
          
          # Move pointer to that element
          current = current[seg][array_index]
          
          # Skip the *next* segment in the main loop because we just handled it (the index)
          # We can't easily "skip" in `each_with_index`, so we'll need a different loop approach.
          # OR we handle the index logic here and let the next iteration be a no-op?
          # Easier: parse keys carefully.
        elsif seg =~ /\A\d+\z/
           # Logic handled in previous step (the parent prepared the array element).
           # So if we are HERE, `current` is already the hash at array[index].
           # But `seg` is the number "0". `current["0"]` is wrong if `current` is the element hash.
           # This means my simple iteration is flawed for the "parent lookahead" approach.
           
           # Let's switch to a recursive approach or a better iterative one.
        else
           # Standard object nesting
           # If next is NOT a number, we expect a Hash
           if !(next_seg =~ /\A\d+\z/)
             current[seg] ||= {}
             current = current[seg]
           end
           # If next IS a number, we handled the Array init in the *previous* step? 
           # No, that's confusing.
        end
      end
    end
  end

  # clean implementation
  def deep_set!(hash, key_path, value)
    parts = key_path.split(".")
    leaf  = parts.pop
    
    # Traverse/Build the structure
    cursor = hash
    
    parts.each_with_index do |part, idx|
      next_part = parts[idx + 1] || leaf
      
      # Is next_part an index? -> We need an Array
      if next_part =~ /\A\d+\z/
        cursor[part] ||= []
        
        # Ensure it is an array (in case of conflict, though unlikely with our keys)
        cursor[part] = [] unless cursor[part].is_a?(Array)
        
        cursor = cursor[part]
      
      # Is current part an index? -> We are IN an array, access/create the element
      elsif part =~ /\A\d+\z/
        idx_i = part.to_i
        # Ensure the slot exists and is a Hash
        cursor[idx_i] ||= {}
        # Move cursor to that hash
        cursor = cursor[idx_i]
        
      else
        # Standard object key
        cursor[part] ||= {}
        # Ensure it is a Hash
        cursor[part] = {} unless cursor[part].is_a?(Hash)
        
        cursor = cursor[part]
      end
    end

    # Assign the value at the leaf
    # If leaf is a number? (Should not happen for a value key, but possible)
    if leaf =~ /\A\d+\z/
      cursor[leaf.to_i] = value
    else
      cursor[leaf] = value
    end
  end
end
