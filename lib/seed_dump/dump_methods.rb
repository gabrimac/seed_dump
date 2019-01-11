require 'indentation'

class SeedDump
  module DumpMethods
    include Enumeration

    def dump(records, options = {})
      return nil if records.count == 0

      io = open_io(options)

      if options[:migration] && options[:file]
        write_migration_to_io(records, io, options)
      else
        write_records_to_io(records, io, options)
      end

      ensure
        io.close if io.present?
    end

    private

    def write_migration_to_io(records, io, options)
      io.write("class #{File.basename(io.path, File.extname(io.path)).classify} < ActiveRecord::Migration\n")
      io.write("def change\n".indent(2))
      if options[:query]
        io.write("if #{model_for(records)}.where(#{options[:query]}).empty?\n".indent(4))
        options[:indentation] = 6
        write_records_to_io(records, io, options)
        io.write("end\n".indent(4))
      else
        options[:indentation] = 4
        write_records_to_io(records, io, options)
      end
      io.write("end\n".indent(2))
      io.write("end\n")
    end

    def dump_record(record, options)
      attribute_strings = []

      # We select only string attribute names to avoid conflict
      # with the composite_primary_keys gem (it returns composite
      # primary key attribute names as hashes).
      record.attributes.select {|key| key.is_a?(String) || key.is_a?(Symbol) }.each do |attribute, value|
        attribute_strings << dump_attribute_new(attribute, value, options) unless options[:exclude].include?(attribute.to_sym)
      end

      open_character, close_character = options[:import] ? ['[', ']'] : ['{', '}']

      "#{open_character}#{attribute_strings.join(", ")}#{close_character}"
    end

    def dump_attribute_new(attribute, value, options)
      options[:import] ? value_to_s(value) : "#{attribute}: #{value_to_s(value)}"
    end

    def value_to_s(value)
      value = case value
              when BigDecimal, IPAddr
                value.to_s
              when Date, Time, DateTime
                value.to_s(:db)
              when Range
                range_to_string(value)
              when ->(v) { v.class.ancestors.map(&:to_s).include?('RGeo::Feature::Instance') }
                value.to_s
              else
                value
              end

      value.inspect
    end

    def range_to_string(object)
      from = object.begin.respond_to?(:infinite?) && object.begin.infinite? ? '' : object.begin
      to   = object.end.respond_to?(:infinite?) && object.end.infinite? ? '' : object.end
      "[#{from},#{to}#{object.exclude_end? ? ')' : ']'}"
    end

    def open_io(options)
      if options[:file].present?
        mode = options[:append] ? 'a+' : 'w+'

        File.open(options[:file], mode)
      else
        StringIO.new('', 'w+')
      end
    end

    def write_records_to_io(records, io, options)
      options[:exclude] ||= [:id, :created_at, :updated_at]

      method = options[:import] ? 'import' : 'create!'

      io_write(io, "#{model_for(records)}.#{method}(", options)
      if options[:import]
        io_write(io, "[#{attribute_names(records, options).map {|name| name.to_sym.inspect}.join(', ')}], ", options)
      end
      io_write(io, "[\n  ", options)

      enumeration_method = if records.is_a?(ActiveRecord::Relation) || records.is_a?(Class)
                             :active_record_enumeration
                           else
                             :enumerable_enumeration
                           end

      send(enumeration_method, records, io, options) do |record_strings, last_batch|
        io_write(io, record_strings.join(",\n  "), options)

        io_write(io, ",\n  ", options) unless last_batch
      end

      io_write(io, "\n]#{active_record_import_options(options)})\n", options)

      if options[:file].present?
        nil
      else
        io.rewind
        io.read
      end
    end

    def io_write(io, sentence, options)
      if options[:indentation]
        io.write(sentence.indent(options[:indentation]))
      else
        io.write(sentence)
      end
    end

    def active_record_import_options(options)
      return unless options[:import] && options[:import].is_a?(Hash)

      ', ' + options[:import].map { |key, value| "#{key}: #{value}" }.join(', ')
    end

    def attribute_names(records, options)
      attribute_names = if records.is_a?(ActiveRecord::Relation) || records.is_a?(Class)
                          records.attribute_names
                        else
                          records[0].attribute_names
                        end

      attribute_names.select {|name| !options[:exclude].include?(name.to_sym)}
    end

    def model_for(records)
      if records.is_a?(Class)
        records
      elsif records.respond_to?(:model)
        records.model
      else
        records[0].class
      end
    end

  end
end
