#!/bin/bash
#
#   build-kudu-binary-maven-ppc64le.sh  - Builds kudu-binary maven artifact for ippc64le architecture.
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


#export JAVA_HOME=$(readlink -f /usr/bin/java | sed "s:/bin/java::")
#export PATH=$JAVA_HOME/bin:$PATH
thirdparty/build-if-necessary.sh  > make.tp.log 2>&1
export PATH=$KUDU_ROOT/thirdparty/installed/common/bin:$KUDU_ROOT/thirdparty/installed/uninstrumented/bin/:$PATH
export LD_LIBRARY_PATH=$KUDU_ROOT/thirdparty/installed/common/lib:$KUDU_ROOT/thirdparty/installed/uninstrumented/lib
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


#
#  Build kudu-binary artificat
#
export NO_REBUILD_THIRDPARTY=1
$KUDU_ROOT/build-support/mini-cluster/build_mini_cluster_binaries.sh > build.log 2>&1


#
#  Install kudu-binary artifact in $HOME/.m2
#
#   This script creates the maven artifact jar file for  kudu-client and kudu-test-utils
#   1) install later version of maven;
#      export PATH=/usr/local/maven/apache-maven-3.8.6/bin/:$PATH
#   2) install open-jdk-11
#      Ex: JAVA_HOME=$(readlink -f /usr/lib/jvm/java-11-openjdk-11.0.16.1.1-1.el8_6.ppc64le/bin/java  | sed "s:/bin/java::")
#       export PATH=$JAVA_HOME/bin:$PATH
#
export PATH=/usr/local/maven/apache-maven-3.8.6/bin/:$PATH
export JAVA_HOME=$(readlink -f /usr/lib/jvm/java-11-openjdk-11.0.16.1.1-1.el8_6.ppc64le/bin/java  | sed "s:/bin/java::")
export PATH=$JAVA_HOME/bin:$PATH

VERSION=`cut -d "-" -f1  $KUDU_ROOT/version.txt`
echo $VERSION > $KUDU_ROOT/version.txt

mvn install:install-file \
   -Dfile=` ls -dF $KUDU_ROOT/build/mini-cluster/kudu-binary-*.jar` \
   -DgroupId=org.apache.kudu \
   -DartifactId=kudu-binary \
   -Dversion=`cut -d "-" -f1  $KUDU_ROOT/version.txt ` \
   -Dclassifier=linux-ppcle_64 \
   -Dpackaging=jar \
   -DgeneratePom=true


