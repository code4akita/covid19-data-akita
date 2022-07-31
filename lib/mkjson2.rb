require 'open-uri'
require 'json'
require 'nokogiri'
require 'dotenv'
require 'aws-sdk'
require 'rubyXL'
require 'time'

Dotenv.load

ENTRY_URL = "https://www.pref.akita.lg.jp/pages/archive/66888"
SERVER = "https://www.pref.akita.lg.jp/"

def get_file_url_paths
  doc = Nokogiri::HTML(URI.open(ENTRY_URL))
  urls = doc.search("a").each.select{|e| /\.xls(x)?$/ =~ e["href"]}
  urls.map{|e| e["href"]}
end

def load_data path
  local_path = File.join("/tmp", File.basename(path))
  # ダウンロード済みの同じファイル名があれば更新しないようにしようとしたが、
  # 同じファイル名で更新される場合があるかもしれないので止める
  # return nil if File.exist? local_path

  `curl #{SERVER}#{path} -o #{local_path}` unless File.exist? local_path
  book = RubyXL::Parser.parse local_path
  sheet = book.worksheets.first
  h = { data: {} }
  headers = nil
  sheet.each_with_index do |row, i|
    values = row.cells.map{ |cell| cell&.value }
    case i
    when 0
      headers = Hash[values.zip((0...values.size).to_a)]
    else
      h2 = {}
      headers.each do |k, i|
        next if k == "公表日"
        h2[k] = values[i]
      end
      h[:data][values[headers["公表日"]].new_offset('+09:00') - Rational("9/24")] = h2
    end
  end
  h[:updated_at] = Time.now.iso8601
  h
end

def load_and_store_all_data paths
  paths.each do |path|
    case path
    when /保健所別/
      h = load_data path
      stoe_to_s3("akita_covid19_by_health_center.json", h) if h
    when /年代別/
      h = load_data path
      stoe_to_s3("akita_covid19_by_age.json", h) if h
    end
  end
end

def stoe_to_s3 filename, h
  Dotenv.load

  Aws.config.update(
    :access_key_id => ENV['AWS_ACCESS_KEY_ID'],
    :secret_access_key => ENV['AWS_SECRET_ACCESS_KEY'])

  s3 = Aws::S3::Resource.new(region: ENV['AWS_BUCKET_REGION'])
  bucket = s3.bucket(ENV['AWS_BUCKET'])

  o = bucket.object(filename)
  o.put(body: JSON.pretty_generate(h), content_type:"application/json; charset=utf-8")
end

def mkjson_from_excel
  paths = get_file_url_paths
  load_and_store_all_data paths
end

if $0 == __FILE__
  mkjson_from_excel
end