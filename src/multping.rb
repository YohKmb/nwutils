#! /usr/bin/env ruby

##
##  Copyright 2015 Yoh Kamibayashi
##


require "optparse"
require "open3"


USAGE = <<EOT
  usage : #{__FILE__} command [command_opts] [command_args]
    
    [commands]
      add : create svi(s) for each vlans specified with "-v" option
            also assign ip-addr and configure default route
            
      del : delete existing svi(s)
      
      ping : start ping and save their logs
             default ping mode is l2(layer2) but could be switched with "--l3" switch option
      
      help : displays this "usage"       
  
    [command_options]
      -v vlans... : vlans you want to add in list format (add command)
      -b bridge_name : bridge name to which svi(s) would be attached (add command)
      -a assigned_addr : ip address of host section that would be assigned to svi(s) (add command)
      -t target_addr : ip address of host section to which ping is fired (ping command)
      -x exclude_vlans... : exclude specified vlans from l3 ping targets (ping command, l3 mode)
      -s specified_vlans... : specify vlans mannually to which ping is fired (ping command, l3 mode)
      -l log_dir : a name of director in which ping logs would be saved (ping command)
      
      -T : switch that decide whether time-stamp are appeded to log_dir's name, defalt=false (ping command)
      --l3 : switch the mode of pinging from l2 ping to l3 ping

EOT
# params = ARGV.getopts("v:b:a:t:x:s:l:T", "l3", "no-log")

Version = "v1.0"

SUBCMDS = {"add" => "va", "del" => "", "ping" => "tl", "help" => ""}
  
BRIDGE_DEFAULT = "vbr0"
#EXTERNAL_IFACE = "eth1"
SVI_NAME = "svi"

EXECUTABLE = "fping"
  
#SUBNET = "192.168.%d.%d/24"
SUBNET = "172.%d.%d.%d/24"
IP_DEFAULT = 1
GATEWAY_DEFAULT = 254
TARGET_DEFAULT = 2

LOGDIR_DEFAULT = "./pinglog.d"
CACHE_TARGETS = "./.targs"


def _add(params)
  
  vlans = _v_to_l(params["v"])
  
  _check_svi(params["b"])    
  for v in vlans do
    _create_svis(v)
    _set_addr(v, params["a"], params["g"])
  end

end


def _v_to_l(vlans)
  
  vlans.gsub!("-", "..")
  vlans = vlans.split(",")
  
  vlans.map! do |v| eval(v) end
  vlans.map! do |v| v.instance_of?(Range) ? v.to_a : v end
    
  vlans.flatten!
  vlans.sort!
end


def _check_svi(bridge)

  %x[ip link show #{SVI_NAME}]

  if $?.exitstatus != 0
    puts "Notice : Goint to create base svi"
    %x[ovs-vsctl add-port #{bridge} #{SVI_NAME} -- set interface #{SVI_NAME} type=internal]
    if $?.exitstatus != 0
      puts "Error : Failed to create base svi interface"
      exit(1)
    end
  end
  
  %x[ip link set up dev #{SVI_NAME}]
  if $?.exitstatus != 0
    puts "Warning : Failed to set svi linkup"
  end
end


def _create_svis(v)

  %x[ip netns add #{SVI_NAME}.#{v}]
  if $?.exitstatus != 0
    puts "Warning : Failed to netns of vlan #{v}"
  else
    %x[ip link add name #{SVI_NAME}.#{v} link #{SVI_NAME} type vlan id #{v}]
    if $?.exitstatus != 0
      puts "Warning : Failed to create svi of vlan #{v}"
    end
    %x[ip link set #{SVI_NAME}.#{v} netns #{SVI_NAME}.#{v}]
    if $?.exitstatus != 0
      puts "Warning : Failed to move netns of #{SVI_NAME}.#{v}"
    else
      %x[ip netns exec #{SVI_NAME}.#{v} ip link set up dev #{SVI_NAME}.#{v}]
      if $?.exitstatus != 0
        puts "Warning : Failed to set linkup svi of vlan #{v}"
      end
    end
    
  end
  
end


def _set_addr(v, ip_host, ip_gw)

  %x[ip netns exec #{SVI_NAME}.#{v} ip addr add #{SUBNET % [(16 + v / 256), (v % 256), ip_host]} dev #{SVI_NAME}.#{v}]
  if $?.exitstatus != 0
    puts "Warning : Failed to set ip address of #{SVI_NAME}.#{v}"
  end
  
  %x[ip netns exec #{SVI_NAME}.#{v} ip route add 0.0.0.0/0 via #{_v_to_addr(v, ip_gw)}]
  if $?.exitstatus != 0
    puts "Warning : Failed to configure default route of #{SVI_NAME}.#{v}"
  end

end


def _v_to_addr(vlan, ip)
  
  "#{(SUBNET % [(16 + vlan / 256), (vlan % 256), ip]).split("/").shift }"

end


def _del(params)

  bridge = params["b"]
#  linkstat = %x[ip link show]
  linkstat = %x[ip netns list]
  svis = []
  
  linkstat.each_line do |line|
    if mgs = line.match(/(svi\.\d+)/)
      svis << mgs[0]
    end
  end
  svis.uniq!

  for svi in svis do
    %x[ip netns exec #{svi} ip link delete dev #{svi}]
    if $?.exitstatus != 0
      puts "Warning : Failed to delete svi of vlan #{v}"
    end
    %x[ip netns delete #{svi}]
    if $?.exitstatus != 0
      puts "Warning : Failed to delete netns of #{svi}"
    end
  end
  
  %x[ovs-vsctl del-port #{bridge} #{SVI_NAME}]
  if $?.exitstatus != 0
    puts "Error : Failed to delete base svi interface"
    exit(1)
  end
  puts "Success : All svis got deleted cleanly"
  
end


def _ping(params)
  
  ping_bin = %x[which #{EXECUTABLE}].chop
  if ping_bin.length == 0
    puts "Error : Could not find ping tool \"#{EXECUTABLE}\""
    exit(1)
  end
  
  begin
    Dir::mkdir(params["l"])
    Dir::chdir(params["l"])
      
  rescue Errno::ENOENT => e
    puts "Error : Failure occurred related to a logging directory"
    puts e.message
    exit(1)
    
  end
  
  map_targ = _build_targets(params)
  log_fds = []
    
  if params["l3"]
    f_targ = File::open(CACHE_TARGETS, "w")
    map_targ[:common].each do |targ|
      f_targ.puts(targ)
    end
    f_targ.close
  end
  
#  p map_targ
  map_targ.each_key do |ns|
    
    log_fd = File::open("./#{ns}.log", "w")
    log_fds << log_fd
    
    cmds = ["ip", "netns", "exec", "#{ns}", ping_bin, "-s", "-l"]
    cmds += params["l3"] ? ["-f #{CACHE_TARGETS}"] : [map_targ[ns]]
#    if params["l3"]
#      f_targ = File::open("./.targs", "w")
#      targs.each do |targ|
#        f_targ.puts(targ)
#      end
#      f_targ.close
#    end
#    targs = targs.instance_of?(Array) ? targs.join(" ") : targs
    
    Thread::new do
      # fping -p 100 -t 1000 -l -Q 1 -s
      Open3::popen2e(*cmds) do |i,oe,t|
        
        begin
          oe.each do |line|
            log_fd.puts(line)
          end
        ensure
          log_fd.print(oe.read)
        end
        
      end
    end
    
  end
  
  begin
    for t in Thread::list do t.join unless t.equal? Thread::current end
    
  rescue Interrupt => e
    puts
    puts "Notice : Program exits due to [ctrl+c]"
    for t in Thread::list do t.kill unless t.equal? Thread::current end

  ensure
    for t in Thread::list do t.kill unless t.equal? Thread::current end
    for t in Thread::list do t.join unless t.equal? Thread::current end
    
    begin
      File::delete(CACHE_TARGETS) if params["l3"]
    rescue Errno::ENOENT => e
      puts "Warning : Failed to delete target-cache file"
      puts e.message
    end
    
  end

end


def _build_targets(params)

  nsstat = %x[ip netns list]
  nses = []
  vlans = []
  
  nsstat.each_line do |line|
    if mgs = line.match(/svi\.(\d+)/)
      nses << mgs[0]
      vlans << mgs[1].to_i
    end
  end

  nses.uniq!
  nses.sort!
#  p nses
  vlans.uniq!
  vlans.sort!
#  p vlans
  
  if params["l3"]
    if params["x"] and params["s"]
      puts "Error : Inconsistent options were passed"
      exit(1)
    else
      vlans = params["s"].nil? ? vlans : _v_to_l(params["s"])
      l_x = _v_to_l(params["x"]) if not params["x"].nil?
      vlans -= l_x if not l_x.nil?
      
      vlans.map! do |v| _v_to_addr(v, params["t"]) end
      Hash[:common] = vlans
#      Hash[nses.zip([vlans] * nses.length) ]
    end
      
  else
    vlans.map! do |v| _v_to_addr(v, params["t"]) end
    Hash[nses.zip(vlans)]
  end
  
end


def _validate_opts(params, subcmd)

  musts = SUBCMDS[subcmd]
#  p musts
  res = musts != "" ?
    musts.each_char.map do |must| not params[must].nil? end :
    [true]
    
  if not res.all?
    puts "Error : Some needed parameter are ignored"
    puts
    _help(1)
#    exit(1)
  end

end


def _help(exit_status)

  print USAGE
  exit(exit_status)
  
end


### 
### main process starts here !
###

cmd = ARGV.shift
params = ARGV.getopts("v:b:a:t:x:s:l:T", "l3", "no-log")

params["a"] ||= IP_DEFAULT
params["a"] = params["a"].to_i

params["t"] ||= TARGET_DEFAULT
params["t"] = params["t"].to_i

params["g"] ||= GATEWAY_DEFAULT
params["g"] = params["g"].to_i

params["b"] ||= BRIDGE_DEFAULT

params["l"] ||= LOGDIR_DEFAULT
params["l"].sub!(/(?=\.\w+$)|(?=$)/, Time.now.strftime("_%Y%m%d_%H%M%S")) if params["T"]
  

if not SUBCMDS.keys.include?(cmd)
  puts "Error : Invalid subcommand"
  puts
#  exit(1)
  _help(1)
end

#p params
_help(0) if cmd == "help"
_validate_opts(params, cmd)

cmd = self.method( ("_" + cmd).to_sym)
cmd.call(params)


