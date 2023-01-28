#!/bin/sh

# test-for-vpn [interface-name]

# test to see if a VPN is running.
# If so , print out 'vpn' and exit 1
# Otherwise, print nothing and exit 0.
# Intended to be used by programs to test if a vpn in use.

# Defaults to looking for a network interface of nordvpn.
# If it is something different, then give the network interface
# name as an argument

default_interface=nordtun

PATH="$PATH:/sbin:/usr/sbin"
export PATH

interface=$1
if [ x$interface = 'x' ]; then
    interface=$default_interface
fi

ifconfig -a | grep --quiet ^${interface}
if [ $? -eq 0 ]; then
    echo vpn
    exit 1
fi
exit 0
