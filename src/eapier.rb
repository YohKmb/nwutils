#! /usr/bin/env ruby

##
##  Copyright 2015 Yoh Kamibayashi
##

require "optparse"

require "net/http"
require "json"


PARAMS_AUTH = ["user", "passwd"]

params = ARGV.getopts("f:o:u:p:T")
runcmds = STDIN.read.split("\n")

out_form = params["T"] ? "text" : "json"

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

  uri = URI("http://#{host}/command-api")

  req = Net::HTTP::Post.new(uri.path)
  req.basic_auth(auth["user"], auth["passwd"])
  req.body = jsdata.to_json

  res = Net::HTTP.start(uri.host, uri.port) do |http|
    http.request(req)
  end

  puts "###########################"
  puts
  p JSON::load(res.body)
  puts
  puts "###########################"

end



