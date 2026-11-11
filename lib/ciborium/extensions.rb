# frozen_string_literal: true
# rbs_inline: enabled

module Ciborium
  # Tag handling beyond Tagged, enabled per call through the extensions: option.
  #
  # An extension is any object that responds to:
  #
  # - tags: the tag numbers it decodes
  # - classes: the classes whose instances it encodes
  # - decode(tag, value): the object for a tag's decoded content
  # - encode(object): an object to encode in place of object, typically a Tagged
  #
  # Symbols name the built-in extensions.
  module Extensions
    BUILTIN = {
      bignum: "BigInteger",
      time: "Time",
      uri: "URI",
      regexp: "Regexp",
    }.freeze #: Hash[Symbol, String]

    # Resolves Symbols to the built-in extensions and checks every entry is an extension.
    #
    #: (untyped extensions) -> Array[_Extension]
    def self.resolve(extensions)
      unless extensions.is_a?(Array)
        raise ArgumentError, "extensions must be an Array, got #{extensions.inspect}"
      end

      extensions.map do |extension|
        next builtin(extension) if extension.is_a?(Symbol)

        unless [:tags, :classes, :decode, :encode].all? { |m| extension.respond_to?(m) }
          raise ArgumentError, "#{extension.inspect} does not implement tags, classes, decode and encode"
        end

        extension
      end
    end

    # Maps each tag to a callable that wraps the extension's failures in ExtensionError.
    #
    #: (Array[_Extension] extensions) -> Hash[Integer, ^(Integer, untyped) -> untyped]?
    def self.tag_handlers(extensions)
      return if extensions.empty?

      handlers = {} #: Hash[Integer, ^(Integer, untyped) -> untyped]
      extensions.each do |extension|
        extension.tags.each do |tag|
          raise ArgumentError, "more than one extension decodes tag #{tag}" if handlers.key?(tag)

          handlers[tag] = ->(t, value) do
            extension.decode(t, value)
          rescue StandardError
            raise ExtensionError, "#{extension.inspect} failed to decode tag #{t}"
          end
        end
      end
      handlers.freeze
    end

    # Pairs each class with a callable that wraps the extension's failures in EncodeError.
    #
    #: (Array[_Extension] extensions) -> Array[[Module, ^(untyped) -> untyped]]?
    def self.class_handlers(extensions)
      return if extensions.empty?

      extensions.flat_map do |extension|
        handler = ->(object) do
          extension.encode(object)
        rescue StandardError
          raise EncodeError, "#{extension.inspect} failed to encode an instance of #{object.class}"
        end
        extension.classes.map do |klass|
          raise ArgumentError, "#{extension.inspect} lists #{klass.inspect}, which is not a Module" unless klass.is_a?(Module)

          [klass, handler] #: [Module, ^(untyped) -> untyped]
        end
      end.freeze
    end

    #: (Symbol name) -> _Extension
    private_class_method def self.builtin(name)
      class_name = BUILTIN.fetch(name) do
        raise ArgumentError, "unknown extension #{name.inspect}; built-in ones are #{BUILTIN.keys.inspect}"
      end
      require_relative "extensions/#{name}"
      const_get(class_name).new
    end
  end
end
