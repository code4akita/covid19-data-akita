require 'mkjson'
require 'mkjson2'

namespace :update do
  desc "Update data as json"

  task :json do
    mkjson_from_excel
    mkjson
  end

end

namespace :notify do
  desc "test notify"
  task :test do
    notify_error "通知テスト"
  end
end
