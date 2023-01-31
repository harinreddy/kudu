#!/bin/bash
set -x
#
#  build-kudu-x86_64.sh  - Builds kudu on x86_64 architecture.
#
git clone https://github.com/harinreddy/kudu.git
cd kudu
export KUDU_ROOT=$PWD
export CC=`which gcc `
export CXX=`which g++`


export JAVA_HOME=$(readlink -f /usr/bin/java | sed "s:/bin/java::")
export PATH=$JAVA_HOME/bin:$PATH
thirdparty/build-if-necessary.sh  > make.tp.log 2>&1
export PATH=$KUDU_ROOT/thirdparty/installed/common/bin:$KUDU_ROOT/thirdparty/installed/uninstrumented/bin/:$PATH
export CLANG=`which clang`
export CLANGXX=`which clang++`
export CC=`which clang`
export CXX=`which clang++`

rm -rf  build/release
mkdir -p build/release
cd build/release

 NO_REBUILD_THIRDPARTY=1  cmake    \
     -Wno-dev -DCMAKE_INSTALL_PREFIX=/usr/local/kudu  -DNO_REBUILD_THIRDPARTY=yes    -DCMAKE_CXX_FLAGS=" -fPIC -Wl,-allow-multiple-definition  " -DCMAKE_BUILD_TYPE=release \
../..

make  -j 32  > build-log 2>&1

ctest -VV -j 32 > ctest-log 2>&1
