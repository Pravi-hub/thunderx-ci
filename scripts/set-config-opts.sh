#!/usr/bin/env bash

set -e

name="${0##*/}"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "${BASH_SOURCE%/*}" && pwd )"}

source ${SCRIPTS_TOP}/lib/util.sh

usage() {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Sets kernel config options from <spec-file>." >&2
	echo "Usage: ${name} [flags] <spec-file> <kernel-config>" >&2
	echo "Option flags:" >&2
	echo "  -h --help          - Show this help and exit." >&2
	echo "  -v --verbose       - Verbose execution." >&2
	echo "Spec File Info:" >&2
	echo "  The spec file contains one kernel option per line.  Lines beginning with '#' (regex '^#') are comments." >&2
	eval "${old_xtrace}"
}

short_opts="hv"
long_opts="help,verbose"

opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${name}" -- "$@")

if [ $? != 0 ]; then
	echo "${name}: ERROR: Internal getopt" >&2
	exit 1
fi

eval set -- "${opts}"

while true ; do
	case "${1}" in
	-h | --help)
		usage=1
		shift
		;;
	-v | --verbose)
		set -x
		verbose=1
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

on_exit() {
	local result=${1}

	echo "${name}: ${result}" >&2
}

trap "on_exit 'Done, failed.'" EXIT

spec="${1}"
config="${2}"

check_file "${spec}" "" "usage"
check_file "${config}" "" "usage"

if [[ ${usage} ]]; then
	usage
	exit 0
fi

cp -f "${config}" "${config}".orig

while read -r update; do
	if [[ -z "${update}" || "${update:0:1}" == '#' ]]; then
		#echo "skip @${update}@"
		continue
	fi

	tok="${update%%=*}"

	if old=$(egrep ".*${tok}[^_].*" ${config}); then
		sed  --in-place "{s/.*${tok}[^_].*/${update}/g}" ${config}
		new=$(egrep ".*${tok}[^_].*" ${config})
		echo "${name}: Update: '${old}' -> '${new}'"
	else
		echo "${update}" >> "${config}"
		echo "${name}: Append: '${update}'"
	fi

done < "${spec}"

diff -u "${config}".orig "${config}" || : >&2

echo "" >&2

trap - EXIT

on_exit 'Done, success.'

