require 'open-uri'
require 'json'
require 'nokogiri'
require 'dotenv'
require 'aws-sdk'

# ローカルで確認する場合にtrueにする。
# その際S3にアップロードしない
LOCAL_CHECK = false

Dotenv.load

def notify_error error
  puts error
  cmd = "curl -X POST -H \"Content-Type: application/json\" -d '{\"value1\":\"#{error}\"}' https://maker.ifttt.com/trigger/COVID19DataAkitaNotification/with/key/#{ENV['IFTTT_WEB_HOOK_KEY']}"
  puts `#{cmd}`
end


def mkjson

  #==========================================
  # 感染者の概要を取得

  urls = %w(
              https://www.pref.akita.lg.jp/pages/archive/54750
              https://www.pref.akita.lg.jp/pages/archive/55157
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
    doc.search(".c-table--full").each do |table|
      if table.search("caption").inner_text.include?("概要")
        table.inner_text.each_line do |l|
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
    end
  end

  info['感染者の概要']['context'].sort!{|a,b| a['県内症例'] <=> b['県内症例']}
  # 陽性確認日の年を付加
  year = 2020
  month = nil
  info['感染者の概要']['context'].each do |e|
    a = e['陽性確認日'].scan(/\d+/).map(&:to_i)
    m, d = begin
      case a.size
      when 2
        a[0, 2]
      when 3
        a[1, 2]
      else
        [1, 1]
      end
    end

    year += 1 if month && m < month
    month = m
    e['陽性確認日'] = "#{year}年#{m}月#{d}日"
  end

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

  index = nil
  keys = %w(感染者数累計 入院者数 うち重症者数 宿泊療養者数 退院者・療養解除者数 死亡者数 現在の感染者数 自宅療養者数 入院等調整中)

  doc = Nokogiri::HTML(URI.open(url))
  doc.search(".c-table--full").reverse.each do |table|
    case table.search("caption").inner_text
    when /県内感染者の状況/, /現在の感染者の内訳/

      trs = table.search("tr")
      headers = trs[0].search("th").map{|td| td.inner_text.chomp }
      values = trs[1].search("td").map{|td| td.inner_text.chomp }

      headers.each_with_index do |title, i|
        
        # 必要があればキーの置換
        case title
        when /入院者数のうち重症者数/
          title = 'うち重症者数'
        when /計/
          title = '感染者数累計'
        end

        # 人数を記録
        if keys.include?(title)
          v = values[i].scan(/(\d+)人/).first.first.to_i
          info['現在の入退院者数等']['context'][title] = v
        end

      end
    end
  end

  #==========================================
  # 検査実施件数の推移を取得

  urls = %w(
    https://www.pref.akita.lg.jp/pages/archive/51592
    https://www.pref.akita.lg.jp/pages/archive/54031
  )

  info['検査実施件数の推移'] = {
    'url' => urls.last,
    'urls' => urls,
    'context' => [],
    'updated_at' => now,
  }
  
  index = nil
  keys = %w(期間 PCR検査実施件数 うち陽性件数)

  urls.each do |url|
    doc = Nokogiri::HTML(URI.open(url))
    doc.search(".c-table--full").reverse.each do |div|
      if div.inner_text.include?("検査実施件数の推移")
        div.inner_text.each_line do |l|
          l.chomp!
          case l
          when ""
          when /内訳はこちら/ # 別ページに詳細があるので含めない
            index = nil
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
                  info['検査実施件数の推移']['context'].last[key] = l.gsub(/,/, '').to_i  # gsubは数値がカンマ区切りなので
                else
                  info['検査実施件数の推移']['context'].last[key] = l
                end
                index = (index + 1) % 3
              end
            end
          end
        end
        break
      end
    end
  end

  # 期間の年を付加
  year = 2020
  month = nil
  info['検査実施件数の推移']['context'].reverse.each do |e|
    a = e['期間'].scan(/[0-9０-９]+/).to_a.map(&:to_i)
    case a.size
    when 5, 6
      a[0] = 2020 + a[0] - 2 if a[0] < 2020   # 令和から西暦に変換
      a.delete_at(3) if a.size == 6
    when 4
      a.unshift year
    end
    year += 1 if month && a[1] < month
    month = a[1]
    e['期間'] = "#{a[0]}年#{a[1]}月#{a[2]}日～#{a[3]}月#{a[4]}日"
  end

  # check data
  a = info['感染者の概要']['context'].map{|e| e["県内症例"]}.sort
  unless a.max == a.size
    notify_error "'感染者の概要'の数が合いません"
    exit 1
  end
 
  if LOCAL_CHECK
    puts JSON.pretty_generate(info)
    exit 1
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