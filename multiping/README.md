multiping
====

Command-line utility to setup/conduct/cleanup many-to-many ping environments.


### Description

This ruby script help you to create a lot of IP assigned vlan virtual interfaces and fire pings from/to them. (Two linux hosts may be used as src/dst nodes.)

One line issue of this may relieve you so much to test network reachabilities for many vlan domain.

Log files for each ping source is automatically saved in a directory. You can specify any direction for this purpose with an option.


### Requirement

 - Ruby later than 1.9 (No non-standard library is required)
 - Open-vSwitch 1.4.2 or later
 - Linux kernel which supports network namespace


### Usage

command-line syntax is like below.

    usage : multping command [command_opts] [command_args]
    
    [commands]
      add : create svi(s) for each vlans specified with "-v" option
            also assign ip-addr and configure default route
            
      del : delete existing svi(s)
      
      ping : start ping and save their logs
             default ping mode is l2(layer2)
             you can switch it to layer3 pinging with "--l3" switch option
      
      help : displays this "usage"       
  
    [command_options]
      -v vlans... : vlans you want to create a coressponding svi
                    both cisco-like range format and ruby-like range format are accepted
                    (used w/ add command)
      -b bridge_name : bridge name to which svi(s) would be attached
                       (used w/ add command)
                       default is vbr0
      -a assigned_addr : ip address of host section that would be assigned to svi(s)
                         default=1 (meaning x.x.x.1)
                         (used w/ add command)
      -t target_addr : ip address of host section to which ping is fired
                       default=2 (meaning y.y.y.2)
                       (used w/ ping command)
      -x exclude_vlans... : exclude specified vlans from l3 ping targets
                            (used w/ ping command, l3 mode)
      -s specified_vlans... : specify vlans mannually to which ping is fired
                              (used /w ping command, l3 mode)
      -l log_dir : a name of director in which ping logs would be saved
                   default=./pinglog.d
                   (used w/ ping command)
      -T : switch that decide whether time-stamp are appeded to log_dir's name
           defalt=false
           (used w/ ping command)
      --l3 : switch the mode of pinging from l2 ping to l3 ping
             (used w/ ping command)


Logging directory would be created like the hierarchy below.

    multiping ping -l logdir -T
    
    (Conducting ping..... ,and finish.)

    logdir_20150514_163033/
        logdir_20150514_163033/svi.711.log
        logdir_20150514_163033/svi.712.log


### Licence

MIT (https://github.com/YohKmb/nwutils/blob/master/LICENSE)


### Author

Yoh Kamibayashi (https://github.com/YohKmb)

