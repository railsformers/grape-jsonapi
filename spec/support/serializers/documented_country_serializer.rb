# frozen_string_literal: true

class DocumentedCountrySerializer
  include JSONAPI::Serializer

  attribute :name, documentation: {
    type: 'String',
    desc: 'localized country name',
    example: 'Local Name',
    required: true
  }

  attribute :nickname, documentation: {
    type: 'mystery_type'
  }
end
