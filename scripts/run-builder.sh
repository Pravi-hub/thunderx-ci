#!/usr/bin/env bash

set -e

name="${0##*/}"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "${BASH_SOURCE%/*}" && pwd )"}

source ${SCRIPTS_TOP}/lib/util.sh

DOCKER_TOP=${DOCKER_TOP:-"$( cd "${SCRIPTS_TOP}/../docker" && pwd )"}
DOCKER_TAG=${DOCKER_TAG:-"$("${DOCKER_TOP}/builder/build-builder.sh" --tag)"}

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Runs a tci container.  If no command is provided, runs an interactive container." >&2
	echo "Usage: ${name} [flags] -- [command] [args]" >&2
	echo "Option flags:" >&2
	echo "  -a --docker-args    - Args for docker run. Default: '${docker_args}'" >&2
	echo "  -h --help           - Show this help and exit." >&2
	echo "  -n --container-name - Container name. Default: '${container_name}'." >&2
	echo "  -s --no-sudoers     - Do not setup sudoers." >&2
	echo "  -t --tag            - Print Docker tag to stdout and exit." >&2
	echo "  -v --verbose        - Verbose execution." >&2
	echo "Args:" >&2
	echo "  command             - Default: '${user_cmd}'" >&2
	echo "Environment:" >&2
	echo "  DOCKER_TAG          - Default: '${DOCKER_TAG}'" >&2
	echo "  TCI_CHECKOUT_SERVER - Default: '${TCI_CHECKOUT_SERVER}'" >&2
	echo "  TCI_CHECKOUT_PORT   - Default: '${TCI_CHECKOUT_PORT}'" >&2
	echo "  TCI_RELAY_SERVER    - Default: '${TCI_RELAY_SERVER}'" >&2
	echo "  TCI_RELAY_PORT      - Default: '${TCI_RELAY_PORT}'" >&2
	echo "  TCI_TFTP_SERVER     - Default: '${TCI_TFTP_SERVER}'" >&2
	echo "  TCI_TFTP_USER       - Default: '${TCI_TFTP_USER}'" >&2
	echo "  TCI_TFTP_ROOT       - Default: '${TCI_TFTP_ROOT}'" >&2
	echo "Examples:" >&2
	echo "  ${name} -v" >&2
	eval "${old_xtrace}"
}

short_opts="a:hn:stv"
long_opts="docker-args:,help,container-name:,no-sudoers,tag,verbose"

opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${name}" -- "$@")

if [ $? != 0 ]; then
	echo "${name}: ERROR: Internal getopt" >&2
	exit 1
fi

eval set -- "${opts}"

while true ; do
	case "${1}" in
	-a | --docker-args)
		docker_args="${2}"
		shift 2
		;;
	-h | --help)
		usage=1
		shift
		;;
	-n | --container-name)
		container_name="${2}"
		shift 2
		;;
	-s | --no-sudoers)
		no_sudoers=1
		shift
		;;
	-t | --tag)
		tag=1
		shift
		;;
	-v | --verbose)
		set -x
		verbose=1
		shift
		;;
	--)
		shift
		user_cmd="${@}"
		break
		;;
	*)
		echo "${name}: ERROR: Internal opts: '${@}'" >&2
		exit 1
		;;
	esac
done

on_exit() {
	local result=${1}

	echo "${name}: ${result}" >&2
}


if [ ${TCI_BUILDER} ]; then
	echo "${name}: ERROR: Already in tci-builder." >&2
	exit 1
fi

docker_extra_args=""

container_name=${container_name:-"tci"}
user_cmd=${user_cmd:-"/bin/bash"}

if [[ -n "${usage}" ]]; then
	usage
	exit 0
fi

if [[ ${tag} ]]; then
	show_tag
	exit 0
fi

trap "on_exit 'Done, failed.'" EXIT

if [[ ! ${TCI_CHECKOUT_SERVER} ]]; then
	echo "${name}: ERROR: TCI_CHECKOUT_SERVER not defined.'" >&2
	usage
	exit 1
fi
if [[ ! ${TCI_RELAY_SERVER} ]]; then
	echo "${name}: ERROR: TCI_RELAY_SERVER not defined.'" >&2
	usage
	exit 1
fi
if [[ ! ${TCI_TFTP_SERVER} ]]; then
	echo "${name}: ERROR: TCI_TFTP_SERVER not defined.'" >&2
	usage
	exit 1
fi

if [[ ! ${SSH_AUTH_SOCK} ]]; then
	echo "${name}: ERROR: SSH_AUTH_SOCK not defined.'" >&2
fi

if [[ $(echo "${docker_args}" | egrep ' -w ') ]]; then
	docker_extra_args+=" -v $(pwd):/work -w /work"
fi

if [[ ! ${no_sudoers} ]]; then
	docker_extra_args+=" \
	-u $(id --user --real):$(id --group --real) \
	-v /etc/group:/etc/group:ro \
	-v /etc/passwd:/etc/passwd:ro \
	-v /etc/shadow:/etc/shadow:ro \
	-v /dev:/dev"
fi

add_server() {
	local server=${1}
	local addr

	if ! is_ip_addr ${server}; then
		find_addr addr "/etc/hosts" ${server}
		docker_extra_args+=" --add-host ${server}:${addr}"
	fi
}

add_server ${TCI_CHECKOUT_SERVER}
add_server ${TCI_RELAY_SERVER}
add_server ${TCI_TFTP_SERVER}

if egrep '127.0.0.53' /etc/resolv.conf; then
	docker_extra_args+=" --dns 127.0.0.53"
fi

eval "docker run \
	--rm \
	-it \
	 --device /dev/kvm \
	 --privileged \
	--network host \
	--name ${container_name} \
	--hostname ${container_name} \
	--add-host ${container_name}:127.0.0.1 \
	-v ${SSH_AUTH_SOCK}:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent \
	-e TCI_CHECKOUT_SERVER \
	-e TCI_CHECKOUT_PORT \
	-e TCI_RELAY_SERVER \
	-e TCI_RELAY_PORT \
	-e TCI_TFTP_SERVER \
	-e TCI_TFTP_USER \
	-e TCI_TFTP_ROOT \
	${docker_extra_args} \
	${docker_args} \
	${DOCKER_TAG} \
	${user_cmd}"

trap - EXIT
on_exit 'Done, success.'
