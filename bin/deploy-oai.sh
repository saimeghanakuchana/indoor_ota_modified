set -ex
COMMIT_HASH=$1
NODE_ROLE=$2
BINDIR=`dirname $0`
ETCDIR=/local/repository/etc
source $BINDIR/common.sh

if [ -f $SRCDIR/oai-setup-complete ]; then
    echo "setup already ran; not running again"
    if [ $NODE_ROLE == "cn" ]; then
        sudo sysctl net.ipv4.conf.all.forwarding=1
        sudo iptables -P FORWARD ACCEPT
    elif [ $NODE_ROLE == "nodeb" ]; then
        LANIF=`ip r | awk '/192\.168\.1\.2/{print $3}'`
        if [ ! -z $LANIF ]; then
          echo LAN IFACE is $LANIF...
          echo adding route to CN
          sudo ip route add 192.168.70.128/26 via 192.168.1.1 dev $LANIF
        fi
    fi
    exit 0
fi

function setup_cn_node {
    # Install docker, docker compose, wireshark/tshark
    echo setting up cn node
    sudo apt-get update && sudo apt-get install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      docker.io \
      docker-compose-v2 \
      gnupg \
      lsb-release

    sudo add-apt-repository -y ppa:wireshark-dev/stable
    echo "wireshark-common wireshark-common/install-setuid boolean false" | sudo debconf-set-selections

    sudo DEBIAN_FRONTEND=noninteractive apt-get update && sudo apt-get install -y \
        wireshark \
        tshark

    sudo systemctl enable docker
    sudo usermod -aG docker $USER

    printf "installing compose"
    until sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose; do
        printf '.'
        sleep 2
    done

    sudo chmod +x /usr/local/bin/docker-compose

    sudo sysctl net.ipv4.conf.all.forwarding=1
    sudo iptables -P FORWARD ACCEPT

    # ignoring the COMMIT_HASH for now
    sudo cp -r /local/repository/etc/oai/cn5g /var/tmp/oai-cn5g
    echo setting up cn node... done.
}

function setup_ran_node {
    # using `build-oai -I --install-optional-packages` results in interactive
    # prompts, so...
    echo installing supporting packages...
    #sudo add-apt-repository -y ppa:ettusresearch/uhd
    sudo apt update && sudo apt install -y \
        iperf3 \
        libboost-dev \
        libforms-dev \
        libforms-bin \
        libuhd-dev \
        numactl \
        zlib1g \
        zlib1g-dev
    sudo uhd_images_downloader
    echo installing supporting packages... done.

    echo cloning and building oai ran...
    cd $SRCDIR
    git clone $OAI_RAN_REPO openairinterface5g
    cd openairinterface5g
    git checkout $COMMIT_HASH
    cd cmake_targets

    ./build_oai -I
    ./build_oai -w USRP $BUILD_ARGS --ninja -C
    echo cloning and building oai ran... done.
}

function configure_nodeb {
    echo configuring nodeb...
    mkdir -p $SRCDIR/etc/oai
    cp -r $ETCDIR/oai/ran/* $SRCDIR/etc/oai/
    LANIF=`ip r | awk '/192\.168\.1\.0/{print $3}'`
    if [ ! -z $LANIF ]; then
      LANIP=`ip r | awk '/192\.168\.1\.0/{print $NF}'`
      echo LAN IFACE is $LANIF IP is $LANIP.. updating nodeb config
      find $SRCDIR/etc/oai/ -type f -exec sed -i "s/LANIF/$LANIF/" {} \;
      echo adding route to CN
      sudo ip route add 192.168.70.128/26 via 192.168.1.1 dev $LANIF
    else
      echo No LAN IFACE.. not updating nodeb config
    fi
    echo configuring nodeb... done.
}

function configure_ue {
    echo configuring ue...
    mkdir -p $SRCDIR/etc/oai
    cp -r $ETCDIR/oai/* $SRCDIR/etc/oai/
    echo configuring ue... done.
}

if [ $NODE_ROLE == "cn" ]; then
    setup_cn_node
elif [ $NODE_ROLE == "nodeb" ]; then
    BUILD_ARGS="--gNB"
    setup_ran_node
    configure_nodeb
elif [ $NODE_ROLE == "ue" ]; then
    BUILD_ARGS="--nrUE"
    setup_ran_node
    configure_ue
fi



touch $SRCDIR/oai-setup-complete
