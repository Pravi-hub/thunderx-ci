#!/bin/bash

if [[ ! -f /.dockerenv || ! ${TCI_JENKINS} ]]; then
	echo "ERROR: Must be run from inside tci-jenkins container."
	exit -1
fi

set -ex

SRC=${SRC:-'/var/tci-store'}
DEST=${DEST:-'/var/jenkins_home/workspace/tci/kernel/kernel-test-cache/bootstrap'}

mkdir -p ${DEST}

if [[ -d ${SRC}/bootstrap.known-good ]]; then
	cp -avf ${SRC}/bootstrap.known-good/* ${DEST}/
	exit 0
fi

if [[ -f ${SRC}/bootstrap.known-good.tar ]]; then
	tar -C ${DEST}/ --strip-components=1 -xvf ${SRC}/bootstrap.known-good.tar
	exit 0
fi

if [[ -f ${SRC}/bootstrap.known-good.tar.gz ]]; then
	tar -C ${DEST}/ --strip-components=1 -xvf ${SRC}/bootstrap.known-good.tar.gz
	exit 0
fi

ls -lh ${SRC}

echo "WARNING: No bootstrap.known-good sources found."
exit 1
