Elastic.co, as of this writing, does not provide any packages for the ARM architecture. Which is why this script can be used to compile a debian package of filebeat, metricbeat or heartbeat for ARM processors. 

This script works fine on Debian, Ubuntu, CentOS, Fedora and RedHat machines with golang installed running on x64 architecture. Run the following commands and a .deb file will be placed in the user's home directory. Copy the .deb file over to the ARM machine and install with `dpkg -i filename.deb`. The compiled packages appear to work on Raspbian and armbian OSes. Cheers!

    curl -LO https://raw.githubusercontent.com/ThisIsQasim/elasticbeat-armhf.deb/master/setup.sh
    chmod +x ./setup.sh
    ./setup.sh filebeat 6.5.4
