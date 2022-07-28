$:.unshift File.expand_path(File.join(File.dirname(__FILE__), 'lib'))

require 'sinatra'
require 'mkjson'
require 'mkjson2'

get '/' do
  'hello'
end

put '/update' do
  mkjson_from_excel
  mkjson
  'updated'
end

put '/notify/test' do
  notify_error "通知テスト"
  'notified'
end
