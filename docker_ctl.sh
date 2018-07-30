#!/bin/bash
set -x
CFG_PATH=/etc/docker/net/

add_port () {
    BRIDGE=$1
    INTERFACE=$2
    CONTAINER=$3

    if [ -z $BRIDGE ] || [ -z $INTERFACE ] || [ -z $CONTAINER ]
    then
        echo "add-port: not enough arguments (use --help for help)"
        exit 1
    fi

    shift 4
    while [ $# -ne 0 ]; do
        case $1 in
            --ipaddress=*)
                ADDRESS=`expr X"$1" : 'X[^=]*=\(.*\)'`
                shift
                ;;
            --gateway=*)
                GATEWAY=`expr X"$1" : 'X[^=]*=\(.*\)'`
                shift
                ;;
            *)
                echo "add-port: unknown option \"$1\""
                exit 1
                ;;
        esac
    done
    
    linux_br=FALSE
    TYPE=linux
    ovs-vsctl --version > /dev/null 2>&1
    if [ $? -eq 0 ]
    then
        PORT=$(ovs-vsctl --data=bare --no-heading --columns=name find interface \
             external_ids:container_id=$CONTAINER external_ids:container_iface=$INTERFACE 2> /dev/null)
        if [ ! -z $PORT ]
        then
            echo "Port '$INTERFACE' already exist"
            exit 1
        fi

        ovs-vsctl br-exists $BRIDGE
        if [ $? -ne 0 ]
        then
            linux_br=TRUE
        else
            TYPE=ovs
        fi
#        ovs-vsctl --may-exist add-br $BRIDGE
    else
        brctl showmacs $BRIDGE > /dev/null 2&>1
        if [ $? -ne 0 ]
        then
            linux_br=TRUE
        fi
    fi

    if [ $linux_br == YES ]
    then
        brctl addbr $BRIDGE
    fi

    PID=$(docker inspect -f '{{.State.Pid}}' $CONTAINER);
    if [ $? != 0 ]
    then
        echo "Failed to get PID of the container '$CONTAINER'"
        exit 1
    elif [ $PID == '0' ]
    then
        echo "Container '$CONTAINER' is not active"
        exit 1
    fi

    mkdir -p /var/run/netns > /dev/null 2&>1
    if [ ! -e /var/run/netns/$PID ]
    then
        ln -s /proc/$PID/ns/net /var/run/netns/$PID
    fi

    ID=`uuidgen | sed 's/-//g'`
    PORTNAME="${ID:0:13}"
    ip link add "${PORTNAME}_l" type veth peer name "${PORTNAME}_c"

    if [ $ovs_br == TRUE ]
    then
        ovs-vsctl --may-exist add-port $BRIDGE "$PORTNAME"_l -- set interface "$PORTNAME"_l \
        external_ids:container_id=$CONTAINER external_ids:container_iface=$INTERFACE
    else
        brctl addif $BRIDGE "$PORTNAME"_l
    fi
    ip link set "$PORTNAME"_l up

    ip link set "$PORTNAME"_c netns $PID
    ip netns exec $PID ip link set dev "$PORTNAME"_c name $INTERFACE
    ip netns exec $PID ip link set $INTERFACE up

    CID=$(docker ps -a -f name=^/$CONTAINER$ --format {{.ID}})

    if [ ! -e $CFG_PATH ]
    then
        mkdir -p $CFG_PATH
    fi

    if [ ${#ADDRESS} -ne 0 ]
    then
        ip netns exec $PID ip addr add $ADDRESS dev $INTERFACE
    fi

    if [ ${#GATEWAY} -ne 0 ]
    then
        if [ -e $CFG_PATH$CID ]
        then
            gw=$(awk -F, '{print $6}' $CFG_PATH$CID |grep -v '^$')
            if [ ${#gw} -ne 0 ]
            then
                echo "Container '$CONTAINER' has set default route '$gw'."
                echo "Address '$GATEWAY' would be ignored."
            else
                ip netns exec $PID ip route add default via $GATEWAY > /dev/null 2&>1
            fi
        else
            ip netns exec $PID ip route add default via $GATEWAY > /dev/null 2&>1
        fi
    fi

    echo $BRIDGE,$TYPE,$INTERFACE,"$PORTNAME"_l,$ADDRESS,$GATEWAY >> $CFG_PATH$CID
}

del_port () {
    BRIDGE=$1
    INTERFACE=$2
    CONTAINER=$3

    if [ -z $BRIDGE ] || [ -z $INTERFACE ] || [ -z $CONTAINER ]
    then
        echo "del-port: not enough arguments (use --help for help)"
        exit 1
    fi

    CID=$(docker ps -a -f name=^/$CONTAINER$ --format {{.ID}})
    if [ ${#CID} -eq 0 ]
    then
        echo "No such container '$CONTAINER'."
        exit 1
    fi
    OLD_IFS=$IFS
    INFO=$(grep $BRIDGE,[a-z]\{3,5\},$INTERFACE $CFG_PATH$CID)
    if [ ${#INFO} -eq 0 ]
    then
        echo "Cannot find device '$INTERFACE' in container."
        exit 1
    fi
    IFS=","
    arr=($INFO)
    TYPE=${arr[2]}
    PORT=${arr[3]}
    IFS=$OLD_IFS
    if [ x$TYPE == x"ovs" ]
    then
        ovs-vsctl --if-exists del-port $BRIDGE $PORT > /dev/null
    else
        brctl delif $BRIDGE $PORT > /dev/null
    fi
    sed -i "s/${arr[0]},${arr[1]},${arr[2]},${arr[3]}.*/d" $CFG_PATH$CID
    ip link delete $PORT
}

recover () {
    while [ $# -ne 0 ]; do
        CID=$(docker ps -a -f name=^/$1$ --format {{.ID}})
        if [ ${#CID} -ne 0 ]
        then
            mv -f $CFG_PATH$CID{,.bak}
            cat $CFG_PATH$CID.bak | while read line
            do
                OLD_IFS=$IFS
                IFS=","
                arr=($line)
                if [ ${arr[1]} == "ovs" ]
                then
                    ovs-vsctl --may-exist add-br $BRIDGE
                fi
                add_port ${arr[0]} ${arr[2]} $1 --ipaddress=${arr[4]} --gateway=${arr[5]}
                IFS=$OLD_IFS
            done
            rm -f $CFG_PATH$CID.bak
        fi
        shift
    done
}

clear () {
    for CID in `ls $CFG_PATH`
    do
        name=$(docker ps -a -f id=$CID --format {{.Names}})
        status=$(docker ps -a -f id=$CID --format {{.Status}})
        cat $CFG_PATH$CID | while read line
        do
            OLD_IFS=$IFS
            IFS=","
            arr=($line)
            
            if [ ${#name} -eq 0 ] || [[ $status == Exited* ]]
            then
                if [ x${arr[1]} == x"ovs" ]
                then
                    ovs-vsctl --if-exists del-port ${arr[0]} ${arr[3]} > /dev/null 2>&1
                fi
            fi
            IFS=$OLD_IFS
        done

        if [ ${#name} -eq 0 ]
        then
            rm -f $CFG_PATH$CID
        fi
    done
}

usage() {
    cat << EOF
${UTIL}: Performs integration of Open vSwitch with Docker.
usage: ${UTIL} COMMAND

Commands:
  add-port BRIDGE INTERFACE CONTAINER [--ipaddress="ADDRESS"] [--gateway=GATEWAY]
                    Adds INTERFACE inside CONTAINER and connects it as a port
                    in Open vSwitch BRIDGE. Optionally, sets ADDRESS on
                    INTERFACE. ADDRESS can include a '/' to represent network
                    prefix length. Optionally, sets a GATEWAY.
                    If there is no bridge, ${UTIL} would create a linux bridge.
                    e.g.:
                    ${UTIL} add-port br-int eth1 c474a0e2830e
                    --ipaddress=192.168.1.2/24 --gateway=192.168.1.1

  del-port BRIDGE INTERFACE CONTAINER
                    Deletes INTERFACE inside CONTAINER and removes its
                    connection to Open vSwitch BRIDGE. e.g.:
                    ${UTIL} del-port br-int eth1 c474a0e2830e

  recover CONTAINER [CONTAINER...]
                    Recover INTERFACES inside CONTAINERS after starting them

  clear CONTAINER [CONTAINER...]
                    Clear INTERFACES inside CONTAINERS after stopping or delete them

Options:
  -h, --help        display this help message.
EOF
}

UTIL=$(basename $0)
if (ip netns) > /dev/null 2>&1; then :; else
    echo "ip utility not found (or it does not support netns), cannot proceed"
    exit 1
fi

if [ $# -eq 0 ]; then
    usage
    exit 0
fi

case $1 in
    "add-port")
        shift
        add_port "$@"
        exit 0
        ;;
    "del-port")
        shift
        del_port "$@"
        exit 0
        ;;
    "clear")
        shift
        clear "$@"
        exit 0
        ;;
    "recover")
        shift
        recover "$@"
        exit 0
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "unknown command \"$1\" (use --help for help)"
        exit 1
        ;;
esac