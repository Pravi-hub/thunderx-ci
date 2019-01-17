#!/usr/bin/env bash

set -e

name="$(basename $0)"
DOCKER_TOP=${DOCKER_TOP:-"$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"}

project_name="builder"
project_from="debian"
project_description="Builds a docker image that contains tools for ThunderX CI."

PROJECT_TOP="${DOCKER_TOP}/${project_name}"
VERSION=${VERSION:-"1"}
DOCKER_NAME=${DOCKER_NAME:-"tci-builder"}

docker_build_setup() {
	true
}

host_install_extra() {
	true
}

source ${DOCKER_TOP}/build-common.sh
