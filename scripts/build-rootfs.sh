#!/usr/bin/env bash

set -e

name="$(basename $0)"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"}

source ${SCRIPTS_TOP}/lib/util.sh
source ${SCRIPTS_TOP}/lib/chroot.sh

usage() {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Builds a minimal Linux disk image." >&2
	echo "Usage: ${name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -a --arch              - Target architecture. Default: '${target_arch}'." >&2
	echo "  -c --clean-rootfs      - Delete bootstrap and rootfs directories. Default: ${clean_rootfs}" >&2
	echo "  -d --output-directory  - Image output path. Default: '${output_dir}', ${rootfs_dir}', '${initrd}', '${disk_img}'." >&2
	echo "  -h --help              - Show this help and exit." >&2
	echo "  -i --output-disk-image - Output a binary disk image file '${disk_img}'." >&2
	echo "  -t --rootfs-type       - Rootfs type {$(clean_ws ${known_rootfs_types})}." >&2
	echo "                           Default: '${rootfs_type}'." >&2
	echo "  -v --verbose           - Verbose execution." >&2
	echo "Option steps:" >&2
	echo "  -1 --bootstrap          - Run bootstrap rootfs step. Default: '${step_bootstrap}'." >&2
	echo "  -2 --rootfs-setup       - Run rootfs setup step. Default: '${step_rootfs_setup}'." >&2
	echo "    --bootstrap-src       - Bootstrap source path. Default: '${bootstrap_src}'." >&2
	echo "    --kernel-modules      - Kernel modules to install. Default: '${kernel_modules}'." >&2
	echo "    --extra-packages      - Extra distro packages. Default: '${extra_packages}'." >&2
	echo "  -3 --make-image         - Run make image step. Default: '${step_make_image}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="a:b:hikm:o:p:t:v123"
	local long_opts="arch:,output-directory:,help,output-disk-image,\
	clean-rootfs,kernel-modules:,extra-packages:,rootfs-type:,verbose,\
	bootstrap,rootfs-setup,bootstrap-src:,make-image"

	local opts
	opts=$(getopt --options "${short_opts}" --long "${long_opts}" -n "${name}" -- "${@}")

	eval set -- "${opts}"

	while true ; do
		#echo "${FUNCNAME[0]}: @${1}@${2}@"
		case "${1}" in
		-a | --arch)
			target_arch=$(get_arch "${2}")
			shift 2
			;;
		-c | --clean-rootfs)
			clean_rootfs=1
			shift
			;;
		-d | --output-directory)
			output_dir="${2}"
			shift 2
			;;
		-h | --help)
			usage=1
			shift
			;;
		-i | --output-disk-image)
			output_disk_image=1
			shift
			;;
		-m | --kernel-modules)
			kernel_modules="${2}"
			shift 2
			;;
		-p | --extra-packages)
			extra_packages="${2}"
			shift 2
			;;
		-t | --rootfs-type)
			rootfs_type="${2}"
			shift 2
			;;
		-v | --verbose)
			set -x
			verbose=1
			shift
			;;
		-1 | --bootstrap)
			step_bootstrap=1
			shift
			;;
		-2 | --rootfs-setup)
			step_rootfs_setup=1
			shift
			;;
		--bootstrap-src)
			bootstrap_src="${2}"
			shift 2
			;;
		-3 | --make-image)
			step_make_image=1
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

check_kernel_modules() {
	local dir=${1}

	if [ ${dir} ]; then
		if [ ! -d "${dir}" ]; then
			echo "${name}: ERROR: <kernel-modules> directory not found: '${dir}'" >&2
			usage
			exit 1
		fi
		if [ "$(basename $(cd ${dir}/.. && pwd))" != "modules" ]; then
			echo "${name}: ERROR: No kernel modules found in '${dir}'" >&2
			usage
			exit 1
		fi
	fi
}

test_step_code() {
	local step_code="${step_bootstrap}-${step_rootfs_setup}-${step_make_image}"

	case "${step_code}" in
	1--|1-1-|1-1-1|-1-|-1-1|--1)
		#echo "${name}: Steps OK" >&2
		;;
	--)
		step_bootstrap=1
		step_rootfs_setup=1
		step_make_image=1
		;;
	1--1)
		echo "${name}: ERROR: Bad flags: 'bootstrap + make_image'." >&2
		usage
		exit 1
		;;
	*)
		echo "${name}: ERROR: Internal bad step_code: '${step_code}'." >&2
		exit 1
		;;
	esac
}

setup_network_ifupdown() {
	local rootfs=${1}

	echo "${TARGET_HOSTNAME}" | sudo_write "${rootfs}/etc/hostname"

	sudo_append "${rootfs}/etc/network/interfaces" <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

#auto enP2p1s0v0
#iface enP2p1s0v0 inet dhcp

#auto enP2p1s0f1
#iface enP2p1s0f1 inet dhcp

#auto enp9s0f1
#iface enp9s0f1 inet dhcp

# gbt2s18
# DHCPREQUEST for 10.112.35.123 on enP2p1s0v0 to 255.255.255.255 port 67

EOF
}

setup_resolv_conf() {
	local rootfs=${1}

	sudo_append "${rootfs}/etc/resolv.conf" <<EOF
nameserver 4.2.2.4
nameserver 4.2.2.2
nameserver 8.8.8.8
EOF
}

setup_network_systemd() {
	local rootfs=${1}

	echo "${TARGET_HOSTNAME}" | sudo_write "${rootfs}/etc/hostname"

	sudo_append "${rootfs}/etc/systemd/network/dhcp.network" <<EOF
[Match]
Name=en*

[Network]
DHCP=ipv4
EOF
}

setup_ssh_keys() {
	local rootfs=${1}
	local key_file=${2}

	${sudo} mkdir -p -m0700 "${rootfs}/root/.ssh"

	ssh-keygen -q -f ${key_file} -N ''
	cat "${key_file}.pub" | sudo_append "${rootfs}/root/.ssh/authorized_keys"

	for key in ${HOME}/.ssh/id_*.pub; do
		[ -f "${key_file}" ] || continue
		cat "${key_file}" | sudo_append "${rootfs}/root/.ssh/authorized_keys"
		local found=1
	done
}

setup_kernel_modules() {
	local rootfs=${1}
	local src=${2}

	if [ ! ${src} ]; then
		echo "${name}: WARNING: No kernel modules provided." >&2
		return
	fi

	local dest="${rootfs}/lib/modules/$(basename ${src})"

	if [ ${verbose} ]; then
		local extra='-v'
	fi

	${sudo} mkdir -p ${dest}
	${sudo} rsync -av --delete ${extra} \
		--exclude '/build' --exclude '/source' \
		${src}/ ${dest}/
	echo "${name}: INFO: Kernel modules size: $(directory_size_human ${dest})"
}

setup_password() {
	local rootfs=${1}
	local pw=${2}

	pw=${pw:-"r"}
	echo "${name}: INFO: Login password = '${pw}'." >&2

	if [ ${pw} ]; then
		local hash
		hash="$(openssl passwd -1 -salt tci ${pw})"
	else
		local hash=''
	fi

	${sudo} sed --in-place "s/root:x:0:0/root:${hash}:0:0/" \
		${rootfs}/etc/passwd
	${sudo} sed --in-place '/^root:.*/d' \
		${rootfs}/etc/shadow
}

delete_rootfs() {
	local rootfs=${1}

	${sudo} rm -rf ${rootfs}
}

clean_make_disk_img() {
	local mnt=${1}

	${sudo} umount ${mnt} || :
}

on_exit() {
	if [ -d ${tmp_dir} ]; then
		${sudo} rm -rf ${tmp_dir}
	fi
}

on_fail() {
	local rootfs=${1}
	local mnt=${2}

	echo "${name}: Step ${current_step}: FAILED." >&2

	cleanup_chroot ${rootfs}

	if [ -d "${mnt}" ]; then
		clean_make_disk_img "${mnt}"
		rm -rf "${mnt}"
	fi

	if [ -d ${tmp_dir} ]; then
		${sudo} rm -rf ${tmp_dir}
	fi

	if [ ${need_clean_rootfs} ]; then
		delete_rootfs ${rootfs}
	fi

	on_exit
}

make_disk_img() {
	local rootfs=${1}
	local img=${2}
	local mnt=${3}

	tmp_img="${tmp_dir}/tci-disk.img"

	dd if=/dev/zero of=${tmp_img} bs=1M count=1536
	mkfs.ext4 ${tmp_img}

	mkdir -p ${mnt}

	${sudo} mount  ${tmp_img} ${mnt}
	${sudo} cp -a ${rootfs}/* ${mnt}

	${sudo} umount ${mnt} || :
	cp ${tmp_img} ${img}
	rm -f  ${tmp_img}
}

make_ramfs() {
	local fs=${1}
	local out_file=${2}

	(cd ${fs} && ${sudo} find . | ${sudo} cpio --create --format='newc' --owner=root:root | gzip) > ${out_file}
}

make_manifest() {
	local rootfs=${1}
	local out_file=${2}

	(cd ${rootfs} && ${sudo} find . -ls | sort --key=11) > ${out_file}
}

print_usage_summary() {
	local rootfs_dir=${1}
	local kernel_modules=${2}

	rootfs_size="$(directory_size_bytes ${rootfs_dir})"
	rootfs_size="$(bc <<< "${rootfs_size} / 1048576")"

	modules_size="$(directory_size_bytes ${kernel_modules})"
	modules_size="$(bc <<< "${modules_size} / 1048576")"

	base_size="$(bc <<< "${rootfs_size} - ${modules_size}")"

	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name}: INFO: Base size:    ${base_size} MiB"
	echo "${name}: INFO: Modules size: ${modules_size} Mib"
	echo "${name}: INFO: Total size:   ${rootfs_size} Mib"
	eval "${old_xtrace}"
}

write_tci_client_script() {
	local out_file=${1}

	sudo_write "${out_file}" <<EOF
#!/bin/sh

set -x
echo ''
echo 'TCI Relay Client: start'
echo '----------'
#date
#uname -a
#cat /etc/os-release
#systemctl status networking.service
#systemctl status ssh.service
ip a
netstat -atpn | grep ':22'
cat /proc/cmdline
cat /proc/sys/kernel/random/entropy_avail
echo '----------'
echo ''

sleep 2s

my_addr() {
	ip route get 8.8.8.8 | egrep -o 'src [0-9.]*' | cut -f 2 -d ' '
}

triple="\$(cat /proc/cmdline | egrep -o 'tci_relay_triple=[^ ]*' | cut -d '=' -f 2)"

if [ ! \${triple} ]; then
	echo "TCI Relay Client: ERROR: Triple not found: '\$(cat /proc/cmdline)'."
	exit 2
fi

ip_test="\$(my_addr)"

if [ ! \${ip_test} ]; then
	echo "TCI Relay Client: WARNING: No IP address found."
	dhclient -v
	ip a
	ip_test="\$(my_addr)"
fi

server="\$(echo \${triple} | cut -d ':' -f 1)"
port="\$(echo \${triple} | cut -d ':' -f 2)"
token="\$(echo \${triple} | cut -d ':' -f 3)"

count=0
while [ \${count} -lt 240 ]; do
	msg="PUT:\${token}:\$(my_addr)"
	reply=\$(echo -n \${msg} | nc -w10 \${server} \${port})
	if [ "\${reply}" = 'QED' -o "\${reply}" = 'UPD' -o "\${reply}" = 'FWD' ]; then
		break
	fi
	count=$((count+5))
	sleep 5s
done

#systemctl status networking.service
#systemctl status ssh.service

echo 'TCI Relay Client: end'
EOF

	${sudo} chmod u+x "${out_file}"
}

#===============================================================================
# program start
#===============================================================================

sudo="sudo -S"

process_opts "${@}"

rootfs_type=${rootfs_type:-"debian"}

source "${SCRIPTS_TOP}/rootfs-plugin/${rootfs_type}.sh"

host_arch=$(get_arch "$(uname -m)")
target_arch=${target_arch:-"${host_arch}"}

output_dir=${output_dir:-"$(pwd)/tci-image--${target_arch}-${rootfs_type}}"}

bootstrap_src="${bootstrap_src:-${output_dir}}"
rootfs_dir="${output_dir}/rootfs"
disk_img="${output_dir}/disk.img"
initrd="${output_dir}/initrd"
manifest="${output_dir}/manifest"
server_key="${output_dir}/server-key"
login_key="${output_dir}/login-key"

check_kernel_modules ${kernel_modules}
test_step_code

if [ ${usage} ]; then
	usage
	exit 0
fi

${sudo} true

${sudo} rm -rf ${disk_img} ${initrd} ${manifest} ${server_key} ${login_key} 

cleanup_chroot ${rootfs_dir}

trap "on_fail ${rootfs_dir} none" EXIT

tmp_dir="$(mktemp --tmpdir --directory ${name}.XXXX)"

if [ ${step_bootstrap} ]; then
	current_step="bootstrap"
	echo "${name}: INFO: Step ${current_step} (${rootfs_type}): start." >&2

	delete_rootfs ${output_dir}
	mkdir -p ${output_dir}

	bootstrap_rootfs ${output_dir}
	${sudo} chown -R $(id --user --real --name): ${output_dir}

	echo "${name}: INFO: Step ${current_step} (${rootfs_type}): Done (${output_dir})." >&2
	echo "${name}: INFO: Bootstrap size: $(directory_size_human ${output_dir})"
fi

if [ ${step_rootfs_setup} ]; then
	current_step="rootfs_setup"
	echo "${name}: INFO: Step ${current_step} (${rootfs_type}): start." >&2

	if [[ -d "${bootstrap_src}.bootstrap" ]]; then
		bootstrap_src="${bootstrap_src}/bootstrap"
	elif [[ -d "${bootstrap_src}/bootstrap" ]]; then
		bootstrap_src="${bootstrap_src}/bootstrap"
	fi

	echo "${name}: INFO: Step ${current_step}: Using ${bootstrap_src}." >&2

	check_directory ${bootstrap_src}

	if [[ "${bootstrap_src}/rootfs" != "${rootfs_dir} " ]]; then
		mkdir -p ${rootfs_dir}
		${sudo} rsync -a --delete ${bootstrap_src}/ ${rootfs_dir}/
	fi

	setup_packages ${rootfs_dir} ${default_packages} ${extra_packages}

	setup_initrd_boot ${rootfs_dir}
	setup_login ${rootfs_dir}
	setup_network ${rootfs_dir}
	setup_sshd ${rootfs_dir} ${server_key}
	setup_ssh_keys ${rootfs_dir} ${login_key}
	setup_kernel_modules ${rootfs_dir} ${kernel_modules}
	setup_relay_client ${rootfs_dir}

	rootfs_cleanup ${rootfs_dir}

	${sudo} chown -R $(id --user --real --name): ${rootfs_dir}

	print_usage_summary ${rootfs_dir} ${kernel_modules}
	echo "${name}: INFO: Step ${current_step} (${rootfs_type}): done." >&2
fi

if [ ${step_make_image} ]; then
	current_step="make_image"
	echo "${name}: INFO: Step ${current_step} (${rootfs_type}): start." >&2
	check_directory ${rootfs_dir}

	if [ ${output_disk_image} ]; then
		tmp_mnt="${tmp_dir}/tci-disk-mnt"
		trap "on_fail ${rootfs_dir} ${tmp_mnt}" EXIT
		make_disk_img ${rootfs_dir} ${disk_img} ${tmp_mnt}
		trap "on_fail ${rootfs_dir} none" EXIT
		clean_make_disk_img "${tmp_mnt}"
	fi

	make_ramfs ${rootfs_dir} ${initrd}
	make_manifest ${rootfs_dir} ${manifest}

	if [ -d ${tmp_mnt} ]; then
		rm -rf ${tmp_mnt}
	fi

	need_clean_rootfs=${clean_rootf}

	print_usage_summary ${rootfs_dir} ${kernel_modules}
	echo "${name}: INFO: Step ${current_step} (${rootfs_type}): done." >&2

fi

if [ ${need_clean_rootfs} ]; then
	delete_rootfs ${rootfs_dir}
fi

trap on_exit EXIT

echo "${name}: INFO: Success: ${output_dir}" >&2
