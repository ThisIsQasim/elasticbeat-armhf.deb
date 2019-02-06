BEAT=${1:-filebeat}
VERSION=${2:-6.5.4}
S3BUCKET=${3:-}
BUILDPATH=/tmp/armbeat
ARMARCH=armhf
USEDOCKER=false

function main(){

    echo "Setting up build environment"
    setup_builder

    echo "Compiling ${BEAT}"
    compile_beat

    echo "Repackaging ${BEAT}"
    repackage_beat

    echo "Moving ${BEAT}"
    move_package

    echo "Cleaning up"
    cleanup

}

function setup_builder(){
    if [[ "${BEAT}" != "filebeat" && "${BEAT}" != "metricbeat" && "${BEAT}" != "heartbeat" ]]; then
        if [[ "${BEAT}" == "packetbeat" ]]; then
            USEDOCKER=true
            echo -e "Building with docker"
        else
            echo "Not a valid beat name"
            exit 1
        fi
    fi

    if [ -d "${BUILDPATH}" ]; then
        echo "Build path at ${BUILDPATH} already exists. Clean it up or specify an empty path"
        exit 1
    fi

    check_deps

    if [ "${ARMARCH}" == "armel" ]; then
        ARMVERSION=6
    elif [ "${ARMARCH}" == "armhf" ]; then
        ARMVERSION=7
    else
        echo "Please specify a valid arm architecture"
    fi

    export GOPATH=${BUILDPATH}/go GOARCH=arm GOARM=$ARMVERSION
    mkdir -p ${GOPATH}
}

function compile_beat(){
    if [ "${USEDOCKER}" == "true" ]; then
        docker_compile_beat
    else
        go get -v github.com/elastic/beats
        cd ${GOPATH}/src/github.com/elastic/beats/

        echo "Checking out version ${VERSION}"
        git checkout -q v${VERSION} || ( echo "version not found" && exit 1 )
        cd ${GOPATH}/src/github.com/elastic/beats/${BEAT}
        make || ( echo "Build failed" && exit 1 )
    fi
}

function repackage_beat(){
    cd ${BUILDPATH}
    curl -LO https://artifacts.elastic.co/downloads/beats/${BEAT}/${BEAT}-oss-${VERSION}-amd64.deb ||\
    ( echo "The specified version is not released yet." && exit 1 )

    echo "unpacking amd64 package"
    alias cp=cp
    dpkg-deb -R ${BEAT}-oss-${VERSION}-amd64.deb deb
    sed -i -e "s/amd64/${ARMARCH}/g" deb/DEBIAN/control
    cp ${GOPATH}/src/github.com/elastic/beats/${BEAT}/${BEAT} deb/usr/share/${BEAT}/bin/${BEAT}
    dpkg-deb -b deb ${BEAT}-oss-${VERSION}-${ARMARCH}.deb
}

function move_package(){
    if [ -n "${S3BUCKET}" ]; then
        SKIPMOVE=true
        s3cmd put -P ${BUILDPATH}/${BEAT}-oss-${VERSION}-${ARMARCH}.deb s3://${S3BUCKET}/${BEAT}/${BEAT}-oss-${VERSION}-${ARMARCH}.deb ||\
        ( SKIPMOVE=false && echo "S3 upload failed" )
    else
        SKIPMOVE=false
        echo "Package will not be uploaded to S3."
    fi

    if [ "${SKIPMOVE}" != "true" ]; then
        mv ${BUILDPATH}/${BEAT}-oss-${VERSION}-${ARMARCH}.deb ~/
        cd ~
        echo "Find the package at $(pwd)/${BEAT}-oss-${VERSION}-${ARMARCH}.deb"
    fi
}

function cleanup(){
    if [ "${USEDOCKER}" == "true" ]; then
        docker stop beat-builder
        docker rm -f beat-builder
    fi

    rm -rf ${BUILDPATH}
}

function check_deps(){
    if [ "${USEDOCKER}" == "true" ]; then
        if [ -z "$(which docker)" ]; then
            echo "docker not installed! Please install Docker first"
            exit 1
        fi
    else
        if [ -z "$(which go)" ]; then
            echo "Go not installed! Please install go first"
            exit 1
        fi
    fi

    if [ -z "$(which dpkg-deb)" ]; then
        echo "dpkg-deb not found. Should have been there if running on Debian"
        echo "Checking if Enterprise Linux"
        /usr/bin/rpm -q -f /usr/bin/rpm >/dev/null 2>&1
        if [ $? == 0 ]; then
            echo "Enterprise Linux found. Installing dpkg-deb"
            sudo yum install -y dpkg
            if [ $? != 0 ]; then
                echo "Install failed. dpkg-deb is required for this to work"
                exit 1
            fi
        else
            echo "Don't know what you are running but dpkg-deb is required for this to work"
            exit 1
        fi
    fi    

}

function docker_compile_beat(){
    cat >> $GOPATH/buildscript << EOF
export GOARCH=arm GOARM=${ARMVERSION}
go get -v github.com/elastic/beats
cd /go/src/github.com/elastic/beats/

echo "Checking out version ${VERSION}"
git checkout -q v${VERSION} || ( echo "version not found" && exit 1 )
cd /go/src/github.com/elastic/beats/${BEAT}
make || ( echo "Build failed" && exit 1 )
EOF

    if [ "${BEAT}" == "packetbeat" ]; then

        if [ "${ARMARCH}" == "armel" ]; then
            cat > $BUILDPATH/Dockerfile << EOF
FROM golang:1.11.5-stretch
RUN apt-get install -y libc6-armel-cross libc6-dev-armel-cross libncurses5-dev flex bison
RUN apt-get install -y binutils-arm-linux-gnueabi gcc-arm-linux-gnueabi g++-arm-linux-gnueabi
RUN cd / &&\
    curl -LO https://s3.amazonaws.com/beats-files/deps/libpcap-1.8.1.tar.gz &&\
    tar xvf libpcap-1.8.1.tar.gz &&\
    rm -f libpcap-1.8.1.tar.gz &&\
    cd libpcap-1.8.1 &&\
    export CC=arm-linux-gnueabi-gcc &&\
    ./configure --host=arm-linux-gnueabi --with-pcap=linux --enable-usb=no --enable-bluetooth=no --enable-dbus=no &&\
    make
ENV CC=arm-linux-gnueabi-gcc CGO_ENABLED=1 CGO_LDFLAGS="-L/libpcap-1.8.1 -lpcap" CGO_CFLAGS="-I /libpcap-1.8.1"
EOF
        else
            cat > $BUILDPATH/Dockerfile << EOF
FROM golang:1.11.5-stretch
RUN apt-get install -y libc6-armhf-cross libc6-dev-armhf-cross libncurses5-dev flex bison
RUN apt-get install -y binutils-arm-linux-gnueabihf gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf
RUN cd / &&\
    curl -LO https://s3.amazonaws.com/beats-files/deps/libpcap-1.8.1.tar.gz &&\
    tar xvf libpcap-1.8.1.tar.gz &&\
    rm -f libpcap-1.8.1.tar.gz &&\
    cd libpcap-1.8.1 &&\
    export CC=arm-linux-gnueabihf-gcc &&\
    ./configure --host=arm-linux-gnueabihf --with-pcap=linux --enable-usb=no --enable-bluetooth=no --enable-dbus=no &&\
    make
ENV CC=arm-linux-gnueabihf-gcc CGO_ENABLED=1 CGO_LDFLAGS="-L/libpcap-1.8.1 -lpcap" CGO_CFLAGS="-I /libpcap-1.8.1"
EOF
        fi

        docker build -t packetbeat-builder-${ARMARCH} $BUILDPATH
        docker run --name beat-builder -v $GOPATH:/go -it packetbeat-builder-${ARMARCH} bash /go/buildscript

    else
        docker run --name beat-builder -v $GOPATH:/go -it golang:1.11.5-stretch bash /go/buildscript
    fi

    if [ $? != 0 ]; then
        echo "Docker run failed. Make sure you can spin up containers and selinux isn't messing around"
        exit 1
    fi
}

main
