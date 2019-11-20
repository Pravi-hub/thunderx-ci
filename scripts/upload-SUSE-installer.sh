#!/usr/bin/env bash

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Upload SUSE netboot installer to tftp server." >&2
	echo "Usage: ${name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -c --config-file - Config file. Default: '${config_file}'." >&2
	echo "  -h --help        - Show this help and exit." >&2
	echo "  -o --host        - Target host. Default: '${host}'." >&2
	echo "  -r --release     - Debian release. Default: '${release}'." >&2
	echo "  -s --tftp-server - TFTP server. Default: '${tftp_server}'." >&2
	echo "  -t --type        - Release type {$(clean_ws ${types})}." >&2
	echo "                     Default: '${type}'." >&2
	echo "  -v --verbose     - Verbose execution." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="c:hors:t:v"
	local long_opts="config-file:,help,host:,release:,tftp-server:,type:,verbose"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		case "${1}" in
		-c | --config-file)
			config_file="${2}"
			shift 2
			;;
		-h | --help)
			usage=1
			shift
			;;
		-o | --host)
			host="${2}"
			shift 2
			;;
		-r | --release)
			release="${2}"
			shift 2
			;;
		-s | --tftp-server)
			tftp_server="${2}"
			shift 2
			;;
		-t | --type)
			type="${2}"
			shift 2
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
}

on_exit() {
	local result=${1}

	if [[ -d ${iso_mnt} ]]; then
		sudo umount ${iso_mnt} || :
		rm -rf ${iso_mnt} || :
		iso_mnt=''
	fi

	echo "${name}: Done: ${result}" >&2
}

download_SUSE_files() {
	local cmd
	local dir
	local ssh_no_check="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

	wget --no-verbose -O ${type}.iso ${iso_url}

	iso_mnt="$(mktemp --tmpdir --directory openSUSE-iso-mnt.XXXX)"
	sudo mount -o rw,uid=$(id -u),gid=$(id -g)  ${type}.iso ${iso_mnt}

	if [[ ${tftp_server} == "localhost" ]]; then
		cmd=''
		dir="$(pwd)"
		cp ${JENKINS_TOP}/jobs/distro/${type}/autoinst.xml ./SUSE_autoinst.xml
		sudo cp ${iso_mnt}/boot/aarch64/linux ${dir}
		sudo cp ${iso_mnt}/boot/aarch64/initrd ${dir}

	else
		cmd="ssh ${tftp_server} ${ssh_no_check} "
		dir="/var/tftproot/${host}"
		scp ${ssh_no_check} ${JENKINS_TOP}/jobs/distro/${type}/autoinst.xml ${tftp_server}:${dir}/SUSE_autoinst.xml
		scp ${ssh_no_check} ${iso_mnt}/boot/aarch64/linux ${tftp_server}:${dir}
		scp ${ssh_no_check} ${iso_mnt}/boot/aarch64/initrd ${tftp_server}:${dir}
	fi

	if [[ -d ${iso_mnt} ]]; then
		sudo umount ${iso_mnt} || :
		rm -rf ${iso_mnt} || :
		iso_mnt=''
	fi


	set +e

	${cmd} env dir=${dir}  bash -s <<'EOF'

set -ex

if [[ -f ${dir}/SUSE_initrd \
	&& -f ${dir}/SUSE_kernel ]]; then
	mv -f ${dir}/SUSE_initrd ${dir}/SUSE_initrd.old
	mv -f ${dir}/SUSE_kernel ${dir}/SUSE_kernel.old
fi

mv  ${dir}/linux ${dir}/SUSE_kernel
mv  ${dir}/initrd ${dir}/SUSE_initrd


sum1=$(md5sum "${dir}/SUSE_initrd" "${dir}/SUSE_kernel" | cut -f 1 -d ' ')
sum2=$(md5sum "${dir}/SUSE_initrd.old" "${dir}/SUSE_kernel.old" | cut -f 1 -d ' ')

set +e

if [[ "${sum1}" != "${sum2}" ]]; then
	exit 0
else
	exit 1
fi


EOF

return ${?}
}


#===============================================================================
# program start
#===============================================================================

name="${0##*/}"
SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "${BASH_SOURCE%/*}" && pwd )"}
JENKINS_TOP=${DOCKER_TOP:-"$( cd "${SCRIPTS_TOP}/../jenkins" && pwd )"}


trap "on_exit 'failed.'" EXIT
set -e

source ${SCRIPTS_TOP}/lib/util.sh

process_opts "${@}"

config_file="${config_file:-${SCRIPTS_TOP}/upload.conf-sample}"

check_file ${config_file} " --config-file" "usage"
source ${config_file}

if [[ ! ${tftp_server} ]]; then
	echo "${name}: ERROR: No tftp_server entry: '${config_file}'" >&2
	usage
	exit 1
fi

if [[ ! ${host} ]]; then
	echo "${name}: ERROR: No host entry: '${config_file}'" >&2
	usage
	exit 1
fi

types="
	openSUSE
	SUSE
"

type=${type:-"openSUSE"}

case "${type}" in
openSUSE )
	iso_url="http://ftp.neowiz.com/opensuse/ports/aarch64/distribution/leap/15.1/iso/openSUSE-Leap-15.1-NET-aarch64-Build458.3-Media.iso"
	;;	
SUSE)
	echo "${name}: ERROR: No SUSE support yet." >&2
	exit 1
	;;
*)
	echo "${name}: ERROR: Unknown type '${type}'" >&2
	usage
	exit 1
	;;
esac


if [[ -n "${usage}" ]]; then
	usage
	exit 0
fi

download_SUSE_files

result=${?}

set -e


echo "${name}: ${host} files ready on ${tftp_server}." >&2

trap "on_exit 'success.'" EXIT

if [[ ${result} -ne 0 ]]; then
	echo "No new files" >&2
	exit 1
else
	echo "need test" >&2
	exit 0
fi
