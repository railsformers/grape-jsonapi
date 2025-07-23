# frozen_string_literal: true

module GrapeSwagger
  module Jsonapi
    class Parser
      RELATIONSHIP_DEFAULT_ITEM = {
        type: :object,
        properties: {
          id: { type: :integer },
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
          properties: default_schema_propeties,
          example: {
            id: 1,
            type: model.record_type,
            attributes: {},
            relationships: {}
          }
        } }
      end

      def default_schema_propeties
        { id: { type: :integer },
          type: { type: :string },
          attributes: default_schema_object,
          relationships: default_schema_object }
      end

      def default_schema_object
        { type: :object, properties: {} }
      end

      def enrich_with_attributes(schema)
        attributes_hash.each do |attribute, type_hash|
          type = type_hash[:type].try(:downcase)
          required = type_hash[:required] || false
          example = type_hash[:example] || send("#{type}_example")
          enum = type_hash[:enum] || nil
          schema[:data][:properties][:attributes][:properties][attribute] = { type:, example: }
          schema[:data][:example][:attributes][attribute] = type_hash[:example]
          schema[:data][:properties][:attributes][:required] ||= []
          schema[:data][:properties][:attributes][:required] << attribute if required
          schema[:data][:properties][:attributes][:properties][attribute][:enum] = enum if enum
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

          documentation = model.attributes_to_serialize[column.name.to_sym]&.documentation || {}
          example = documentation[:example] || send("#{column.type}_example")
          values = documentation[:values] || nil
          attributes[column.name] = documentation
          attributes[column.name][:type] ||= column.type
          attributes[column.name][:example] ||= example
          attributes[column.name][:enum] ||= values if values
        end
      end

      def activerecord_model
        model.record_type.to_s.camelize.safe_constantize
      end

      def map_model_attributes
        attributes = {}
        (model.attributes_to_serialize || []).each do |attribute, options|
          type = options.documentation.dig(:type) || :string
          example = options.documentation.dig(:example) || send("#{type}_example")
          values = options.documentation.dig(:values) || nil

          attributes[attribute] = options.documentation || {}
          attributes[attribute][:type] ||= type
          attributes[attribute][:example] ||= example
          attributes[attribute][:enum] ||= values if values
        end
        attributes
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
          id: 1,
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
        SecureRandom.uuid
      end
    end
  end
end
