#! /usr/bin/env ruby

##
##  Copyright 2015 Yoh Kamibayashi
##

require "optparse"

require "net/https"
require "json"


PARAMS_AUTH = ["user", "passwd"]


class Eapier

  PARAMS_AUTH = ["user", "passwd", "port"]

  def initialize(runcmds, filename_targets, user, passwd, is_https, port_dst,
                 is_text, *arglist)
    @runcmds = runcmds
    # @targets = targets
    @proto = is_https ? "https" : "http"
    @is_text = is_text

    if filename_targets
      begin
        targets = File::open(filename_targets, "r") do |f_in|
          JSON.load(f_in)
        end

        @targets = targets.each.select do |host, auth|
          checks = auth.keys.each.map do |k|
            PARAMS_AUTH.include? k
          end
          checks.all?
        end

        if @targets.length == 0
          puts "Error : No valid target host and its auth-info was provided"
          exit(1)
        end

      rescue Errno::ENOENT => e
        puts "Error : Failure occurred related to file operations"
        # puts e.message
        exit(1)

      rescue JSON::ParserError => e
        puts "Error : Invalid json format"
        # puts e.message
        exit(1)
      end

    elsif user and passwd
      port = nil
      port = port_dst if port_dst
      # port = is_https ? 443 : 80 if port.nil?
      @targets = Hash[arglist.zip( [{"user" => user, "passwd" => passwd, "port" => port}] * arglist.length )]

    else
      puts "Error : Authentication infomaion was not found"
      # puts e.message
      exit(1)
    end
    # p @targets
    if @targets.length == 0
      puts "Error : No eapi target was passed"
    end

    @jsdata = {
        :jsonrpc => "2.0",
        :method => "runCmds",
        :params => {
            :version => 1,
            :format => is_text ? "text" : "json",
            :cmds => runcmds
        },
        :id => "#{__FILE__ + '_'}"
    }

  end


  def _get_uri(host, auth)

    # std_port = {"http" => 80, "htpps" => 443}
    host += ":" + auth["port"].to_s if auth["port"]

    URI("#{@proto}://#{host}/command-api" )
  end


  def _get_post_req(uri, auth)

    req = Net::HTTP::Post.new(uri.path)
    req.basic_auth(auth["user"], auth["passwd"])
    jsdata = @jsdata.dup
    jsdata[:id] += rand(1000).to_s
    req.body = jsdata.to_json

    req
  end


  def _send_and_receive(uri, req)

    begin
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true if @proto == "https"
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE if @proto == "https"

      http.start
      res = http.request(req)

    rescue Exception => e
      puts e.class
      puts "Warning : Http connection failed for #{uri.host}"
      # exit(1)
      res = nil
    end

    res

  end


  def start

    @targets.each do |host, auth|

      puts "#### BEGIN #{host} #############################"
      puts
      # host += ":" + auth["port"]
      # uri = URI("#{@proto}://#{host}/command-api" )
      uri = self._get_uri(host, auth)

      # req = Net::HTTP::Post.new(uri.path)
      # req.basic_auth(auth["user"], auth["passwd"])
      # req.body = jsdata.to_json
      req = self._get_post_req(uri, auth)

      # begin
      #   http = Net::HTTP.new(uri.host, uri.port)
      #   http.use_ssl = true if @proto == "https"
      #   http.verify_mode = OpenSSL::SSL::VERIFY_NONE if @proto == "https"
      #
      #   http.start
      #   res = http.request(req)
      #
      # rescue Exception => e
      #   puts e.class
      #   puts "Error : Http connection failed"
      #   exit(1)
      # end
      #
      res = self._send_and_receive(uri, req)
      if res.nil?
        puts "Warning : Skip #{host} and go to the next target host"
        puts "########################## END #{host} #########"
        puts "\n" * 2
        
        next
      end

      jsres = JSON.load(res.body)["result"]
      jsres = jsres.each.map do |r| r["output"] end if @is_text
      jsres = @runcmds.zip(jsres)

      # puts "#### BEGIN #{host} #############################"
      # puts
      # p res
      # p JSON::load(res.body) if res
      p jsres
      puts
      puts "########################## END #{host} #########"
      puts "\n" * 2

    end
  end

end


params = ARGV.getopts("f:o:u:p:Ts", "port")
runcmds = STDIN.read.split("\n")
# p ARGV

# out_form = params["T"] ? "text" : "json"

# proto = params["s"] ? "https" : "http"
# klass = Net::HTTPS : Net::HTTP


# def initialize(runcmds, filename_targets, user, passwd, is_https, port_dst,
#                is_text, *arglist)


eapier = Eapier.new(runcmds, params["f"], params["u"], params["p"], params["s"],
                    params["port"], params["T"], *ARGV)

eapier.start

# if params["f"]
#
#   begin
#     # targets = []
#     targets = File::open(params["f"], "r") do |f_in|
#       JSON.load(f_in)
#     end
#
#     targets = targets.each.select do |host, auth|
#       checks = auth.keys.each.map do |k|
#         PARAMS_AUTH.include? k
#       end
#       checks.all?
#     end
#
#   rescue Errno::ENOENT => e
#     puts "Error : Failure occurred related to a logging directory"
#     puts e.message
#     exit(1)
#   end
#
# elsif params["u"] and params["p"]
#   targets = ARGV.zip( [{"user" => params["u"], "passwd" => params["p"]}] * ARGV.length )
#
# else
#   puts "Error : Authentication infomaion was not found"
#   # puts e.message
#   exit(1)
# end
#
# jsdata = {
#     :jsonrpc => "2.0",
#     :method => "runCmds",
#     :params => {
#       :version => 1,
#       :format => out_form,
#       :cmds => runcmds
#     },
#     :id => "#{__FILE__ + "_" + rand(1024).to_s}"
# }
#
# # p targets
# targets.each do |host, auth|
#
#   host += ":" + params["port"] if params["port"]
#   uri = URI("#{proto}://#{host}/command-api" )
#
#   req = Net::HTTP::Post.new(uri.path)
#   req.basic_auth(auth["user"], auth["passwd"])
#   req.body = jsdata.to_json
#
#   begin
#     http = Net::HTTP.new(uri.host, uri.port)
#     http.use_ssl = true if params["s"]
#     http.verify_mode = OpenSSL::SSL::VERIFY_NONE if params["s"]
#
#     http.start
#     res = http.request(req)
#
#   rescue Exception => e
#     puts e.class
#     puts "Error : Http connection failed"
#     exit(1)
#   end
#
#   if not res
#     puts "Warning : No response came from #{host}"
#     next
#   end
#
#   jsres = JSON.load(res.body)["result"]
#   jsres = jsres.each.map do |r| r["output"] end if params["T"]
#   jsres = runcmds.zip(jsres)
#
#   puts "#### BEGIN #{host} #############################"
#   puts
#   # p res
#   # p JSON::load(res.body) if res
#   p jsres
#   puts
#   puts "########################## END #{host} #########"
#   puts "\n" * 2
#
# end



