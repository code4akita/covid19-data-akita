require 'sinatra'
require './mkjson'

get '/' do
  'hello'
end

get '/update' do
  mkjson
  'updated'
end
