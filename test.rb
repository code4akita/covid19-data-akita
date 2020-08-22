require 'open-uri'
require 'json'
require 'nokogiri'

url = "https://www.pref.akita.lg.jp/pages/archive/47957"

doc = Nokogiri::HTML(URI.open(url))

puts doc.inner_text