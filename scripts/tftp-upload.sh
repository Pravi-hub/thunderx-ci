#!/usr/bin/env bash

set -e

name="$(basename ${0})"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"}

source ${SCRIPTS_TOP}/lib/util.sh

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Upload files to tftp server." >&2
	echo "Usage: ${name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help           - Show this help and exit." >&2
	echo "  -i --initrd         - Initrd image. Default: '${initrd}'." >&2
	echo "  -k --kernel         - Kernel image. Default: '${kernel}'." >&2
	echo "  -n --no-known-hosts - Do not setup known_hosts file. Default: '${no_known_hosts}'." >&2
	echo "  -s --ssh-login-key  - SSH login private key file. Default: '${ssh_login_key}'." >&2
	echo "  -v --verbose        - Verbose execution." >&2
	echo "  --tftp-triple       - tftp triple.  File name or 'user:server:root'. Default: '${tftp_triple}'." >&2
	echo "  --tftp-dest         - tftp destination directory relative to tftp-root.  Default: '${tftp_dest}'." >&2
	eval "${old_xtrace}"
}

short_opts="hi:k:ns:v"
long_opts="help,initrd:,kernel:,no-known-hosts,ssh-login-key:,tftp-dest:,tftp-triple:,verbose"

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
	-i | --initrd)
		initrd="${2}"
		shift 2
		;;
	-k | --kernel)
		kernel="${2}"
		shift 2
		;;
	-n | --no-known-hosts)
		no_known_hosts=1
		shift
		;;
	-s | --ssh-login-key)
		ssh_login_key="${2}"
		shift 2
		;;
	-t | --tftp-triple)
		tftp_triple="${2}"
		shift 2
		;;
	-t | --tftp-dest)
		tftp_dest="${2}"
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

tftp_kernel="tci-kernel"
tftp_initrd="tci-initrd"
tftp_login_key="tci-login-key"

if [[ ${usage} ]]; then
	usage
	exit 0
fi

if [[ -f "${tftp_triple}" ]]; then
	tftp_triple=$(cat ${tftp_triple})
fi

if [[ ${tftp_triple} ]]; then
	echo "${name}: INFO: tftp triple: '${tftp_triple}'" >&2

	tftp_user="$(echo ${tftp_triple} | cut -d ':' -f 1)"
	tftp_server="$(echo ${tftp_triple} | cut -d ':' -f 2)"
	tftp_root="$(echo ${tftp_triple} | cut -d ':' -f 3)"
else
	tftp_user=${TCI_TFTP_USER:-"tci-jenkins"}
	tftp_server=${TCI_TFTP_SERVER:-"tci-tftp"}
	tftp_root=${TCI_TFTP_ROOT:-"/var/tftproot"}
fi

check_opt 'tftp-dest' ${tftp_dest}

echo "${name}: INFO: tftp user:   '${tftp_user}'" >&2
echo "${name}: INFO: tftp server: '${tftp_server}'" >&2
echo "${name}: INFO: tftp root:   '${tftp_root}'" >&2
echo "${name}: INFO: tftp dest:   '${tftp_dest}'" >&2

check_opt 'kernel' ${kernel}
check_file "${kernel}"

check_opt 'initrd' ${initrd}
check_file "${initrd}"

check_opt 'ssh-login-key' ${ssh_login_key}
check_file "${ssh_login_key}"

on_exit() {
	local result=${1}

	if [[ ${tmp_dir} && -d ${tmp_dir} ]]; then
		rm -rf ${tmp_dir}
	fi

	echo "${name}: ${result}" >&2
}

trap "on_exit 'Done, failed.'" EXIT

#if [[ ${no_known_hosts} ]]; then
#	ssh_extra_args+="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
#else
#	if ! ssh-keygen -F ${tftp_server} &> /dev/null; then
#		tmp_dir="$(mktemp --tmpdir --directory ${name}.XXXX)"
#		known_hosts_file="${tmp_dir}/known_hosts"
#
#		ssh-keyscan ${tftp_server} >> ${known_hosts_file}
#		ssh_extra_args+="-o UserKnownHostsFile=${known_hosts_file}"
#	fi
#fi

ssh_extra_args+="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

if [[ ${verbose} ]]; then
	ssh_extra_args+=" -v"
	#ssh ${ssh_extra_args} ${tftp_user}@${tftp_server} ls -lh ${tftp_root}/${tftp_dest}
fi

scp ${ssh_extra_args} ${initrd} ${tftp_user}@${tftp_server}:${tftp_root}/${tftp_dest}/${tftp_initrd}
scp ${ssh_extra_args} ${kernel} ${tftp_user}@${tftp_server}:${tftp_root}/${tftp_dest}/${tftp_kernel}
scp ${ssh_extra_args} ${ssh_login_key} ${tftp_user}@${tftp_server}:${tftp_root}/${tftp_dest}/${tftp_login_key}

#if [[ ${verbose} ]]; then
#	ssh ${ssh_extra_args} ${tftp_user}@${tftp_server} ls -lh ${tftp_root}/${tftp_dest}
#fi

trap - EXIT

on_exit 'Done, success.'
