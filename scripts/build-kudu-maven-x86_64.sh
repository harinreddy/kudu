#!/bin/bash
#
#   build-kudu-maven-x86_64.sh - Installs  the following maven artifacts for x86_64
#         - kudu-client
#         - kudu-test-utils
#
#   This script creates the maven artifact jar file for  kudu-client and kudu-test-utils
#   1) install later version of maven; 
#      export PATH=/usr/local/maven/apache-maven-3.8.6/bin/:$PATH
#   2) install open-jdk-11
#      Ex: JAVA_HOME=$(readlink -f /usr/lib/jvm/java-11-openjdk-11.0.16.1.1-1.el8_6.x86_64/bin/java   | sed "s:/bin/java::")
#	export PATH=$JAVA_HOME/bin:$PATH
#   
#
#    set  KUDU_ROOT to the top level of the kudu source directory 
#    Example: 
#    cd $HOME
#    git clone https://github.com/harinreddy/kudu.git
#    export KUDU_ROOT=$HOME/kudu
#
set -x
#git clone https://github.com/harinreddy/kudu.git
#cd kudu

export KUDU_ROOT=$HOME/kudu

export JAVA_HOME=$(readlink -f /usr/lib/jvm/java-11-openjdk-11.0.16.1.1-1.el8_6.x86_64/bin/java   | sed "s:/bin/java::")  
export PATH=$JAVA_HOME/bin:$PATH

export PATH=/usr/local/maven/apache-maven-3.8.6/bin/:$PATH

cd $KUDU_ROOT/java


VERSION=`cut -d "-" -f1  $KUDU_ROOT/version.txt`
echo $VERSION > $KUDU_ROOT/version.txt

./gradlew  :kudu-client:assemble
./gradlew  :kudu-test-utils:assemble

mvn install:install-file \
   -Dfile=` ls -dF  $KUDU_ROOT/java//kudu-client/build/libs/kudu-client-$VERSION.jar `  \
   -DgroupId=org.apache.kudu  \
   -DartifactId=kudu-client \
   -Dversion=`cut -d "-" -f1  $KUDU_ROOT/version.txt ` \
   -Dpackaging=jar \
   -DgeneratePom=true


mvn install:install-file \
   -Dfile=` ls -dF  $KUDU_ROOT/java//kudu-test-utils/build/libs/kudu-test-utils-$VERSION.jar `  \
   -DgroupId=org.apache.kudu  \
   -DartifactId=kudu-test-utils \
   -Dversion=`cut -d "-" -f1  $KUDU_ROOT/version.txt ` \
   -Dpackaging=jar \
   -DgeneratePom=true


#
#   From top level kudu source 
#


#mvn install:install-file \
#   -Dfile=` ls -dF $KUDU_ROOT/build/mini-cluster/kudu-binary-*.jar` \
#   -DgroupId=org.apache.kudu \
#   -DartifactId=kudu-binary \
#   -Dversion=`cut -d "-" -f1  $KUDU_ROOT/version.txt ` \
#   -Dclassifier=linux-x86_64 \
#   -Dpackaging=jar \
#   -DgeneratePom=true


