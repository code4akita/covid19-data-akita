$:.unshift File.expand_path(File.join(File.dirname(__FILE__), 'lib'))

require 'sinatra'
require 'mkjson'

get '/' do
  'hello'
end

put '/update' do
  mkjson
  'updated'
end
