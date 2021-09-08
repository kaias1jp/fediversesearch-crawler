require 'faraday'
class PeerWorker < ApplicationController
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
    conn = Faraday.new(:url => 'https://'+uri) do |faraday|
        faraday.response :logger                  # log requests to STDOUT
        faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
        faraday.options[:open_timeout] = 10
        faraday.options[:timeout] = 10
        faraday.use FaradayMiddleware::FollowRedirects
        faraday.adapter :net_http
        faraday.request  :url_encoded             # form-encode POST params
    end
    response = conn.get '/api/v1/instance/peers'
    hash = JSON.parse(response.body)

    p uri+" size:"+hash.size.to_s

    if hash.size > Settings.peer[:limit] then
      p "size over "+Settings.peer[:limit].to_s
      return
    end

    hash.each{|value|
      if (value.include?("@") == true || value.include?("/") == true) then
        next
      end

      begin
        conn2 = Faraday.new(ENV["SERVER_URL"]) do |builder|
          builder.request  :json             # form-encode POST params
          builder.adapter  Faraday.default_adapter  # make requests with Net::HTTP
          builder.options[:open_timeout] = 10 # コネクションを開くまでに待つ最大秒数
          builder.options[:timeout] = 10      # データ読み込みまでに待つ最大秒数
          builder.token_auth ENV["SERVER_TOKEN"]
        end

        # get sites
        response = conn2.get('/api/v1/sites?uri='+value)
        hash = JSON.parse(response.body)
        value2 = hash["data"]
        if value2 == nil then
          obj = {"uri" => value}
          obj["software_id"] = 1
          res = conn2.post("/api/v1/sites", obj.to_json)
        end
      rescue
      end
    }
  end
end
