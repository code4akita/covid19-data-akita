require 'open-uri'
require 'json'
require 'nokogiri'
require 'dotenv'
require 'aws-sdk'

def mkjson

  #==========================================
  # 感染者の概要を取得

  urls = %w(
              https://www.pref.akita.lg.jp/pages/archive/53190
              https://www.pref.akita.lg.jp/pages/archive/47957
          )

  index = nil
  keys = %w(県内症例 陽性確認日 年齢 性別 居住地 職業 濃厚接触者等に関する調査 備考)

  info = {}

  now = Time.now

  info['感染者の概要'] = {
    'url' => urls.last,
    'urls' => urls,
    'context' => [],
    'daily_total' => {},
    'updated_at' => now,
  }


  urls.each do |url|
    doc = Nokogiri::HTML(URI.open(url))
    doc.search(".c-table--full")[0].inner_text.each_line do |l|
      l = l.chomp!
      case l
      when "", "<hr>"
        next
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
      else
        e[key] = l
      end
      index += 1
    end
  end
  info['感染者の概要']['context'].sort!{|a,b| a['県内症例'] <=> b['県内症例']}
  info['感染者の概要']['daily_total'] = Hash[info['感染者の概要']['context']
                                          .group_by{|e| e['陽性確認日']}
                                          .map{|k,v| [k, v.size]}]

  #==========================================
  # 現在の入退院者数等を取得

  url = 'https://www.pref.akita.lg.jp/pages/archive/51592'

  info['現在の入退院者数等'] = {
    'url' => url,
    'context' => {},
    'updated_at' => now,
  }

  doc = Nokogiri::HTML(URI.open(url))

  index = nil
  keys = %w(感染者数累計 入院者数 うち重症者数 宿泊療養者数 退院者・療養解除者数 死亡者数)
  doc.inner_text.each_line do |l|
    case l
    when /死亡者数/
      index = 0
    when /(\d+)人/
      if index
        key = keys[index]
        if key
          info['現在の入退院者数等']['context'][key] = $1.to_i
          index += 1
        end
      end
    end
  end

  #==========================================
  # 検査実施件数の推移を取得

  info['検査実施件数の推移'] = {
    'url' => url,
    'context' => [],
    'updated_at' => now,
  }

  index = nil
  keys = %w(期間 PCR検査実施件数 うち陽性件数)
  doc.search(".c-table--full")[1].inner_text.each_line do |l|
    l.chomp!
    case l
    when ""
    when /うち陽性件数/
      index = 0
    when /合計/
      index = nil
    else
      if index
        key = keys[index]
        if key
          info['検査実施件数の推移']['context'] << {} if index == 0
          case key
          when "PCR検査実施件数", "うち陽性件数"
            info['検査実施件数の推移']['context'].last[key] = l.to_i
          else
            info['検査実施件数の推移']['context'].last[key] = l
          end
          index = (index + 1) % 3
        end
      end
    end
  end


  #==========================================
  # S3にアップロード

  Dotenv.load

  Aws.config.update(
    :access_key_id => ENV['AWS_ACCESS_KEY_ID'],
    :secret_access_key => ENV['AWS_SECRET_ACCESS_KEY'])

  s3 = Aws::S3::Resource.new(region: ENV['AWS_BUCKET_REGION'])
  bucket = s3.bucket(ENV['AWS_BUCKET'])

  o = bucket.object("#{now.year}/#{now.month.to_s.rjust(2,'0')}/#{now.day.to_s.rjust(2,'0')}.json")
  o.put(body: JSON.pretty_generate(info), content_type:"application/json; charset=utf-8")

  # 最新のデータとしてcurrent.jsonにコピーする
  o.copy_to bucket.object("current.json")

  #==========================================
end