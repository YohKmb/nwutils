#! /usr/bin/env ruby

##
##  Copyright 2015 Yoh Kamibayashi
##

require "optparse"

require "net/https"
require "json"


PARAMS_AUTH = ["user", "passwd"]

params = ARGV.getopts("f:o:u:p:Ts", "port")
runcmds = STDIN.read.split("\n")

out_form = params["T"] ? "text" : "json"

proto = params["s"] ? "https" : "http"
# klass = Net::HTTPS : Net::HTTP

if params["f"]

  begin
    # targets = []
    targets = File::open(params["f"], "r") do |f_in|
      JSON.load(f_in)
    end

    targets = targets.each.select do |host, auth|
      checks = auth.keys.each.map do |k|
        PARAMS_AUTH.include? k
      end
      checks.all?
    end

  rescue Errno::ENOENT => e
    puts "Error : Failure occurred related to a logging directory"
    puts e.message
    exit(1)
  end

elsif params["u"] and params["p"]
  targets = ARGV.zip( [{"user" => params["u"], "passwd" => params["p"]}] * ARGV.length )

else
  puts "Error : Authentication infomaion was not found"
  # puts e.message
  exit(1)
end

jsdata = {
    :jsonrpc => "2.0",
    :method => "runCmds",
    :params => {
      :version => 1,
      :format => out_form,
      :cmds => runcmds
    },
    :id => "#{__FILE__ + "_" + rand(1024).to_s}"
}

# p targets
targets.each do |host, auth|

  host += ":" + params["port"] if params["port"]
  uri = URI("#{proto}://#{host}/command-api" )

  req = Net::HTTP::Post.new(uri.path)
  req.basic_auth(auth["user"], auth["passwd"])
  req.body = jsdata.to_json

  begin
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if params["s"]
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE if params["s"]

    http.start
    res = http.request(req)

  rescue Exception => e
    puts e.class
    puts "Error : Http connection failed"
    exit(1)
  end

  if not res
    puts "Warning : No response came from #{host}"
    next
  end

  jsres = JSON.load(res.body)["result"]
  jsres = jsres.each.map do |r| r["output"] end if params["T"]
  jsres = runcmds.zip(jsres)

  puts "#### BEGIN #{host} ###########################"
  puts
  # p res
  # p JSON::load(res.body) if res
  p jsres
  puts
  puts "######################## END #{host} #########"
  puts "\n" * 2

end



