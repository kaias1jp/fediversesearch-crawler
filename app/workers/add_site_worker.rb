require 'faraday'
class AddSiteWorker < ApplicationController
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: false

  def perform(uri)
    if uri.include?("@") == true then
      return
    end
    if uri.include?("/") == true then
      return
    end

    #myip = Socket.ip_address_list.detect{|intf| intf.ipv4_private?}.ip_address
    begin
      conn2 = Faraday.new(ENV["SERVER_URL"]) do |builder|
        builder.request  :json             # form-encode POST params
        builder.adapter  Faraday.default_adapter  # make requests with Net::HTTP
        builder.options[:open_timeout] = 10 # コネクションを開くまでに待つ最大秒数
        builder.options[:timeout] = 10      # データ読み込みまでに待つ最大秒数
        builder.token_auth ENV["SERVER_TOKEN"]
      end

      # get sites
      response = conn2.get('/api/v1/sites?uri='+uri)
      hash = JSON.parse(response.body)
      value2 = hash["data"]
      if value2 == nil then
        obj = {"uri" => uri}
        obj["software_id"] = 1
        res = conn2.post("/api/v1/sites", obj.to_json)
      end
    rescue
    end
  end
end
