#!/usr/bin/env bash

set -e

name="$(basename ${0})"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"}

source ${SCRIPTS_TOP}/lib/util.sh
source ${SCRIPTS_TOP}/lib/relay.sh

usage() {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Run Linux kernel tests in QEMU." >&2
	echo "Usage: ${name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -a --arch              - Target architecture. Default: '${target_arch}'." >&2
	echo "  -c --kernel-cmd        - Kernel command line options. Default: '${kernel_cmd}'." >&2
	echo "  -f --hostfwd-offset    - QEMU hostfwd port offset. Default: '${hostfwd_offset}'." >&2
	echo "  -h --help              - Show this help and exit." >&2
	echo "  -i --initrd            - Initrd image. Default: '${initrd}'." >&2
	echo "  -k --kernel            - Kernel image. Default: '${kernel}'." >&2
	echo "  -o --out-file          - stdout, stderr redirection file. Default: '${out_file}'." >&2
	echo "  -s --systemd-debug     - Run systemd with debug options. Default: '${systemd_debug}'." >&2
	echo "  -v --verbose           - Verbose execution." >&2
	echo "  --relay-server         - Relay server host[:port]. Default: '${relay_server}'." >&2
	echo "  --result-file          - Result file. Default: '${result_file}'." >&2
	echo "  --ssh-login-key        - SSH login private key file. Default: '${ssh_login_key}'." >&2
	echo "  --test-name            - Tests name. Default: '${test_name}'." >&2
	echo "  --tests-dir            - Test directory. Default: '${tests_dir}'." >&2
	#echo "  --qemu-tap             - EXPERIMENTAL -- Use QEMU tap networking. Default: '${qemu_tap}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="a:c:d:f:hi:k:o:r:sv"
	local long_opts="arch:,kernel-cmd:,ether-mac:,hostfwd-offset:,help,initrd:,\
kernel:,out-file:,systemd-debug,verbose,\
relay-server:,result-file:,ssh-login-key:,test-name:,tests-dir:,qemu-tap"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${name}" -- "$@")

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
		-i | --initrd)
			initrd="${2}"
			shift 2
			;;
		-k | --kernel)
			kernel="${2}"
			shift 2
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
		--relay-server)
			relay_server="${2}"
			shift 2
			;;
		--result-file)
			result_file="${2}"
			shift 2
			;;
		--ssh-login-key)
			ssh_login_key="${2}"
			shift 2
			;;
		--test-name)
			test_name="${2}"
			shift 2
			;;
		--tests-dir)
			tests_dir="${2}"
			shift 2
			;;
		--qemu-tap)
			qemu_tap=1
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

	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo '*** on_exit ***'
	echo "*** result   = ${result}" >&2
	echo "*** qemu_pid = ${qemu_pid}" >&2
	echo "*** up time  = $(sec_to_min ${SECONDS}) min" >&2
	eval "${old_xtrace}"

	if [[ -n "${qemu_pid}" ]]; then
		${sudo} kill ${qemu_pid} || :
		wait ${qemu_pid}
		qemu_pid=''
	fi

	rm -f ${test_kernel}

	if [[ -d ${tmp_dir} ]]; then
		${sudo} rm -rf ${tmp_dir}
	fi

	echo "${name}: ${result}" >&2
}

start_qemu_user_networking() {
	ssh_fwd=$(( ${hostfwd_offset} + 22 ))

	echo "${name}: ssh_fwd port = ${ssh_fwd}" >&2

	${SCRIPTS_TOP}/start-qemu.sh \
		--arch="${target_arch}" \
		--kernel-cmd="${kernel_cmd}" \
		--hostfwd-offset="${hostfwd_offset}" \
		--initrd="${initrd}" \
		--kernel="${test_kernel}" \
		--out-file="${out_file}" \
		--disk-image="${disk_image}" \
		--pid-file="${qemu_pid_file}" \
		--verbose \
		${qemu_extra_args} \
		</dev/null &> "${out_file}.start" &
	ps aux
}

start_qemu_tap_networking() {
	local mac=${2}

	local bridge="br0"
	local host_eth="eth0"
	local qemu_tap="qemu0"
	local my_addr=$(my_addr)
	local my_net="${my_addr%.[0-9]*}"

	echo "${name}: my_addr = '${my_addr}'" >&2
	echo "${name}: my_net  = '${my_net}'" >&2

	local bridge_addr
	bridge_addr="$(ip address show dev ${host_eth} \
		| egrep -o 'inet .*' | cut -f 2 -d ' ')"

	echo "${name}: bridge_addr='${bridge_addr}'" >&2

	# Create bridge.
	${sudo} ip link add ${bridge} type bridge
	${sudo} ip link set ${bridge} down
	${sudo} ip addr flush dev ${bridge}
	${sudo} ip addr add dev ${bridge} ${bridge_addr}
	${sudo} ip link set ${bridge} up
	bridge link

	# Add host interface to bridge.
	${sudo} ip link set ${host_eth} down
	${sudo} ip addr flush dev ${host_eth}
	${sudo} ip link set ${host_eth} up
	${sudo} ip link set ${host_eth} master ${bridge}
	bridge link

	sudo_write /etc/default/isc-dhcp-server <<EOF
INTERFACESv4='eth0'
INTERFACESv6=''
EOF

	sudo_write /etc/dhcp/dhcpd.conf <<EOF
option domain-name-servers 8.8.8.8, 8.8.4.4, 4.2.2.4, 4.2.2.2;
default-lease-time 600;
max-lease-time 7200;
ddns-update-style none;

subnet ${my_net}.0 netmask 255.255.0.0 {
  authoritative;
  range ${my_net}.100 ${my_net}.120;
  option routers ${my_net}.1;
}

host ci-tester-1 {
  hardware ethernet ${remote_mac};
  fixed-address ${my_net}.20;
  option host-name 'ci-tester-1';
}
EOF

	touch /var/lib/dhcp/dhcpd.leases

	dhcpd -4 -pf /tmp/dhcpd.pid -cf /etc/dhcp/dhcpd.conf

	${SCRIPTS_TOP}/start-qemu.sh \
		--ether-mac=${mac}
		${qemu_extra_args} \
		--arch=${target_arch} \
		--install-dir=${kernel_install_dir} \
		--qemu-tap \
		</dev/null &>"${out_file}" &

	qemu_pid="${!}"

	# Add qemu tap interface to bridge.
	${sudo} ip link set ${qemu_tap} down
	${sudo} ip addr flush dev ${qemu_tap}
	${sudo} ip link set ${qemu_tap} up
	${sudo} ip link set ${qemu_tap} master ${bridge}
	bridge link
}

#===============================================================================
# program start
#===============================================================================
sudo="sudo -S"

trap "on_exit 'failed.'" EXIT

process_opts "${@}"

host_arch=$(get_arch "$(uname -m)")
target_arch=${target_arch:-"${host_arch}"}
hostfwd_offset=${hostfwd_offset:-"20000"}
out_file=${out_file:-"qemu.out"}
result_file=${result_file:-"qemu-result.txt"}

relay_triple=$(relay_init_triple ${relay_server})
relay_token=$(relay_triple_to_token ${relay_triple})

if [[ -n "${usage}" ]]; then
	usage
	exit 0
fi

if [[ "${target_arch}" != "arm64" ]]; then
	echo "${name}: ERROR: Unsupported target arch '${target_arch}'.  Must be arm64." >&2
	exit 1
fi

check_opt 'kernel' ${kernel}
check_file "${kernel}"

check_opt 'initrd' ${initrd}
check_file "${initrd}"

check_opt 'ssh-login-key' ${ssh_login_key}
check_file "${ssh_login_key}"

check_opt 'test-name' ${test_name}

check_opt 'tests-dir' ${tests_dir}
check_directory "${tests_dir}"

if [[ ${systemd_debug} ]]; then
	qemu_extra_args+=' --systemd-debug'
fi

${SCRIPTS_TOP}/set-relay-triple.sh \
	--kernel=${kernel} \
	--relay-triple="${relay_triple}" \
	--verbose

test_kernel=${kernel}.${relay_token}

mkdir -p ${out_file%/*}
rm -f ${out_file} ${out_file}.start ${result_file}

tmp_dir="$(mktemp --tmpdir --directory ${name}.XXXX)"

echo '--------' >> ${result_file}
echo 'printenv' >> ${result_file}
echo '--------' >> ${result_file}
printenv        >> ${result_file}
echo '--------' >> ${result_file}

qemu_hda=${tmp_dir}/qemu-hda
qemu-img create -f qcow2 ${qemu_hda} 8G

qemu_hdb=${tmp_dir}/qemu-hdb
qemu-img create -f qcow2 ${qemu_hdb} 8G

qemu_pid_file=${tmp_dir}/qemu-pid

SECONDS=0
start_qemu_user_networking

#remote_mac="10:11:12:00:00:01"
#start_qemu_tap_networking ${remote_mac}

echo "${name}: Waiting for QEMU startup..." >&2
sleep 10s

echo '---- start-qemu start ----' >&2
cat ${out_file}.start >&2
echo '---- start-qemu end ----' >&2

ps aux

if [[ ! -f ${qemu_pid_file} ]]; then
	echo "${name}: ERROR: QEMU seems to have quit early (pid file)." >&2
	exit 1
fi

qemu_pid=$(cat ${qemu_pid_file})

if ! kill -0 ${qemu_pid} &> /dev/null; then
	echo "${name}: ERROR: QEMU seems to have quit early (pid)." >&2
	exit 1
fi

relay_get "180" ${relay_triple} remote_addr

user_remote_host="root@localhost"
user_remote_ssh_opts="-o Port=${ssh_fwd}"

tap_remote_host="root@${remote_addr}"

remote_host=${user_remote_host}
remote_ssh_opts=${user_remote_ssh_opts}

# The remote host address could come from DHCP, so don't use known_hosts.
ssh_no_check="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

source ${SCRIPTS_TOP}/test-plugin/${test_name}.sh
run_ssh_opts="${ssh_no_check} -i ${ssh_login_key} ${remote_ssh_opts}"
test_run_${test_name/-/_} ${tests_dir} 'qemu' ${remote_host} run_ssh_opts

ssh ${ssh_no_check} -i ${ssh_login_key} ${remote_ssh_opts} ${remote_host} \
	'/sbin/poweroff &'

echo "${name}: Waiting for QEMU exit..." >&2
wait_pid ${qemu_pid} 180

trap - EXIT
on_exit 'Done, success.'
