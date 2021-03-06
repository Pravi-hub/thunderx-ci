#!/usr/bin/env bash

set -e

name="$(basename ${0})"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"}

source ${SCRIPTS_TOP}/lib/util.sh

usage() {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Run Linux kernel in QEMU." >&2
	echo "Usage: ${name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -a --arch              - Target architecture. Default: '${target_arch}'." >&2
	echo "  -c --kernel-cmd        - Kernel command line options. Default: '${kernel_cmd}'." >&2
	echo "  -e --ether-mac         - QEMU Ethernet MAC. Default: '${ether_mac}'." >&2
	echo "  -f --hostfwd-offset    - QEMU hostfwd port offset. Default: '${hostfwd_offset}'." >&2
	echo "  -h --help              - Show this help and exit." >&2
	echo "  -i --initrd            - Initrd image. Default: '${initrd}'." >&2
	echo "  -k --kernel            - Kernel image. Default: '${kernel}'." >&2
# TODO	echo "  -m --modules           - Kernel modules directory.  To mount over existing modules directory. Default: '${modules}'." >&2
	echo "  -o --out-file          - stdout, stderr redirection file. Default: '${out_file}'." >&2
# TODO	echo "  -r --disk-image        - Raw disk image.  Alternative to --initrd. Default: '${disk_image}'." >&2
	echo "  -s --systemd-debug     - Run systemd with debug options. Default: '${systemd_debug}'." >&2
	echo "  -t --qemu-tap          - Use QEMU tap networking. Default: '${qemu_tap}'." >&2
	echo "  -v --verbose           - Verbose execution." >&2
	echo "  --hda                  - QEMU IDE hard disk image hda. Default: '${hda}'." >&2
	echo "  --hdb                  - QEMU IDE hard disk image hdb. Default: '${hdb}'." >&2
	echo "  --pid-file             - QEMU IDE hard disk image hdb. Default: '${pid_file}'." >&2
	eval "${old_xtrace}"
}

short_opts="a:c:e:f:hi:k:m:o:r:stv"
long_opts="arch:,kernel-cmd:,ether-mac:,hostfwd-offset:,help,initrd:,\
kernel:,modules:,out-file:,disk-image:,systemd-debug,qemu-tap,verbose,\
hda:,hdb:,pid-file:"

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
	-e | --ether-mac)
		ether_mac="${2}"
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
	-i | --initrd)
		initrd="${2}"
		shift 2
		;;
	-k | --kernel)
		kernel="${2}"
		shift 2
		;;
	-m | --modules)
		modules="${2}"
		shift 2
		;;
	-o | --out-file)
		out_file="${2}"
		shift 2
		;;
	-r | --disk-image)
		disk_image="${2}"
		shift 2
		;;
	-s | --systemd-debug)
		systemd_debug=1
		shift
		;;
	-t | --qemu-tap)
		qemu_tap=1
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
	--hdb)
		hdb="${2}"
		shift 2
		;;
	--pid-file)
		pid_file="${2}"
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
ether_mac=${ether_mac:-"01:02:03:00:00:01"}

if [[ ${systemd_debug} ]]; then
	# FIXME: need to run set-systemd-debug.sh???
	kernel_cmd+=" systemd.log_level=debug systemd.log_target=console systemd.journald.forward_to_console=1"
fi

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

if [[ ! ${initrd} && ! ${disk_image} ]]; then
	echo "${name}: ERROR: Must provide --initrd or --disk-image option." >&2
	usage
	exit 1
fi

if [[ ${initrd} ]]; then
	check_file "${initrd}"
fi

if [[ ${disk_image} ]]; then
	check_file "${disk_image}"
	disk_image_root="/dev/vda"
fi

if [[ ${modules} ]]; then
	check_directory "${modules}"
fi

# --- end common ---

setup_efi() {
	case "${target_arch}" in
	amd64)
		efi_code_src="/usr/share/OVMF/OVMF_CODE.fd"
		efi_vars_src="/usr/share/OVMF/OVMF_VARS.fd"
		efi_full_src="/usr/share/ovmf/OVMF.fd"
		;;
	arm64)
		efi_code_src="/usr/share/AAVMF/AAVMF_CODE.fd"
		efi_vars_src="/usr/share/AAVMF/AAVMF_VARS.fd"
		efi_full_src="/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
		;;
	esac

	efi_code="${efi_code_src}"
	efi_vars="${target_arch}-EFI_VARS.fd"

	check_file ${efi_code_src}
	check_file ${efi_vars_src}

	copy_file ${efi_vars_src} ${efi_vars}
}

qemu_args="-kernel ${kernel}"
qemu_append_args="${kernel_cmd}"

case "${host_arch}--${target_arch}" in
amd64--amd64)
	qemu_exe="qemu-system-x86_64"
	qemu_args+=" -machine accel=kvm -cpu host -m 2048"
	;;
amd64--arm64)
	qemu_exe="qemu-system-aarch64"
	qemu_args+=" -machine virt,gic-version=3 -cpu cortex-a57 -m 5120"
	#qemu_args+=" -machine virt,gic-version=3 -cpu cortex-a57 -m 15360"
	;;
arm64--amd64)
	qemu_exe="qemu-system-x86_64"
	qemu_args+=" -machine pc-q35-2.8 -cpu kvm64 -m 2048"
	;;
arm64--arm64)
	qemu_exe="qemu-system-aarch64"
	qemu_args+=" -machine virt,gic-version=3,accel=kvm -cpu host -m 4096"
	;;
*)
	echo "${name}: ERROR: Unsupported host--target combo: '${"${host_arch}--${target_arch}"}'." >&2
	exit 1
	;;
esac


if [[ -n ${qemu_tap} ]]; then
	# FIXME: Needs test.
	# FIXME: Use virtio-net-device or virtio-net-pci???
	qemu_args+=" \
	-netdev tap,id=tap0,ifname=qemu0,br=br0 \
	-device virtio-net-pci,netdev=tap0,mac=${ether_mac} \
	"
else
	ssh_fwd=$(( ${hostfwd_offset} + 22 ))

	echo "${name}: SSH fwd = ${ssh_fwd}" >&2

	# FIXME: Use virtio-net-device or virtio-net-pci???
	qemu_args+=" \
		-netdev user,id=eth0,hostfwd=tcp::${ssh_fwd}-:22,hostname=${TARGET_HOSTNAME} \
		-device virtio-net-device,netdev=eth0 \
	"
fi

if [[ ${initrd} ]]; then
	qemu_args+=" -initrd ${initrd}"
fi

if [[ ${hda} ]]; then
	qemu_args+=" -hda ${hda}"
fi

if [[ ${hdb} ]]; then
	qemu_args+=" -hdb ${hdb}"
fi


if [[ ${modules} ]]; then # TODO
	qemu_args+=" \
		-fsdev local,id=modules,security_model=none,path=${modules} \
		-device virtio-9p-device,fsdev=modules,mount_tag=${MODULES_ID} \
	"
fi

if [[ ${disk_image} ]]; then # TODO
	qemu_args+=" \
		-drive if=none,id=blk,file=${disk_image}   \
		-device virtio-blk-device,drive=blk \
	"
	qemu_append_args+=" root=${disk_image_root} rw"
fi

if [[ ${out_file} ]]; then
	qemu_args+=" \
		-display none \
		-chardev file,id=char0,path=${out_file} \
		-serial chardev:char0 \
	"
else
	qemu_args+=" -nographic"
fi

if [[ ${pid_file} ]]; then
	qemu_args+=" -pidfile ${pid_file}"
fi

setup_efi

ls -l /dev/kvm || :
cat /etc/group || :
id

cmd="${qemu_exe} \
	-name tci-vm \
	-smp 2 \
	-object rng-random,filename=/dev/urandom,id=rng0 \
	-device virtio-rng-pci,rng=rng0 \
	-drive if=pflash,file=${efi_code},format=raw,readonly \
	-drive if=pflash,file=${efi_vars},format=raw \
	${qemu_args} \
	-append '${qemu_append_args}' \
"

eval exec "${cmd}"
