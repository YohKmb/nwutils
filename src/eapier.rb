#! /usr/bin/env ruby

##
##  Copyright 2015 Yoh Kamibayashi
##

require "optparse"

require "net/https"
require "json"
require "resolv"

Version = "v1.0"

# params = ARGV.getopts("f:u:p:Tsec", "port")

USAGE = <<EOT
  usage : #{__FILE__} [options] [targets]

    [options]
      -f filename : specify a JSON formatted file in which targets
                    and infomation for their authentication are listed
      -u user
      -p password
      -T : switch the output format to text-dumping of show CLI commands
           (default is JSON formatted outputs)
      -s : use https protocol for eAPI connection
      -e : prepend "enable" command to executed commands list
      -c : prepend "enable" and "configure" commands to executed commands list

  example :
      echo -e "show hostname\\nshow version" | \\
        ./eapier.rb -T -s -u admin -p password 192.168.1.1

      the example above send `show hostname` and `show version` commands to
      an EOS node who resides in 192.168.1.1.

      -s means the connection is established as https
      -T means you specify the format of outputs returned from EOS not in JSON,
         but in text-dump.

EOT

PARAMS_AUTH = ["user", "passwd"]


class Eapier

  PARAMS_AUTH = ["user", "passwd", "port"]

  def initialize(runcmds, filename_targets, user, passwd, is_https, port_dst,
                 is_text, is_enable, is_conf, *arglist)

    modecmd = []
    modecmd << "enable" if is_enable or is_conf
    modecmd << "configure" if is_conf
    runcmds.unshift(*modecmd)

    @runcmds = runcmds
    @proto = is_https ? "https" : "http"

    @Formatter = is_text ? LogTextFormatter : LogJsonFormatter
    @resolver = Resolv::Hosts::new

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
        exit(1)
      end

    elsif user and passwd
      port = nil
      port = port_dst if port_dst
      @targets = Hash[arglist.zip( [{"user" => user, "passwd" => passwd, "port" => port}] * arglist.length )]

    else
      puts "Error : Authentication infomaion was not found"
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
      res = nil
    end

    res

  end


  def start

    @targets.each do |host, auth|

      uri = self._get_uri(host, auth)
      req = self._get_post_req(uri, auth)

      res = self._send_and_receive(uri, req)

      begin
        sol = @resolver.getaddress(host)
      rescue Resolv::ResolvError => e
        sol = nil
      end
      host += " (#{sol})" if sol

      if res.nil?
        @Formatter::alert(host, "Warning : Skip #{host} and go to the next target host")
        next
      end

      @Formatter::format(host, @runcmds, res)

    end
  end

end


class LogFormatter

  class << self

    def format(host, runcmds, htres)
      _print_prelude(host)
      _print_content(runcmds, htres)
      _print_finale(host)
    end

    def alert(host, msg)
      _print_prelude(host)
      puts msg
      _print_finale(host)
    end

    def _print_content(runcmds, htres) nil end

    def _print_prelude(host)
      puts "###### BEGIN #{host} ##########################################################"
      puts
    end

    def _print_finale(host)
      puts
      puts "############################################### END #{host} ###################"
      puts "\n" * 2
    end

  end

end


class LogTextFormatter < LogFormatter

  class << self
    def _print_content(runcmds, htres)
      jsres = JSON.load(htres.body)["result"]
      jsres = jsres.each.map do |r| r["output"] end
      jsres = runcmds.zip(jsres)

      jsres.each do |cmd, out|
        puts "[------------------- #{cmd} --------------------------]"
        puts
        puts out
        puts
        puts "[--------------------#{'-' * cmd.length}---------------------------]"
        puts
      end
    end
  end

end


class LogJsonFormatter < LogFormatter

  class << self
    def _print_content(runcmds, htres)
      jsres = JSON.load(htres.body)["result"]
      jsres = runcmds.zip(jsres)

      jsres.each do |cmd, out|
        puts "[------------------- #{cmd} --------------------------]"
        puts
        puts( JSON.pretty_generate(out) )
        puts
        puts "[--------------------#{'-' * cmd.length}---------------------------]"
        puts
      end
    end
  end

end


def _help(exit_status)

  print USAGE
  exit(exit_status)

end


params = ARGV.getopts("f:u:p:Tsec", "port", "help")
_help(0) if params["h"] or params["help"]

runcmds = STDIN.read.split("\n")

eapier = Eapier.new(runcmds, params["f"], params["u"], params["p"], params["s"],
                    params["port"], params["T"], params["e"], params["c"], *ARGV)
eapier.start

