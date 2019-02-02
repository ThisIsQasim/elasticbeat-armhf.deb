Elastic.co, as of this writing, does not provide any packages for the ARM architecture. Which is why this script can be used to compile a debian package of filebeat, metricbeat, heartbeat or packetbeat for ARM processors. 

This script works fine on Debian, Ubuntu, CentOS, Fedora and RedHat OSes with golang installed running on an x64 machine. To build an arm debian package, run the following commands and a .deb file will be placed in the user's home directory. Copy the .deb file over to the ARM machine and install with `dpkg -i somebeat.deb`. The compiled packages appear to work on Raspbian and armbian OSes.

    curl -LO https://raw.githubusercontent.com/ThisIsQasim/elasticbeat-armhf.deb/master/setup.sh
    chmod +x ./setup.sh
    ./setup.sh filebeat 6.5.4


Note: Golang-11 or docker is required to compile binary except packetbeat which can only be compiled via docker. dpkg is required to package .deb file (on CentOS/RHEL it is available in the epel repo `yum install -y epel-release`).