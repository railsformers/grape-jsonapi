# frozen_string_literal: true

describe GrapeSwagger::Jsonapi::Parser do
  let(:model) { BlogPostSerializer }
  let(:endpoint) { '/' }

  describe 'attr_readers' do
    subject { described_class.new(model, endpoint) }

    it { expect(subject.model).to eq model }
    it { expect(subject.endpoint).to eq endpoint }
  end

  describe 'instance methods' do
    describe '#call' do
      subject { described_class.new(model, endpoint).call }
      before { allow(SecureRandom).to receive(:uuid_v7).and_return 'fakeuuid' }

      it 'return a hash defining the schema' do
        expect(subject).to eq({
          data: {
            type: :object,
            properties: {
              id: { type: :string },
              type: { type: :string },
              attributes: {
                type: :object,
                properties: {
                  title: { type: :string, example: 'Example string' },
                  body: { type: :string, example: 'Example string' }
                }
              },
              relationships: {
                type: :object,
                properties: {
                  user: {
                    type: :object,
                    properties: {
                      data: {
                        type: :object,
                        properties: {
                          id: { type: :string },
                          type: { type: :string }
                        }
                      }
                    }
                  }
                }
              }
            },
            example: {
              id: 'fakeuuid',
              type: :blog_post,
              attributes: {
                title: 'Example string',
                body: 'Example string'
              },
              relationships: {
                user: {
                  data: {
                    id: 'fakeuuid',
                    type: :user
                  }
                }
              }
            }
          }
        })
      end

      context 'when the serializer contains sensitive information' do
        let(:model) { UserSerializer } # contains :password attribute

        it 'return a hash defining the schema filtering the sensitive attributes' do
          expect(subject[:data][:properties]).to include(
            id: { type: :string },
            type: { type: :string },
            attributes: {
              type: :object,
              properties: {
                first_name: { type: :string, example: 'Example string' },
                last_name: { type: :string, example: 'Example string' },
                email: { type: :string, example: 'Example string' }
              }
            },
            relationships: {
              type: :object,
              properties: {
                blog_posts: {
                  type: :object,
                  properties: {
                    data: {
                      type: :array,
                      items: {
                        type: :object,
                        properties: {
                          id: { type: :string },
                          type: { type: :string }
                        }
                      }
                    }
                  }
                }
              }
            }
          )

          expect(subject[:data][:example][:id]).to eq('fakeuuid')
          expect(subject[:data][:example][:attributes]).to eq(
            first_name: 'Example string',
            last_name: 'Example string',
            email: 'Example string'
          )
          expect(subject[:data][:example][:relationships][:blog_posts][:data].first[:id]).to eq('fakeuuid')
          expect(%i[blog_post blog_posts]).to include(
            subject[:data][:example][:relationships][:blog_posts][:data].first[:type]
          )
        end
      end

      context 'when schema has an association with :key different than association name' do
        let(:model) { FooSerializer }

        it 'includes associations as defined by :key attributes' do
          expect(subject[:data][:properties][:relationships][:properties]).to include(:foo_bar, :foo_fizz, :foo_buzzes)
        end
      end

      context 'when serializer has additional schema specified' do
        let(:model) { FooSerializer }

        it 'is deep-merged into the returned schema' do
          expect(subject[:data][:example][:attributes]).to include(xyz: 'foobar')
        end
      end

      context 'when serializer has DB-backed model' do
        let(:model) { DbRecordSerializer }

        it 'contains examples for corresponding data types' do
          expect(subject[:data][:example][:attributes]).to include(
            string_attribute: be_a(String),
            uuid_attribute: 'fakeuuid',
            integer_attribute: be_a(Integer),
            text_attribute: be_a(String),
            datetime_attribute: satisfy { |val| Time.parse(val).is_a? Time },
            date_attribute: satisfy { |val| Date.parse(val).is_a? Date },
            boolean_attribute: be_a(TrueClass).or(be_a(FalseClass)),
            array_attribute: be_a(Array)
          )
        end
      end

      context 'when the serializer doesn\'t have any attributes' do
        let(:model) { AnotherBlogPostSerializer } # no attributes

        it 'return a hash defining the schema with empty attributes' do
          expect(subject).to eq({
            data: {
              type: :object,
              properties: {
                id: { type: :string },
                type: { type: :string },
                attributes: {
                  type: :object,
                  properties: {}
                },
                relationships: {
                  type: :object,
                  properties: {
                    user: {
                      properties: {
                        data: {
                          properties: {
                            id: { type: :string },
                            type: { type: :string }
                          },
                          type: :object
                        }
                      },
                      type: :object
                    }
                  }
                }
              },
              example: {
                id: 'fakeuuid',
                type: :blog_post,
                attributes: {
                },
                relationships: {
                  user: {
                    data: { id: 'fakeuuid', type: :user }
                  }
                }
              }
            }
          })
        end
      end

      context 'when serializer attributes use documentation metadata' do
        let(:model) { DocumentedCountrySerializer }

        it 'parses type, desc, example and required' do
          name = subject[:data][:properties][:attributes][:properties][:name]

          expect(name).to include(
            type: :string,
            description: 'localized country name',
            desc: 'localized country name',
            example: 'Local Name'
          )
          expect(subject[:data][:properties][:attributes][:required]).to include(:name)
          expect(subject[:data][:example][:attributes][:name]).to eq('Local Name')
        end

        it 'falls back to a string example for unknown types' do
          nickname_schema = subject[:data][:properties][:attributes][:properties][:nickname]

          expect(nickname_schema[:type]).to eq(:mystery_type)
          expect(nickname_schema[:example]).to eq('Example string')
        end
      end
    end
  end
end
