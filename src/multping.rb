#! /usr/bin/env ruby


require "optparse"


SUBCMDS = {"add" => "va", "del" => "", "ping" => "tl"}
  
BRIDGE_DEFAULT = "vbr0"
SVI_NAME = "svi"

EXECUTABLE = "fping"
  
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


def _set_addr(v, ip_host, ip_gw)

  %x[ip netns exec #{SVI_NAME}.#{v} ip addr add #{SUBNET % [(v % 256), ip_host]} dev #{SVI_NAME}.#{v}]
#  %x[ip netns exec #{SVI_NAME}.#{v} ip addr add #{_v_to_addr(v, ip_host)} dev #{SVI_NAME}.#{v}]
  if $?.exitstatus != 0
    puts "Warning : failed to set ip address of #{SVI_NAME}.#{v}"
  end
#    p "#{SUBNET % [(v % 256), ip_gw]}"
  %x[ip netns exec #{SVI_NAME}.#{v} ip route add 0.0.0.0/0 via #{_v_to_addr(v, ip_gw)}]
  if $?.exitstatus != 0
    puts "Warning : failed to configure default route of #{SVI_NAME}.#{v}"
  end

end


def _v_to_addr(vlan, ip)
  
  "#{(SUBNET % [(vlan % 256), ip]).split("/").shift }"

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
  
  ping_bin = %x[which #{EXECUTABLE}].chop
  if ping_bin.length == 0
    puts "Error : could not find ping tool \"#{EXECUTABLE}\""
    exit(1)
  end
  
  map_targ = _build_targets(params)
  
  map_targ.each do |ns, vlans|
    pid = Process.spawn("ping localhost")
    mon = Process.detach(pid)
  end
  
#  p map_targ
#  exit(0)

  # fping -p 500 -t 2000 -l -Q 1 -s <target>
#  pid = Process.spawn("ping localhost", :out=>params["l"],
#                        :err=>params["l"])
#  mon = Process.detach(pid)
  
  begin
     p mon.value
  rescue Interrupt => e
    puts
    puts "Notice : program exits due to [ctrl+c]"
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
  vlans.uniq!
  vlans.sort!
  
  if params["l3"]
    if params["x"] and params["s"]
      puts "Error : inconsistent options were passed"
      exit(1)
    else
      vlans = params["s"].nil? ? vlans : _v_to_l(params["s"])
      l_x = _v_to_l(params["x"]) if not params["x"].nil?
      vlans -= l_x if not l_x.nil?
      
      Hash[nses.zip([vlans] * nses.length) ]
    end
      
  else
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
    puts "Error : some needed parameter are ignored"
    exit(1)
  end

end


### 
### main process starts here !
###

cmd = ARGV.shift
params = ARGV.getopts("v:b:a:t:x:s:l:T", "l3")

params["a"] ||= IP_DEFAULT
params["a"] = params["a"].to_i

params["t"] ||= TARGET_DEFAULT
params["t"] = params["t"].to_i

params["g"] ||= GATEWAY_DEFAULT
params["g"] = params["g"].to_i

params["b"] ||= BRIDGE_DEFAULT

params["l"] ||= LOGFILE_DEFAULT
params["l"].sub(/(?=\.\w+$)/, Time.now.strftime("_%Y%m%d_%H")) if params["T"]
  

if not SUBCMDS.keys.include?(cmd)
  puts "Error : Invalid subcommand"
  exit(1)
end

#p params
_validate_opts(params, cmd)

cmd = self.method( ("_" + cmd).to_sym)
cmd.call(params)


