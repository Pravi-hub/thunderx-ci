#!/usr/bin/env bash

set -e

name="$(basename ${0})"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"}

source ${SCRIPTS_TOP}/lib/util.sh
source ${SCRIPTS_TOP}/lib/relay.sh

usage() {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Run Fedora install test in QEMU." >&2
	echo "Usage: ${name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -a --arch           - Target architecture. Default: '${target_arch}'." >&2
	echo "  -c --kernel-cmd     - Kernel command line options. Default: '${kernel_cmd}'." >&2
	echo "  -f --hostfwd-offset - QEMU hostfwd port offset. Default: '${hostfwd_offset}'." >&2
	echo "  -h --help           - Show this help and exit." >&2
	echo "  -o --out-file       - stdout, stderr redirection file. Default: '${out_file}'." >&2
	echo "  -s --systemd-debug  - Run systemd with debug options. Default: '${systemd_debug}'." >&2
	echo "  -v --verbose        - Verbose execution." >&2
	echo "  --hda               - QEMU IDE hard disk image hda. Default: '${hda}'." >&2
	echo "  --initrd            - Initrd image. Default: '${initrd}'." >&2
	echo "  --kickstart         - Fedora kickstart file. Default: '${kickstart}'." >&2
	echo "  --kernel            - Kernel image. Default: '${kernel}'." >&2
	echo "  --result-file       - Result file. Default: '${result_file}'." >&2
	echo "  --ssh-key           - SSH private key file. Default: '${ssh_key}'." >&2
	eval "${old_xtrace}"
}

short_opts="a:c:f:ho:sv"
long_opts="arch:,kernel-cmd:,hostfwd-offset:,help,out-file:,systemd-debug,\
verbose,hda:,initrd:,kickstart:,kernel:,result-file:,ssh-key:"

opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${name}" -- "$@")

if [ $? != 0 ]; then
	echo "${name}: ERROR: Internal getopt" >&2
	exit 1
fi

eval set -- "${opts}"

while true ; do
	case "${1}" in
	-a | --arch)
		target_arch=$(get_arch "${2}")
		shift 2
		;;
	-c | --kernel-cmd)
		kernel_cmd="${2}"
		shift 2
		;;
	-f | --hostfwd-offset)
		hostfwd_offset="${2}"
		shift 2
		;;
	-h | --help)
		usage=1
		shift
		;;
	-o | --out-file)
		out_file="${2}"
		shift 2
		;;
	-s | --systemd-debug)
		systemd_debug=1
		shift
		;;
	-v | --verbose)
		set -x
		verbose=1
		shift
		;;
	--hda)
		hda="${2}"
		shift 2
		;;
	--initrd)
		initrd="${2}"
		shift 2
		;;
	--kickstart)
		kickstart="${2}"
		shift 2
		;;
	--kernel)
		kernel="${2}"
		shift 2
		;;
	--result_file)
		result_file="${2}"
		shift 2
		;;
	--ssh-key)
		ssh_key="${2}"
		shift 2
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

host_arch=$(get_arch "$(uname -m)")

target_arch=${target_arch:-"${host_arch}"}
hostfwd_offset=${hostfwd_offset:-"20000"}

if [[ -n "${usage}" ]]; then
	usage
	exit 0
fi

if [[ "${target_arch}" != "arm64" ]]; then
	echo "${name}: ERROR: Unsupported target arch '${target_arch}'.  Must be arm64." >&2
	exit 1
fi

if [[ ! ${kernel} ]]; then
	echo "${name}: ERROR: Must provide --kernel option." >&2
	usage
	exit 1
fi

check_file "${kernel}"

if [[ ! ${initrd} ]]; then
	echo "${name}: ERROR: Must provide --initrd option." >&2
	usage
	exit 1
fi

check_file "${initrd}"

if [[ ! ${hda} ]]; then
	echo "${name}: ERROR: Must provide --hda option." >&2
	usage
	exit 1
fi

check_file "${hda}"

if [[ ! ${kickstart} ]]; then
	echo "${name}: ERROR: Must provide --kickstart option." >&2
	usage
	exit 1
fi

check_file "${kickstart}"

inst_repo="$(egrep '^url[[:space:]]*--url=' ${kickstart} | cut -d '=' -f 2 | sed 's/"//g')"
kernel_cmd="inst.text inst.repo=${inst_repo} inst.ks=hd:vdb:$(basename ${kickstart}) ${kernel_cmd}"

if [[ -z "${out_file}" ]]; then
	out_file="qemu.out"
fi

if [[ -z "${result_file}" ]]; then
	result_file="result.txt"
fi

if [[ -n "${ssh_key}" ]]; then
	check_file ${ssh_key} " ssh-key" "usage"
fi

start_extra_args=''

if [[ ${systemd_debug} ]]; then
	start_extra_args+=' --systemd-debug'
fi

on_exit() {
	local result=${1}

	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo '*** on_exit ***'
	echo "*** result   = ${result}" >&2
	echo "*** qemu_pid = ${qemu_pid}" >&2
	echo "*** up time  = $(sec_to_min ${SECONDS}) min" >&2
	eval "${old_xtrace}"

	if [[ -n "${qemu_pid}" ]]; then
		sudo kill ${qemu_pid} || :
		wait ${qemu_pid}
		qemu_pid=''
	fi

	if [[ -d ${ks_mnt} ]]; then
		sudo umount ${ks_mnt} || :
		rm -rf ${ks_mnt} || :
		ks_mnt=''
	fi
	
	if [[ -f "${ks_img}" ]]; then
		rm -f ${ks_img}
		ks_img=''
	fi

	echo "${name}: ${result}" >&2
}

make_kickstart_img() {
	ks_img="$(mktemp --tmpdir tci-ks-img.XXXX)"
	ks_mnt="$(mktemp --tmpdir --directory tci-ks-mnt.XXXX)"

	local ks_file
	ks_file="${ks_mnt}/$(basename ${kickstart})"

	dd if=/dev/zero of=${ks_img} bs=1M count=1
	mkfs.vfat ${ks_img}

	sudo mount -o rw,uid=$(id -u),gid=$(id -g) ${ks_img} ${ks_mnt}

	cp -v ${kickstart} ${ks_file}

	if [[ -n "${ssh_key}" ]]; then
		sed --in-place "s|@@ssh-keys@@|$(cat ${ssh_key}.pub)|" ${ks_file}
	fi

	echo '' >> ${result_file}
	echo '---------' >> ${result_file}
	echo 'kickstart' >> ${result_file}
	echo '---------' >> ${result_file}
	cat ${ks_file} >> ${result_file}
	echo '---------' >> ${result_file}

	sudo umount ${ks_mnt}
	rmdir ${ks_mnt}
	ks_mnt=''
}

start_qemu_user_networking() {
	ssh_fwd=$(( ${hostfwd_offset} + 22 ))

	echo "${name}: ssh_fwd port = ${ssh_fwd}" >&2

	${SCRIPTS_TOP}/start-qemu.sh \
		--arch="${target_arch}" \
		--kernel-cmd="${kernel_cmd}" \
		--hostfwd-offset="${hostfwd_offset}" \
		--initrd="${initrd}" \
		--kernel="${kernel}" \
		--hda="${hda}" \
		--hdb="${ks_img}" \
		--out-file="${out_file}" \
		--verbose \
		${start_extra_args} \
		</dev/null &> "${out_file}.start" &

	qemu_pid="${!}"
}

trap "on_exit 'Done, failed.'" EXIT

rm -f ${out_file} ${out_file}.start ${result_file}

echo '--------' >> ${result_file}
echo 'printenv' >> ${result_file}
echo '--------' >> ${result_file}
printenv        >> ${result_file}
echo '---------' >> ${result_file}

make_kickstart_img

SECONDS=0
start_qemu_user_networking

sleep 3s

echo '---- start-qemu start ----'
cat ${out_file}.start
echo '---- start-qemu end ----'

if ! kill -0 ${qemu_pid} &> /dev/null; then
	echo "${name}: ERROR: QEMU seems to have quit early." >&2
	exit 1
fi

echo "${name}: Waiting for QEMU exit..." >&2
wait_pid ${qemu_pid} 180
qemu_pid=''

echo "${name}: Boot time: $(sec_to_min ${SECONDS}) min" >&2

trap - EXIT
on_exit 'Done, success.'

