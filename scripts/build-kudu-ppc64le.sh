#!/bin/bash
set -x
#
#  build-kudu-ppc64le.sh  - Builds kudu on ppc64le architecture.
#
#  The follwoing two steps are added so that the build on ppc64le can compplete.
#  1) Replace
#        ./src/kudu/gutil/linux_syscall_support.h with  gperftools-2.8.1/src/base/linux_syscall_support.h  
#
#  2) Replace
#        ppc_wrappers in clang header libraries located in thridparty packges with 
# 		src/kudu/util/ppc_wrappers
#
#git clone https://github.com/harinreddy/kudu.git
#cd kudu
#git checkout ppc64le
export KUDU_ROOT=$PWD
#export CLANG=`which clang`
#export CLANGXX=`which clang++`
#export CC=`which clang`
#export CXX=`which clang++`
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

#
# ./src/kudu/gutil/linux_syscall_support.h is not ported to ppc64le
#   gperftools-2.8.1/src/base/linux_syscall_support.h  is ported to ppc64le
#  replace ./src/kudu/gutil/linux_syscall_support.h with gperftools-2.8.1/src/base/linux_syscall_support.h
#

wget https://github.com/gperftools/gperftools/releases/download/gperftools-2.8.1/gperftools-2.8.1.tar.gz
tar -xvfgperftools-2.8.1.tar.gz
for lss in ` find gperftools-2.8.1 -name linux_syscall_support.h`; do cp  -rf $lss $KUDU_ROOT/src/kudu/gutil/linux_syscall_support.h; done
rm -rf gperftools-2.8.1  gperftools-2.8.1.tar.gz



#
#   Replace
#        ppc_wrappers in clang header libraries located in thridparty packges with
#               src/kudu/util/ppc_wrappers
#
 for  ppc_wrapper in `find $KUDU_ROOT/thirdparty -name ppc_wrappers`; do cp -rf $KUDU_ROOT/src/kudu/util/ppc_wrappers/*  $ppc_wrapper/; done

rm -rf  build/release
mkdir -p build/release
cd build/release

 NO_REBUILD_THIRDPARTY=1  cmake    \
     -Wno-dev -DCMAKE_INSTALL_PREFIX=/usr/local/kudu  -DNO_REBUILD_THIRDPARTY=yes    -DCMAKE_CXX_FLAGS=" -fPIC -mcpu=power9  -Wl,-allow-multiple-definition -v   -Wno-dev -DNO_WARN_X86_INTRINSICS " -DCMAKE_BUILD_TYPE=release \
../..

make  -j 32  > build-log 2>&1

ctest -VV -j 32 > ctest-log 2>&1
