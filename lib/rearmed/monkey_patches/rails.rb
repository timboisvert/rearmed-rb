enabled = Rearmed.enabled_patches[:rails] == true

if defined?(ActiveRecord)

  if enabled || Rearmed.dig(Rearmed.enabled_patches, :rails, :pluck_to_hash) == true
    ActiveRecord::Base.class_eval do
      def self.pluck_to_hash(*keys)
        hash_type = keys[-1].is_a?(Hash) ? keys.pop.fetch(:hash_type, HashWithIndifferentAccess) : HashWithIndifferentAccess
        block_given = block_given?
        keys, formatted_keys = format_keys(keys)
        keys_one = keys.size == 1

        pluck(*keys).map do |row|
          value = hash_type[formatted_keys.zip(keys_one ? [row] : row)]
          block_given ? yield(value) : value
        end
      end

      def self.pluck_to_struct(*keys)
        struct_type = keys[-1].is_a?(Hash) ? keys.pop.fetch(:struct_type, Struct) : Struct
        block_given = block_given?
        keys, formatted_keys = format_keys(keys)
        keys_one = keys.size == 1

        struct = struct_type.new(*formatted_keys)
        pluck(*keys).map do |row|
          value = keys_one ? struct.new(*[row]) : struct.new(*row)
          block_given ? yield(value) : value
        end
      end

      private

      def self.format_keys(keys)
        if keys.blank?
          [column_names, column_names]
        else
          [
            keys,
            keys.map do |k|
              case k
              when String
                k.split(/\bas\b/i)[-1].strip.to_sym
              when Symbol
                k
              end
            end
          ]
        end
      end
    end
  end

  ActiveRecord::Batches.module_eval do
    if enabled || Rearmed.dig(Rearmed.enabled_patches, :rails, :find_in_relation_batches) == true
      def find_in_relation_batches(options = {})
        options.assert_valid_keys(:start, :batch_size)

        relation = self
        start = options[:start]
        batch_size = options[:batch_size] || 1000

        unless block_given?
          return to_enum(:find_in_relation_batches, options) do
            total = start ? where(table[primary_key].gteq(start)).size : size
            (total - 1).div(batch_size) + 1
          end
        end

        if logger && (arel.orders.present? || arel.taken.present?)
          logger.warn("Scoped order and limit are ignored, it's forced to be batch order and batch size")
        end

        relation = relation.reorder(batch_order).limit(batch_size)
        #records = start ? relation.where(table[primary_key].gteq(start)).to_a : relation.to_a
        records = start ? relation.where(table[primary_key].gteq(start)) : relation

        while records.any?
          records_size = records.size
          primary_key_offset = records.last.id
          raise "Primary key not included in the custom select clause" unless primary_key_offset

          yield records

          break if records_size < batch_size

          records = relation.where(table[primary_key].gt(primary_key_offset))#.to_a
        end
      end
    end

    if enabled || Rearmed.dig(Rearmed.enabled_patches, :rails, :find_relation_each) == true
      def find_relation_each(options = {})
        if block_given?
          find_in_relation_batches(options) do |records|
            records.each { |record| yield record }
          end
        else
          enum_for :find_relation_each, options do
            options[:start] ? where(table[primary_key].gteq(options[:start])).size : size
          end
        end
      end
    end
  end

end
