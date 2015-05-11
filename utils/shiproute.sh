#! /bin/bash

echo -e "enable\nshow ip route\n" | \
    ./src/eapier.rb -T -s -u eapi -p password 192.168.1.250 | \
    sed -nE 's/.+([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{1,2}).+/\1/p'