require 'mkjson'

namespace :update do
  desc "Update data as json"

  task :json do
    mkjson
  end
end
