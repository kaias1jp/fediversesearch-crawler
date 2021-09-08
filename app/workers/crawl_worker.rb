require 'faraday'
class CrawlWorker < ApplicationController
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: false

  def perform(uri)
    #myip = Socket.ip_address_list.detect{|intf| intf.ipv4_private?}.ip_address

    conn = Faraday.new(:url => ENV["SERVER_URL"]) do |faraday|
      faraday.response :logger                  # log requests to STDOUT
      faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
      faraday.options[:open_timeout] = 10
      faraday.options[:timeout] = 10
      faraday.token_auth ENV["SERVER_TOKEN"]
    end


    # get softwares
    response = conn.get '/api/v1/softwares'
    hash = JSON.parse(response.body)
    softwares = {}
    for value in hash["data"] do
      softwares[value["name"]]=value["id"]
    end

    obj = {}
    obj["uri"] = uri

    # get sites
    response = conn.get( '/api/v1/sites?uri='+uri)
    hash = JSON.parse(response.body)
    value = hash["data"]
    
#    updated_at = Time.parse(value["updated_at"])
#    today = Time.zone.now
#    difference = (today - updated_at).floor / 3600
#    if difference < 23 then
#      p "not get:"+uri
#      return
#    end

    if (uri.include?("@") == true || uri.include?("/") == true) then
      # uri format error
      p "illegal uri:"+uri
      @obj = {"uri" => ""}
      conn2 = Faraday.new(:url => ENV["SERVER_URL"]) do |builder|
        builder.request  :json             # form-encode POST params
        builder.adapter  Faraday.default_adapter  # make requests with Net::HTTP
        builder.options[:open_timeout] = 10 # コネクションを開くまでに待つ最大秒数
        builder.options[:timeout] = 10      # データ読み込みまでに待つ最大秒数
        builder.token_auth ENV["SERVER_TOKEN"]
      end
      p "id:"+value["id"].to_s
      conn2.headers["Content-Type"] = "application/json"
      res = conn2.put("/api/v1/sites/"+value["id"].to_s, @obj.to_json)
      return
    end

    @obj = {"last_confirmation_date" => Date.today}
    begin
      #DNSチェック
      p "uri:"+value["uri"]
      begin
        address =  Resolv.getaddress(value["uri"])
        p "ip address:"+value["uri"]+":"+address
      rescue
        p "DNSerror"
        @obj["dns_status"] = "ERROR"
        conn2 = Faraday.new(:url => ENV["SERVER_URL"]) do |builder|
          builder.request  :json             # form-encode POST params
          builder.adapter  Faraday.default_adapter  # make requests with Net::HTTP
          builder.options[:open_timeout] = 10 # コネクションを開くまでに待つ最大秒数
          builder.options[:timeout] = 10      # データ読み込みまでに待つ最大秒数
          builder.token_auth ENV["SERVER_TOKEN"]
        end
        p value["id"]
        conn2.headers["Content-Type"] = "application/json"
        res = conn2.put("/api/v1/sites/"+value["id"].to_s, @obj.to_json)
        p res
        return
      end

      # get nodeinfo
      conn3 = Faraday.new(:url => 'https://'+value["uri"]) do |faraday|
        faraday.response :logger                  # log requests to STDOUT
        faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
        faraday.options[:open_timeout] = 10
        faraday.options[:timeout] = 10
        faraday.use FaradayMiddleware::FollowRedirects
        faraday.adapter :net_http
      end
      response = conn3.get '/.well-known/nodeinfo'
      if response.status == 200 then
        if response.headers['content-type'].include?("json") == true then
          hash2 = JSON.parse(response.body)
          uri = URI.parse(hash2["links"][0]["href"])
          p uri.path
          conn2 = Faraday.new(:url => 'https://'+uri.host+":"+uri.port.to_s) do |faraday|
            faraday.response :logger                  # log requests to STDOUT
            faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
            faraday.options[:open_timeout] = 10
            faraday.options[:timeout] = 10
            faraday.use FaradayMiddleware::FollowRedirects
            faraday.adapter :net_http
          end
          response = conn2.get uri.path
          if response.status == 200 then
            if response.headers['content-type'].include?("json") == true then
              hash2 = JSON.parse(response.body)
              software_name = hash2["software"]["name"]
              p software_name
              software_id = softwares[software_name]
              p software_id
              if software_id == nil then
                id = 1
              else
                id = software_id
              end

              conn2 = Faraday.new(:url => ENV["SERVER_URL"]) do |builder|
                builder.request  :json             # form-encode POST params
                builder.adapter  Faraday.default_adapter  # make requests with Net::HTTP
                builder.options[:open_timeout] = 10 # コネクションを開くまでに待つ最大秒数
                builder.options[:timeout] = 10      # データ読み込みまでに待つ最大秒数
                builder.token_auth ENV["SERVER_TOKEN"]
              end
              conn2.headers["Content-Type"] = "application/json"
              obj = {"software_id" => id}
              res = conn2.put("/api/v1/sites/"+value["id"].to_s, obj.to_json)
            end
          end
        end
      end

      # get instance data
      conn4 = Faraday.new(:url => 'https://'+value["uri"]) do |faraday|
        faraday.response :logger                  # log requests to STDOUT
        faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
        faraday.options[:open_timeout] = 10
        faraday.options[:timeout] = 10
        faraday.use FaradayMiddleware::FollowRedirects
        faraday.adapter :net_http
      end
      response2 = conn4.get '/api/v1/instance'
      if response2 == nil then
        p "response is nil"
      end
      p "response not nil"
      p 'status:'+response2.status.to_s
      if response2.status == 200 then
        if response2.headers['content-type'].to_s.include?("json") == true then
          p "json"
          hash2 = JSON.parse(response2.body)
          @obj["title"] = hash2["title"]
          @obj["short_description"] = hash2["short_description"]
          @obj["description"] = hash2["description"]
          @obj["registrations"] = hash2["registrations"]
          @obj["thumbnail"] = hash2["thumbnail"]
          p "kokomade"
          @obj["http_status"] = response2.status
        else 
          @obj["http_status"] = 404
        end 
      elsif response2.status == 400 then
        #もしかしてPeerTube
        conn3 = Faraday.new(:url => 'https://'+value["uri"]) do |faraday|
          faraday.response :logger                  # log requests to STDOUT
          faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
          faraday.options[:open_timeout] = 10
          faraday.options[:timeout] = 10
          faraday.use FaradayMiddleware::FollowRedirects
          faraday.adapter :net_http
        end
        response = conn3.get '/api/v1/config/about'
        if response.status == 200 then
          if response.headers['content-type'].include?("json") == true then
            hash2 = JSON.parse(response.body)
            @obj["title"] = hash2["instance"]["name"]
            @obj["short_description"] = hash2["instance"]["shortDescription"]
            @obj["description"] = hash2["instance"]["description"]
            @obj["http_status"] = response.status

            response = conn3.get '/api/v1/config'
            if response.status == 200 then
              if response.headers['content-type'].include?("json") == true then
                hash2 = JSON.parse(response.body)
                @obj["registrations"] = hash2["signup"]["allowed"]
              end
            end
          else
            @obj["http_status"] = 404
          end 
        else
          @obj["http_status"] = response.status
        end
      elsif response2.status == 404 then
        p 'uri:'+value['uri']
        #もしかしてmisskey
        conn3 = Faraday.new(:url => 'https://'+value["uri"]) do |faraday|
         faraday.response :logger                  # log requests to STDOUT
          faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
          faraday.options[:open_timeout] = 10
          faraday.options[:timeout] = 10
          faraday.use FaradayMiddleware::FollowRedirects
          faraday.adapter :net_http
        end

        conn3.headers["Content-Type"] = "application/json"
        postdata = {"host" => value['uri']}
        response = conn3.post('/api/federation/show-instance', postdata.to_json)

        if response.status == 200 then
          p response.body
          hash2 = JSON.parse(response.body)
          @obj = {"last_confirmation_date" => Date.today}
          @obj["title"] = hash2["name"]
          @obj["description"] = hash2["description"]
          @obj["registrations"] = hash2["openRegistrations"]
          @obj["thumbnail"] = hash2["iconUrl"]
          @obj["http_status"] = response.status
        elsif response.status == 404 then
          misskey_url = ENV["MISSKEY_URL"].split
          conn4 = Faraday.new(:url => misskey_url.sample) do |faraday|
            faraday.response :logger                  # log requests to STDOUT
            faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
            faraday.options[:open_timeout] = 10
            faraday.options[:timeout] = 10
            faraday.use FaradayMiddleware::FollowRedirects
            faraday.adapter :net_http
          end

          conn4.headers["Content-Type"] = "application/json"
          postdata = {"host" => value['uri']}
          response = conn4.post('/api/federation/show-instance', postdata.to_json)

          if response.status == 200 then
            hash2 = JSON.parse(response.body)
            @obj = {"last_confirmation_date" => Date.today}
            @obj["title"] = hash2["name"]
            @obj["description"] = hash2["description"]
            @obj["registrations"] = hash2["openRegistrations"]
            @obj["thumbnail"] = hash2["iconUrl"]
            @obj["http_status"] = response.status
          else
            @obj = {"last_confirmation_date" => Date.today}
            @obj["http_status"] = 404
          end
        else  
          @obj = {"last_confirmation_date" => Date.today}
          @obj["http_status"] = 404
        end
      else
        @obj = {"last_confirmation_date" => Date.today}
        @obj["http_status"] = response.status
      end
      conn2 = Faraday.new(:url => ENV["SERVER_URL"]) do |builder|
        builder.request  :json             # form-encode POST params
        builder.adapter  Faraday.default_adapter  # make requests with Net::HTTP
        builder.options[:open_timeout] = 10 # コネクションを開くまでに待つ最大秒数
        builder.options[:timeout] = 10      # データ読み込みまでに待つ最大秒数
        builder.token_auth ENV["SERVER_TOKEN"]
      end
      conn2.headers["Content-Type"] = "application/json"
      @obj["dns_status"] = "NOERROR"
      res = conn2.put("/api/v1/sites/"+value["id"].to_s, @obj.to_json)
    rescue
    end

    p "dounano"
#    render json: { status: "SUCCESS" }
  end
end

