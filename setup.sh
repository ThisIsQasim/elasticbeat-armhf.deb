BEAT=${1:-filebeat}
VERSION=${2:-6.5.4}
S3BUCKET=${3:-}
BUILDPATH=/tmp/armbeat
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
        echo "Build path already exists. Clean it up or specify an empty path"
        exit 1
    fi

    check_deps
    export GOPATH=${BUILDPATH}/go GOARCH=arm
    mkdir -p ${GOPATH}
}

function compile_beat(){
    if [ "${USEDOCKER}" == "true" ]; then
        docker_compile_beat
    else
        go get github.com/elastic/beats
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
    sed -i -e 's/amd64/armhf/g' deb/DEBIAN/control
    cp ${GOPATH}/src/github.com/elastic/beats/${BEAT}/${BEAT} deb/usr/share/${BEAT}/bin/${BEAT}
    dpkg-deb -b deb ${BEAT}-oss-${VERSION}-armhf.deb
}

function move_package(){
    if [ -n "${S3BUCKET}" ]; then
        SKIPMOVE=true
        s3cmd put -P ${BUILDPATH}/${BEAT}-oss-${VERSION}-armhf.deb s3://${S3BUCKET}/${BEAT}/${BEAT}-oss-${VERSION}-armhf.deb ||\
        ( SKIPMOVE=false && echo "S3 upload failed" )
    else
        SKIPMOVE=false
        echo "Package will not be uploaded to S3."
    fi

    if [ "${SKIPMOVE}" != "true" ]; then
        mv ${BUILDPATH}/${BEAT}-oss-${VERSION}-armhf.deb ~/
        cd ~
        echo "Find the package at $(pwd)/${BEAT}-oss-${VERSION}-armhf.deb"
    fi
}

function cleanup(){
    rm -rf ${BUILDPATH}
    docker stop beat-builder
    docker rm -f beat-builder
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
    if [ "${BEAT}" == "packetbeat" ]; then
        cat > $GOPATH/buildscript << EOF
dpkg --add-architecture armhf
apt-get update
apt-get install -y libc6-armel-cross libc6-dev-armel-cross binutils-arm-linux-gnueabi libncurses5-dev 
apt-get install -y gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf
apt-get install -y libpcap0.8-dev:armhf
export CC=arm-linux-gnueabihf-gcc CGO_ENABLED=1
EOF
    fi

    cat >> $GOPATH/buildscript << EOF
export GOARCH=arm
go get github.com/elastic/beats
cd /go/src/github.com/elastic/beats/

echo "Checking out version ${VERSION}"
git checkout -q v${VERSION} || ( echo "version not found" && exit 1 )
cd /go/src/github.com/elastic/beats/${BEAT}
make || ( echo "Build failed" && exit 1 )
EOF

    docker run --name beat-builder -v $GOPATH:/go -it golang:1.11.5-stretch bash /go/buildscript

    if [ $? != 0 ]; then
        echo "Docker run failed. Make sure you can spin up containers and selinux isn't messing around"
        exit 1
    fi
}

main