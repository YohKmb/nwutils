#! /usr/bin/env ruby

require "optparse"

# SUBCMDS = {"set" => :set, "unset" => :unset, "start" => :start, "stop" => :stop}
SUBCMDS = ["add", "del", "start", "stop"]
  
BRIDGE_DEFAULT = "vbr0"
SVI_NAME = "svi"
  

def _add(params)
  vlans = _v_to_l(params["v"])
  
  _check_svi(params["b"])    
  for v in vlans do
    _create_svis(v)
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
    %x[ip link add name #{SVI_NAME}.#{v} link #{SVI_NAME} type vlan id #{v}]
    if $?.exitstatus != 0
      puts "Warning : failed to create svi of vlan #{v}"
    end
    %x[ip link set up dev #{SVI_NAME}.#{v}]
    if $?.exitstatus != 0
      puts "Warning : failed to set linkup svi of vlan #{v}"
    end
#    p "created " + v.to_s
  end
  
end

def _del(params)
  
  bridge = params["b"]
    
  linkstat = %x[ip link show]
  svis = []
  
  linkstat.each_line do |line|
    if mgs = line.match(/(svi\.\d+)/)
      svis.push(mgs[0])
    end
  end
  svis.uniq!

  for svi in svis do
    %x[ip link delete dev #{svi}]
    if $?.exitstatus != 0
      puts "Warning : failed to delete svi of vlan #{v}"
    end
  end
  
  %x[ovs-vsctl del-port #{bridge} #{SVI_NAME}]
  if $?.exitstatus != 0
    puts "Error : failed to delete base svi interface"
    exit(1)
  end
  puts "Success : all svis got deleted cleanly"
  
end

cmd = ARGV.shift
params = ARGV.getopts("i:v:H:t:l:b:")

if not params["b"]
  params["b"] = BRIDGE_DEFAULT
end

if not SUBCMDS.include?(cmd)
  puts "Error : Invalid subcommand"
  exit(1)
end

cmd = self.method( ("_" + cmd).to_sym)

cmd.call(params)


