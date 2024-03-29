require 'open-uri'
require 'json'
require 'nokogiri'
require 'dotenv'
require 'aws-sdk'
require 'dotenv'

# ローカルで確認する場合にtrueにする。
# その際S3にアップロードしない
LOCAL_CHECK = false

Dotenv.load

def notify_error error
  puts error
  return unless LOCAL_CHECK == false

  mentions = (ENV['TWITTER_IDS'] || "").split(",").map{|id| "@#{id}"}.join(" ")
  cmd = "curl -X POST -H \"Content-Type: application/json\" -d '{\"value1\":\"#{mentions} #{error}\"}' https://maker.ifttt.com/trigger/COVID19DataAkitaNotification/with/key/#{ENV['IFTTT_WEB_HOOK_KEY']}"
  puts `#{cmd}`
end


def mkjson

  #==========================================
  # 感染者の概要を取得

  # 追加になったページは下から2行目に追加する
  urls = %w(
    https://www.pref.akita.lg.jp/pages/archive/57443
    https://www.pref.akita.lg.jp/pages/archive/57444
    https://www.pref.akita.lg.jp/pages/archive/57552
    https://www.pref.akita.lg.jp/pages/archive/58645
    https://www.pref.akita.lg.jp/pages/archive/59331
    https://www.pref.akita.lg.jp/pages/archive/59729
    https://www.pref.akita.lg.jp/pages/archive/59894
    https://www.pref.akita.lg.jp/pages/archive/60163
    https://www.pref.akita.lg.jp/pages/archive/60766
    https://www.pref.akita.lg.jp/pages/archive/62329
    https://www.pref.akita.lg.jp/pages/archive/62530
    https://www.pref.akita.lg.jp/pages/archive/62540
    https://www.pref.akita.lg.jp/pages/archive/62645

    https://www.pref.akita.lg.jp/pages/archive/47957
  )

  index = nil
  from = nil
  to = nil
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
          l = l.chomp!.strip
          case l
          when "", "<hr>"
            next
          when /^.?\d+例\s*目/
            # from例目からto例目までの形式の場合、件数分のコピーを作る
            if to
              ((from + 1)..to).each do |i|
                h = info['感染者の概要']['context'].last.dup
                h['県内症例'] = i
                info['感染者の概要']['context'] << h
              end
            end
            info['感染者の概要']['context'] << {}
            from, to = l.scan(/\d+/).map(&:to_i)
            index = 0
          end
          next unless index

          key = keys[index]
          next unless key

          e = info['感染者の概要']['context'].last
          case key
          when '県内症例'
            e[key] = (l.scan(/\d+/).first || 0).to_i
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
  md = [1,1]
  info['感染者の概要']['context'].each do |e|
    a = (e['陽性確認日'] || "").scan(/\d+/).map(&:to_i)
    m, d = begin
      case a.size
      when 2
        md = a[0, 2]
      when 3
        md = a[1, 2]
      end
      md
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
          v = values[i].scan(/(\d+)人?/).first.first.to_i
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
  indexes = nil

  urls.each do |url|
    doc = Nokogiri::HTML(URI.open(url))
    doc.search(".c-table--full").reverse.each do |div|
      if div.inner_text.include?("うち陽性件数")
        div.search("tr").each do |tr|
          t = tr.inner_text
          case t
          when /期間/
            keys = tr.search("th").map{|e| e.inner_text.gsub(/(\r|\n)/, "")}
            indexes = [
              keys.index("期間"),
              keys.index("PCR検査実施件数") || keys.index("検査件数（総件数）（c）"),
              keys.index("うち陽性件数") || keys.index("うち陽性件数（d）"),
            ]
          when /内訳はこちら/, /合計/
            # スキップ
          else
            # データピックアップ
            a = tr.search("td").map{|e| e.inner_text.gsub(/(\r|\n)/, "")}
            info['検査実施件数の推移']['context'] << {
              "期間" => a[indexes[0]],
              "PCR検査実施件数" => a[indexes[1]].scan(/\d/).join('').to_i,
              "うち陽性件数" => a[indexes[2]].scan(/\d/).join('').to_i,
            }
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
    when 5
      if /^令和/ =~ e['期間']
        a[0] = 2020 + a[0] - 2 if a[0] < 2020   # 令和から西暦に変換
      else
        a.delete_at(2)
        a.unshift year
      end
    when 6
      a[0] = 2020 + a[0] - 2 if a[0] < 2020   # 令和から西暦に変換
      a.delete_at(3)
    when 4
      a.unshift year
    end
    year += 1 if month && a[1] < month
    month = a[1]
    e['期間'] = "#{a[0]}年#{a[1]}月#{a[2]}日～#{a[3]}月#{a[4]}日"
  end

  if LOCAL_CHECK
    puts JSON.pretty_generate(info)
  end

  # check data
  a = info['感染者の概要']['context'].map{|e| e["県内症例"]}.sort.uniq
  unless a.max == a.size
    oversight = a.map.with_index{|e, i| [e, e - (a[i - 1] || 0) - 1]}.select{|a| a.last > 0}
    message = oversight.map{|a| "#{a.first - a.last}から#{a.first - 1}例目の#{a.last}件が抜け落ちています。"}.join("")
    c = oversight.inject(0){|s, a| s + a.last}
    message += "概要の数が#{(a.max - a.size).abs}件合いません。" if c != a.max - a.size
    #message += " https://bit.ly/3rEizN6"
    err = a.max < info['現在の入退院者数等']['context']['感染者数累計']
    message = (err ? "異常: " : "警告: ") + message
    notify_error message
    exit 1 if err
  end

  if LOCAL_CHECK
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