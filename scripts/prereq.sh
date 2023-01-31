#!/bin/bash

#
#  Thhis script installas all the prerequisite packages that are nneded
#  to build kudu repository located at:
#    git clone https://github.com/harinreddy/kudu.git
#    cd kudu
#    git checkout ppc64le 
#


#subscription-manager register
# subscription-manager repos --enable codeready-builder-for-rhel-8-ppc64le-rpms
#dnf  install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
yum update
yum repolist
yum -y   install install autoconf automake curl cyrus-sasl-devel cyrus-sasl-gssapi \
 cyrus-sasl-plain flex gcc gcc-c++ gdb git java-1.8.0-openjdk-devel \
 krb5-server krb5-workstation libtool make openssl-devel patch pkgconfig \
 redhat-lsb-core rsync unzip vim-common which python2 python2-pip  python2-devel wget  xz  bison
ln -s  /usr/bin/python2.7  /usr/bin/python
ln -s /usr/bin/pip2.7 /usr/bin/pip

yum -y install openblas atlas lapack
yum -y install help2man
 yum -y install graphviz graphviz-devel 

pip install virtualenv
pip install wheel
pip install numpy
#
#  Download and install  doxygen
#
git clone https://github.com/doxygen/doxygen.git
cd doxygen
mkdir build
cd build
cmake -G "Unix Makefiles" ..
make  -j 16
make install
cd ..
rm -rf doxygen
