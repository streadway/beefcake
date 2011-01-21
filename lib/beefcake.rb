require 'beefcake/buffer'

module Beefcake
  module Message

    class InvalidValueError < StandardError
      def initialize(name, val)
        super("Invalid Value given for `#{name}`: #{val.inspect}")
      end
    end

    class RequiredFieldNotSetError < StandardError
      def initialize(name)
        super("Field #{name} is required but nil")
      end
    end

    class Field < Struct.new(:rule, :name, :type, :fn, :opts)
      def <=>(o)
        fn <=> o.fn
      end
    end

    module Dsl
      def required(name, type, fn, opts={})
        field(:required, name, type, fn, opts)
      end

      def repeated(name, type, fn, opts={})
        field(:repeated, name, type, fn, opts)
      end

      def field(rule, name, type, fn, opts)
        fields[fn] = Field.new(rule, name, type, fn, opts)
        attr_accessor name
      end

      def fields
        @fields ||= {}
      end
    end

    def self.included(o)
      o.extend Dsl
    end

    def initialize(attrs={})
      fields.values.each do |fld|
        self[fld.name] = attrs[fld.name]
      end
    end

    def fields
      self.class.fields
    end

    def [](k)
      __send__(k)
    end

    def []=(k, v)
      __send__(k.to_s+"=", v)
    end

    def validate!
      fields.values.each do |fld|
        if fld.rule == :required && self[fld.name].nil?
          raise RequiredFieldNotSetError, fld.name
        end
      end
    end

    def encode(buf = Buffer.new)
      validate!

      if ! buf.respond_to?(:<<)
        raise ArgumentError, "buf doesn't respond to `<<`"
      end

      if ! buf.is_a?(Buffer)
        buf = Buffer.new(buf)
      end

      # TODO: Error if any required fields at nil

      fields.values.sort.each do |fld|
        if fld.opts[:packed]
          bytes = encode!(Buffer.new, fld, 0)
          buf.append_info(Buffer.wire_for(fld.type), fld.fn)
          buf.append_uint64(bytes.length)
          buf << bytes
        else
          encode!(buf, fld, fld.fn)
        end
      end

      buf
    end

    def encode!(buf, fld, fn)
      Array(self[fld.name]).each do |val|
        case fld.type
        when Class # encodable
          # TODO: raise error if type != val.class
            buf.append(:string, val.encode, fn)
        when Module # enum
          if ! valid_enum?(fld.type, val)
            raise InvalidValueError.new(fld.name, val)
          end

          buf.append(:int32, val, fn)
        else
          buf.append(fld.type, val, fn)
        end
      end
      buf
    end

    def valid_enum?(mod, val)
      mod.constants.any? {|name| mod.const_get(name) == val }
    end
  end
end
