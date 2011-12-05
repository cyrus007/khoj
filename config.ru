require 'rubygems'
require 'rack/cache'
require 'bundler'

Bundler.require

use Rack::Cache,
  :verbose          => true,
  :allow_reload     => false,
  :allow_revalidate => false

require './numi'
run Sinatra::Application
