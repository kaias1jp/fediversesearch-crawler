require 'faraday'
class PeerAllWorker < ApplicationController
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: false

  def perform()
    #myip = Socket.ip_address_list.detect{|intf| intf.ipv4_private?}.ip_address
    conn2 = Faraday.new(ENV["SERVER_URL"]) do |builder|
      builder.request  :json             # form-encode POST params
      builder.adapter  Faraday.default_adapter  # make requests with Net::HTTP
      builder.options[:open_timeout] = 300 # コネクションを開くまでに待つ最大秒数
      builder.options[:timeout] = 300      # データ読み込みまでに待つ最大秒数
      builder.token_auth ENV["SERVER_TOKEN"]
    end
    res = conn2.get "/api/v1/all_sites"
    hash = JSON.parse(res.body)
    hash["data"].each{|value|
      begin
        if (value["dns_status"] == nil || value["dns_status"] == "" || (value["dns_status"] == "NOERROR" && value["http_status"] == 200)) then
          PeerWorker.perform_async(value["uri"])
        end
      rescue
      end
    }
  end
end
