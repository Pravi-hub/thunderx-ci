#!/usr/bin/env bash

set -e

name="$(basename ${0})"

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Enter tci-jenkins.server container." >&2
	echo "Usage: ${name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -c --clean          - Clean kernel rootfs files." >&2
	echo "  -h --help           - Show this help and exit." >&2
	echo "  -v --verbose        - Verbose execution." >&2
	eval "${old_xtrace}"
}

short_opts="chv"
long_opts="clean,help,verbose"

opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${name}" -- "$@")

if [ $? != 0 ]; then
	echo "${name}: ERROR: Internal getopt" >&2
	exit 1
fi

eval set -- "${opts}"

while true ; do
	case "${1}" in
	-c | --clean)
		clean=1
		shift
		;;
	-h | --help)
		usage=1
		shift
		;;
	-v | --verbose)
		set -x
		verbose=1
		export PS4='\[\033[0;33m\]+${BASH_SOURCE##*/}:${LINENO}: \[\033[0;37m\]'
		shift
		;;
	--)
		shift
		break
		;;
	*)
		echo "${name}: ERROR: Internal opts: '${@}'" >&2
		exit 1
		;;
	esac
done

if [[ ${usage} ]]; then
	usage
	exit 0
fi

kernel_rootfs=/var/jenkins_home/workspace/tci/kernel/kernel-test/arm64-debian-buster.rootfs

if [[ ${clean} ]]; then
	exec docker exec --privileged tci-jenkins.service sudo rm -rf ${kernel_rootfs}
else
	exec docker exec -it --privileged tci-jenkins.service /bin/bash
fi

