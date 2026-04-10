# frozen_string_literal: true

module GrapeSwagger
  module Jsonapi
    class Parser
      RELATIONSHIP_DEFAULT_ITEM = {
        type: :object,
        properties: {
          id: { type: :string },
          type: { type: :string }
        }
      }.freeze

      attr_reader :model, :endpoint

      def initialize(model, endpoint)
        @model = model
        @endpoint = endpoint
      end

      def call
        schema = default_schema
        schema = enrich_with_attributes(schema)
        schema = enrich_with_relationships(schema)
        schema.deep_merge!(model.additional_schema) if model.respond_to?(:additional_schema)

        schema
      end

      private

      def default_schema
        { data: {
          type: :object,
          properties: default_schema_properties,
          example: {
            id: uuid_example,
            type: model.record_type,
            attributes: {},
            relationships: {}
          }
        } }
      end

      def default_schema_properties
        { id: { type: :string },
          type: { type: :string },
          attributes: default_schema_object,
          relationships: default_schema_object }
      end

      def default_schema_object
        { type: :object, properties: {} }
      end

      def enrich_with_attributes(schema)
        attributes_schema = schema[:data][:properties][:attributes]
        attributes_properties = attributes_schema[:properties]
        attributes_examples = schema[:data][:example][:attributes]

        attributes_hash.each do |attribute, type_hash|
          normalized_metadata = normalize_attribute_metadata(type_hash)
          type = normalize_type(normalized_metadata[:type])

          attribute_schema = { type:, example: normalized_metadata[:example] }
          attribute_schema[:description] = normalized_metadata[:description] if normalized_metadata[:description]
          attribute_schema[:desc] = normalized_metadata[:desc] if normalized_metadata[:desc]
          attribute_schema[:enum] = normalized_metadata[:enum] if normalized_metadata[:enum]
          attribute_schema[:items] = normalized_metadata[:items] || { type: :object } if type == :array

          attributes_properties[attribute] = attribute_schema
          attributes_examples[attribute] = normalized_metadata[:example]
          append_required_attribute(attributes_schema, attribute) if normalized_metadata[:required]
        end

        schema
      end

      def attributes_hash
        return map_model_attributes.symbolize_keys unless defined?(ActiveRecord)

        map_model_attributes.symbolize_keys.merge(
          map_active_record_columns_to_attributes.symbolize_keys
        )
      end

      def enrich_with_relationships(schema)
        relationships_hash.each do |model_type, relationship_data|
          relationships_attributes = relationship_data.instance_values.symbolize_keys
          schema[:data][:properties][:relationships][:properties][model_type] = {
            type: :object,
            properties: relationships_properties(relationships_attributes)
          }
          schema[:data][:example][:relationships][model_type] = relationships_example(relationships_attributes)
        end

        schema
      end

      def relationships_hash
        hash = model.relationships_to_serialize || []

        # If relationship has :key set different than association name, it should be rendered under that key

        hash.each_with_object({}) do |(_relationship_name, relationship), accu|
          accu[relationship.key] = relationship
        end
      end

      def map_active_record_columns_to_attributes
        return map_model_attributes unless activerecord_model && activerecord_model < ActiveRecord::Base

        activerecord_model.columns.each_with_object({}) do |column, attributes|
          next unless model.attributes_to_serialize.key?(column.name.to_sym)

          documentation = model.attributes_to_serialize[column.name.to_sym]&.documentation
          attributes[column.name] = normalize_documentation(documentation, fallback_type: column.type)
        end
      end

      def activerecord_model
        model.record_type.to_s.singularize.camelize.safe_constantize
      end

      def map_model_attributes
        attributes = {}
        (model.attributes_to_serialize || []).each do |attribute, options|
          attributes[attribute] = normalize_documentation(options.documentation, fallback_type: :string)
        end
        attributes
      end

      def normalize_documentation(documentation, fallback_type:)
        normalized = (documentation || {}).dup
        type = normalized[:type] || fallback_type
        values = normalized[:values] || normalized[:enum]

        normalized[:type] ||= type
        normalized[:example] ||= example_for_type(type)
        normalized[:enum] ||= values if values
        normalized
      end

      def normalize_attribute_metadata(type_hash)
        type = normalize_type(type_hash[:type])
        {
          type:,
          example: type_hash[:example] || example_for_type(type),
          enum: type_hash[:enum] || type_hash[:values],
          description: type_hash[:description] || type_hash[:desc],
          desc: type_hash[:desc],
          items: type_hash[:items],
          required: !!type_hash[:required]
        }
      end

      def append_required_attribute(attributes_schema, attribute)
        attributes_schema[:required] ||= []
        attributes_schema[:required] << attribute
      end

      def normalize_type(type)
        normalized = type.to_s.strip.downcase
        return :string if normalized.empty?

        normalized.to_sym
      end

      def example_for_type(type)
        method_name = "#{normalize_type(type)}_example"
        return send(method_name) if respond_to?(method_name, true)

        string_example
      end

      def relationships_properties(relationship_data)
        return { data: RELATIONSHIP_DEFAULT_ITEM } unless relationship_data[:relationship_type] == :has_many

        { data: {
          type: :array,
          items: RELATIONSHIP_DEFAULT_ITEM
        } }
      end

      def relationships_example(relationship_data)
        data = {
          id: uuid_example,
          type: relationship_data[:record_type] ||
                relationship_data[:static_record_type] ||
                relationship_data[:object_method_name]
        }

        data = [data] if relationship_data[:relationship_type] == :has_many

        { data: }
      end

      def integer_example
        1
      end

      def string_example
        'Example string'
      end

      def text_example
        'Example text'
      end
      alias citext_example text_example

      def float_example
        (10..100).to_a.sample.to_f
      end

      def date_example
        Date.today.iso8601
      end

      def datetime_example
        Time.current.iso8601
      end
      alias time_example datetime_example

      def object_example
        return { example: :object } unless defined?(Faker)

        { string_example.parameterize.underscore.to_sym => string_example.parameterize.underscore.to_sym }
      end

      def array_example
        [string_example]
      end

      def boolean_example
        [true, false].sample
      end

      def uuid_example
        SecureRandom.uuid_v7
      end
    end
  end
end
