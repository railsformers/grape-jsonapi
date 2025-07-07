# frozen_string_literal: true

source 'https://rubygems.org'

git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?("/")
  "https://github.com/#{repo_name}.git"
end

gemspec

gem 'grape'
gem 'jsonapi-serializer', github: 'railsformers/jsonapi-serializer'

group :development do
  gem 'rails', '>= 4.2.0'
  gem 'rspec', '~> 3.7'
  gem 'rubocop'
end
