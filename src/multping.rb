#! /usr/bin/env ruby


require "optparse"


SUBCMDS = {"add" => "va", "del" => "", "ping" => "tl"}
  
BRIDGE_DEFAULT = "vbr0"
SVI_NAME = "svi"
  
SUBNET = "192.168.%d.%d/24"
IP_DEFAULT = 1
GATEWAY_DEFAULT = 254
TARGET_DEFAULT = 2

LOGFILE_DEFAULT = "./ping.log"


def _add(params)
  vlans = _v_to_l(params["v"])
  
  _check_svi(params["b"])    
  for v in vlans do
    _create_svis(v)
    _set_addr(v, params["a"])
  end

end


def _v_to_l(vlans)
  vlans.gsub!("-", "..")
  vlans = vlans.split(",")
  
  vlans.map! do |v| eval(v) end
end


def _check_svi(bridge)
  %x[ip link show #{SVI_NAME}]
#  puts "Debug : " + $?.exitstatus.to_s
  if $?.exitstatus != 0
    puts "Notice : goint to create base svi"
    %x[ovs-vsctl add-port #{bridge} #{SVI_NAME} -- set interface #{SVI_NAME} type=internal]
    if $?.exitstatus != 0
      puts "Error : failed to create base svi interface"
      exit(1)
    end
  end
  
  %x[ip link set up dev #{SVI_NAME} &> /dev/null]
  if $?.exitstatus != 0
    puts "Warning : failed to set svi linkup"
  end
end


def _create_svis(v)

  if v.instance_of? Range
    for one in v
      _create_svis(one)
    end
  else

    %x[ip netns add #{SVI_NAME}.#{v}]
    if $?.exitstatus != 0
      puts "Warning : failed to netns of vlan #{v}"
    else
      %x[ip link add name #{SVI_NAME}.#{v} link #{SVI_NAME} type vlan id #{v}]
      if $?.exitstatus != 0
        puts "Warning : failed to create svi of vlan #{v}"
      end
      %x[ip link set #{SVI_NAME}.#{v} netns #{SVI_NAME}.#{v}]
      if $?.exitstatus != 0
        puts "Warning : failed to move netns of #{SVI_NAME}.#{v}"
      else
        %x[ip netns exec #{SVI_NAME}.#{v} ip link set up dev #{SVI_NAME}.#{v}]
        if $?.exitstatus != 0
          puts "Warning : failed to set linkup svi of vlan #{v}"
        end
      end
      
    end
    
  end
  
end


def _set_addr(v, ip_host)
  if v.instance_of? Range
    for one in v
      _set_addr(one, ip_host)
    end
  else
    %x[ip netns exec #{SVI_NAME}.#{v} ip addr add #{SUBNET % [(v % 256), ip_host]} dev #{SVI_NAME}.#{v}]
    if $?.exitstatus != 0
      puts "Warning : failed to set ip address of #{SVI_NAME}.#{v}"
    end
  end
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
      puts "Warning : failed to delete svi of vlan #{v}"
    end
    %x[ip netns delete #{svi}]
    if $?.exitstatus != 0
      puts "Warning : failed to delete netns of #{svi}"
    end
  end
  
  %x[ovs-vsctl del-port #{bridge} #{SVI_NAME}]
  if $?.exitstatus != 0
    puts "Error : failed to delete base svi interface"
    exit(1)
  end
  puts "Success : all svis got deleted cleanly"
  
end


def _ping(params)
  # fping -p 500 -t 2000 -l -Q 1 -s <target>
  pid = Process.spawn("ping localhost", :out=>params["l"],
                        :err=>params["l"])
  
  mon = Process.detach(pid)
  
  begin
     p mon.value
  rescue Interrupt => e
    puts
    puts "Notice : program exits due to [ctrl+c]"
  end
end


def _validate_opts(params, subcmd)
  musts = SUBCMDS[subcmd]
#  p musts
  res = musts != "" ?
    musts.each_char.map do |must| not params[must].nil? end :
    [true]
    
  if not res.all?
    puts "Error : some needed parameter are ignored"
    exit(1)
  end
end


### 
### main process starts here !
###

cmd = ARGV.shift
params = ARGV.getopts("v:b:a:t:l:T")

params["a"] ||= IP_DEFAULT
params["a"] = params["a"].to_i

params["t"] ||= TARGET_DEFAULT
params["t"] = params["t"].to_i

params["g"] ||= GATEWAY_DEFAULT
params["g"] = params["t"].to_i

params["b"] ||= BRIDGE_DEFAULT

params["l"] ||= LOGFILE_DEFAULT
params["l"].sub(/(?=\.\w+$)/, Time.now.strftime("_%Y%m%d_%H")) if params["T"]
  
#if not params["b"]
#  params["b"] = BRIDGE_DEFAULT
#end

if not SUBCMDS.keys.include?(cmd)
  puts "Error : Invalid subcommand"
  exit(1)
end

#p params
_validate_opts(params, cmd)

cmd = self.method( ("_" + cmd).to_sym)
cmd.call(params)


