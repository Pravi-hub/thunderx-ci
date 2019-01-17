#!/usr/bin/env bash

set -e

name="$(basename $0)"
DOCKER_TOP=${DOCKER_TOP:-"$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"}

project_name="jenkins"
project_from="openjdk"
project_description="Builds a docker image that contains Jenkins for ThunderX-CI."

PROJECT_TOP="${DOCKER_TOP}/${project_name}"
VERSION=${VERSION:-"1"}
DOCKER_NAME=${DOCKER_NAME:-"tci-jenkins"}

JENKINS_USER=${JENKINS_USER:-'tci-jenkins'}

if ! getent passwd ${JENKINS_USER} &> /dev/null; then
	echo "${name}: WARNING: User '${JENKINS_USER}' not found." >&2
	echo "${name}: WARNING: Run useradd-jenkins.sh to add." >&2
fi

extra_build_args="\
	--build-arg user=$(id --user --real --name ${JENKINS_USER}) \
	--build-arg uid=$(id --user --real ${JENKINS_USER}) \
	--build-arg group=$(id --group --real --name ${JENKINS_USER}) \
	--build-arg gid=$(id --group --real ${JENKINS_USER}) \
	--build-arg host_docker_gid=$(stat --format=%g /var/run/docker.sock) \
"

docker_build_setup() {
	true
}

host_install_extra() {
	true
}

source ${DOCKER_TOP}/build-common.sh
