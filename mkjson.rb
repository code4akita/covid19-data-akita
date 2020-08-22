require 'open-uri'
require 'json'
require 'nokogiri'

url = "https://www.pref.akita.lg.jp/pages/archive/47957"


index = nil
keys = %w(県内症例 陽性確認日 年齢 性別 居住地 職業 濃厚接触者等に関する調査 備考)

info = {}

now = Time.now

info['感染者の概要'] = {
  'url' => url,
  'context' => [],
  'daily_total' => {},
  'updated_at' => now,
}


doc = Nokogiri::HTML(URI.open(url))
doc.inner_text.each_line do |l|
  case l
  when "\n", "<hr>\n"
    index = nil
  when /^\d+例目/
    info['感染者の概要']['context'] << {}
    index = 0
  end
  next unless index

  key = keys[index]
  next unless key

  e = info['感染者の概要']['context'].last
  case key
  when '県内症例'
    e[key] = l.to_i
    p l if e[key] == 0
  else
    e[key] = l.chomp.gsub(/\r/, "")
  end
  index += 1
end
info['感染者の概要']['context'].sort!{|a,b| a['県内症例'] <=> b['県内症例']}
info['感染者の概要']['daily_total'] = Hash[info['感染者の概要']['context']
                                        .group_by{|e| e['陽性確認日']}
                                        .map{|k,v| [k, v.size]}]

#==========================================

url = 'https://www.pref.akita.lg.jp/pages/archive/51592'

info['現在の入退院者数等'] = {
  'url' => url,
  'context' => {},
  'updated_at' => now,
}

doc = Nokogiri::HTML(URI.open(url))

index = nil
keys = %w(感染者数累計 入院者数 うち重症者数 宿泊療養者数 退院者・療養解除者数 死亡者数)
p keys
doc.inner_text.each_line do |l|
  #puts l
  case l
  when /死亡者数/
    index = 0
  when /(\d+)人/
    if index
      key = keys[index]
      #p key
      if key
        info['現在の入退院者数等']['context'][key] = $1
        index += 1
      end
    end
  end
end


#==========================================

puts JSON.pretty_generate(info)
