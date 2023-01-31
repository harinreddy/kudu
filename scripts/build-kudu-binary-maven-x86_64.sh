#!/bin/bash
#
#   build-kudu-binary-maven-x86_64.sh  - Builds kudu-binary maven artifact for x86_64 architecture.
#
#
#git clone https://github.com/harinreddy/kudu.git
#cd kudu

export KUDU_ROOT=$PWD
#export CLANG=`which clang`
#export CLANGXX=`which clang++`
#export CC=`which clang`
#export CXX=`which clang++`
export CC=`which gcc `
export CXX=`which g++`


export JAVA_HOME=$(readlink -f /usr/bin/java | sed "s:/bin/java::")
export PATH=$JAVA_HOME/bin:$PATH
#thirdparty/build-if-necessary.sh  > make.tp.log 2>&1
export PATH=$KUDU_ROOT/thirdparty/installed/common/bin:$KUDU_ROOT/thirdparty/installed/uninstrumented/bin/:$PATH
export LD_LIBRARY_PATH=$KUDU_ROOT/thirdparty/installed/common/lib:$KUDU_ROOT/thirdparty/installed/uninstrumented/lib
export CLANG=`which clang`
export CLANGXX=`which clang++`
export CC=`which clang`
export CXX=`which clang++`


#
#  Build kudu-binary artificat
#
export NO_REBUILD_THIRDPARTY=1
$KUDU_ROOT/build-suppoort/mini-cluster/build_mini_cluster_binaries.sh > build.log 2>&1


#
#  Install kudu-binary artifact in $HOME/.m2
#
#   This script creates the maven artifact jar file for  kudu-client and kudu-test-utils
#   1) install later version of maven;
#      export PATH=/usr/local/maven/apache-maven-3.8.6/bin/:$PATH
#   2) install open-jdk-11
#      Ex: JAVA_HOME=$(readlink -f /usr/lib/jvm/java-11-openjdk-11.0.16.1.1-1.el8_6.x86_64/bin/java   | sed "s:/bin/java::")
#       export PATH=$JAVA_HOME/bin:$PATH
#
export PATH=/usr/local/maven/apache-maven-3.8.6/bin/:$PATH
export RJAVA_HOME=$(readlink -f /usr/lib/jvm/java-11-openjdk-11.0.16.1.1-1.el8_6.x86_64/bin/java  | sed "s:/bin/java::")
export PATH=$JAVA_HOME/bin:$PATH

VERSION=`cut -d "-" -f1  $KUDU_ROOT/version.txt`
echo $VERSION > $KUDU_ROOT/version.txt

mvn install:install-file \
   -Dfile=` ls -dF $KUDU_ROOT/build/mini-cluster/kudu-binary-*.jar` \
   -DgroupId=org.apache.kudu \
   -DartifactId=kudu-binary \
   -Dversion=`cut -d "-" -f1  $KUDU_ROOT/version.txt ` \
   -Dclassifier=linux-x86_64 \
   -Dpackaging=jar \
   -DgeneratePom=true


