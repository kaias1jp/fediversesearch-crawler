require 'faraday'
class CrawlAllWorker < ApplicationController
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: false

  def perform()
    #myip = Socket.ip_address_list.detect{|intf| intf.ipv4_private?}.ip_address
    conn2 = Faraday.new(ENV["SERVER_URL"]) do |builder|
      builder.request  :json             # form-encode POST params
      builder.adapter  Faraday.default_adapter  # make requests with Net::HTTP
      builder.options[:open_timeout] = 3000 # コネクションを開くまでに待つ最大秒数
      builder.options[:timeout] = 3000      # データ読み込みまでに待つ最大秒数
      builder.token_auth ENV["SERVER_TOKEN"]
    end
    res = conn2.get "/api/v1/all_sites"
    hash = JSON.parse(res.body)
    hash["data"].each{|value|
      if (value["uri"] != nil && value["uri"] != "") then
        begin
          CrawlWorker.perform_async(value["uri"])
        rescue
        end
      end
    }
  end
end
