begin
  require "oauth"
  require "yaml"
  require "json"
  require "net/https"
  require "uri"
  require "logger"
  require "thread"
rescue LoadError
  require "rubygems"
  retry
end

consumer = OAuth::Consumer.new(
  "Q0iCmmhk1VjkWyUc88AA",
  "3pGXwnsltDk00FEiF7mEnSWMc6gHBNYtHbsGR0tCAM",
  :site => "http://api.twitter.com"
)

system "touch '#{File.dirname(__FILE__)}/app.log'" unless File.exist?(File.dirname(__FILE__)+'/app.log')
@logger = Logger.new(File.dirname(__FILE__)+'/app.log')

begin
  token,secret,wait = YAML.load_file(File.dirname(__FILE__)+'/config.yaml')
rescue
  request_token = consumer.get_request_token  
  puts "Access this URL and approve => #{request_token.authorize_url}"
  print "Input OAuth Verifier: "
  oauth_verifier = gets.chomp.strip
  access_token = request_token.get_access_token(
    :oauth_verifier => oauth_verifier
  )
  puts "Access token: #{access_token.token}"
  puts "Access token secret: #{access_token.secret}"
  
  print "How many seconds to wait before deleting tweet?: "
  wait = gets.chomp.strip.to_i

  YAML.dump([access_token.token, access_token.secret, wait], open(File.dirname(__FILE__)+'/config.yaml', 'w'))
  puts "Access Token & Config Saved"
  token,secret = [access_token.token, access_token.secret]
end

access_token = OAuth::AccessToken.new(
  consumer,
  token,
  secret
)

def delete id, access_token, wait
  Thread.start do
    sleep wait
    r = JSON.parse(access_token.post("/statuses/destroy/#{id}.json").body)
    unless r["error"]
      text = r["text"]
      id = r["id"]
      username = r["user"]["screen_name"]
      @logger.debug "Deleted: @#{username} #{text} - http://twitter.com/#{username}/status/#{id}"
    end
  end
end

uri = URI.parse("https://userstream.twitter.com/2/user.json")
s = Net::HTTP.new(uri.host, uri.port)
s.use_ssl = true
s.verify_mode = OpenSSL::SSL::VERIFY_NONE
s.start do |h|
  q = Net::HTTP::Get.new(uri.request_uri)
  q.oauth!(h, consumer, access_token)
  h.request(q) do |r|
    r.read_body do |b|
      data = JSON.parse(b) rescue next
      if data["event"] == 'favorite'
        delete(data["target_object"]["id"], access_token, wait)
      elsif data["retweeted_status"]
        delete(data["retweeted_status"]["id"], access_token, wait)
      end
    end
  end
end
