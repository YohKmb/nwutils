eapier
====

Command-line utility to administrate multiple Arista EOS nodes.


### Description

This ruby script receives Arista CLI commands from standard-input stream, and sends them to multiple EOS nodes(both physical switch and virtual switch) via RESTful API.


### Requirement

 - Ruby later than 1.9
    - Developped and tested with ruby 1.9.3p194 on 3.18.0-kali3-amd64
    - No non-standard library is required

 - Arista EOS nodes which are opening eAPI port and listening for RESTful API POST requests


### Usage

command-line syntax is like below.

    usage : eapier [options] [targets]

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
      echo -e "show hostname\nshow version" | \
        ./eapier.rb -T -s -u admin -p password 192.168.1.1

      the example above send `show hostname` and `show version` commands to
      an EOS node who resides in 192.168.1.1.

      -s means the connection is established as https
      -T means you specify the format of outputs returned from EOS not in JSON,
         but in text-dump.


Target-file syntax is like below.

    {
        "192.168.1.1":
                {"user": "admin", "passwd": "secret"},
        "192.168.100.1":
                {"user": "admin", "passwd": "himitsu"},
        "eos-01":
                {"user": "eapi", "passwd": "secret"}
    }


### Licence

MIT (https://github.com/YohKmb/nwutils/blob/master/LICENSE)

### Author

Yoh Kamibayashi (https://github.com/YohKmb)

