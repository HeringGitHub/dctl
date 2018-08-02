dctl
=======
Command dctl use for container add port or delete port.  
Modified base on command ovs-docker in project ovs(https://github.com/openvswitch/ovs.git).

Added linux bridge supporting(default).  
Added ip address recording and if container restart, the inner ports would be added automatically.  
Deleted vlan and mtu option.

Install:
-------
In project directory, execute:  
chmod +x install.sh  
./install.sh

Useage:
-------
dctl  add-port BRIDGE INTERFACE CONTAINER [--ipaddress=ADDRESS] [--gateway=GATEWAY]

                    Adds INTERFACE inside CONTAINER and connects it as a port  
                    in Open vSwitch BRIDGE. Optionally, sets ADDRESS on
                    INTERFACE. ADDRESS can include a '/' to represent network
                    prefix length. Optionally, sets a GATEWAY.
                    If there is no bridge named BRIDGE, ${UTIL} would create a linux bridge.
                    e.g.:
                    ${UTIL} add-port br-int eth1 c474a0e2830e
                    --ipaddress=192.168.1.2/24 --gateway=192.168.1.1

dctl  del-port BRIDGE INTERFACE CONTAINER

                    Deletes INTERFACE inside CONTAINER and removes its
                    connection to Open vSwitch BRIDGE.
                    e.g.:
                    ${UTIL} del-port br-int eth1 c474a0e2830e

dctl  -h, --help

                    display this help message.



Warning:
-------
The option clear/recover use for invoking automatically when starting container, don't use them initiatively. 