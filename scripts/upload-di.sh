#!/usr/bin/env bash

set -e

name="${0##*/}"
TOP="$(cd "${BASH_SOURCE%/*}" && pwd)"

clean_ws() {
	local in="$*"

	shopt -s extglob
	in="${in//+( )/ }" in="${in# }" in="${in% }"
	echo -n "$in"
}

check_file() {
	local src="${1}"
	local msg="${2}"
	local usage="${3}"

	if [[ ! -f "${src}" ]]; then
		echo -e "${name}: ERROR: File not found${msg}: '${src}'" >&2
		[[ -z "${usage}" ]] || usage
		exit 1
	fi
}

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Upload Debian netboot installer to tftp server." >&2
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

short_opts="c:hors:t:v"
long_opts="config-file:,help,host:,release:,tftp-server:,type:,verbose"

opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${name}" -- "$@")

if [ $? != 0 ]; then
	echo "${name}: ERROR: Internal getopt" >&2
	exit 1
fi

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

config_file="${config_file:-${TOP}/upload-di.conf}"

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
	buster
	daily
	sid
"

if [[ -n "${usage}" ]]; then
	usage
	exit 0
fi

case "${type}" in
buster)
	release="current"
	files_url="http://ftp.nl.debian.org/debian/dists/buster/main/installer-arm64/${release}/images/netboot/debian-installer/arm64"
	sums_url="http://ftp.nl.debian.org/debian/dists/buster/main/installer-arm64/${release}/images/"
	;;
daily)
	release="daily"
	files_url="https://d-i.debian.org/daily-images/arm64/${release}/netboot/debian-installer/arm64"
	sums_url="https://d-i.debian.org/daily-images/arm64/${release}"
	;;
sid)
	echo "${name}: ERROR: No sid support yet." >&2
	exit 1
	;;
*)
	echo "${name}: ERROR: Unknown type '${type}'" >&2
	usage
	exit 1
	;;
esac

on_exit() {
	local result=${1}

	echo "${name}: ${result}" >&2
}

trap "on_exit 'Done, failed.'" EXIT

ssh ${tftp_server} ls -l /var/tftproot/${host}

ssh ${tftp_server} host=${host} files_url=${files_url} sums_url=${sums_url} 'bash -s' <<'EOF'

set -e

if [[ -f /var/tftproot/${host}/tci-initrd \
	&& -f /var/tftproot/${host}/tci-kernel ]]; then
	mv -f /var/tftproot/${host}/tci-initrd /var/tftproot/${host}/tci-initrd.old
	mv -f /var/tftproot/${host}/tci-kernel /var/tftproot/${host}/tci-kernel.old
fi

wget --no-verbose -O /var/tftproot/${host}/tci-initrd ${files_url}/initrd.gz
wget --no-verbose -O /var/tftproot/${host}/tci-kernel ${files_url}/linux
wget --no-verbose -O /tmp/di-sums ${sums_url}/MD5SUMS

echo "--- initrd ---"
[[ -f /var/tftproot/${host}/tci-initrd.old ]] && md5sum /var/tftproot/${host}/tci-initrd.old
md5sum /var/tftproot/${host}/tci-initrd
cat /tmp/di-sums | egrep 'netboot/debian-installer/arm64/initrd.gz'
echo "--- kernel ---"
[[ -f /var/tftproot/${host}/tci-kernel.old ]] && md5sum /var/tftproot/${host}/tci-kernel.old
md5sum /var/tftproot/${host}/tci-kernel
cat /tmp/di-sums | egrep 'netboot/debian-installer/arm64/linux'
echo "---------"

EOF

trap - EXIT
echo "${name}: ${host} files ready." >&2
on_exit 'Done, success.'
