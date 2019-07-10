# UnixBench test plug-in.

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"}

source ${SCRIPTS_TOP}/lib/util.sh

test_usage_sys_info() {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${BASH_SOURCE##*/} - Collect system information." >&2
	eval "${old_xtrace}"
}

test_packages_sys_info() {
	local rootfs_type=${1}

	case "${rootfs_type}" in
	alpine)
		echo "dmidecode"
		;;
	debian)
		echo "dmidecode"
		;;
	*)
		echo "${FUNCNAME[0]}: ERROR: Unknown rootfs type: '${rootfs_type}'" >&2
		exit 1
		;;
	esac
}

test_setup_sys_info() {
	local rootfs_type=${1}
	local rootfs=${2}

	return
}

test_build_sys_info() {
	local rootfs_type=${1}
	local tests_dir=${2}
	mkdir -p ${tests_dir}
	tests_dir="$(cd ${tests_dir} && pwd)"
	local sysroot="$(cd ${3} && pwd)"
	local kernel_src_dir="$(cd ${4} && pwd)"

	echo "${FUNCNAME[0]}: Done, success." >&2
}

test_run_sys_info() {
	local tests_dir="$(cd ${1} && pwd)"
	local machine_type=${2}
	local ssh_host=${3}
	local -n _test_run_sys_info__ssh_opts=${4}
	local ssh_opts="${_test_run_sys_info__ssh_opts}"

	local test_name='sys-info'
	local results_file="${tests_dir}/${test_name}-results.tar.gz"
	local timeout=${sys_info_timeout:-"5m"}

	echo "INSIDE @${BASH_SOURCE[0]}:${FUNCNAME[0]}@"
	echo "ssh_opts = @${ssh_opts}@"

	set -x
	rm -rf ${results_file}

	set +e
	timeout ${timeout} ssh ${ssh_opts} ${ssh_host} 'sh -s' <<'EOF'
export PS4='+sys-info-test-script:${LINENO}: '

set -ex


mkdir -p ./results

id | tee ./results/id.log
cat /proc/partitions | tee ./results/partitions.log
printenv | tee ./results/printenv.log
uname -a | tee ./results/uname.log
/usr/sbin/dmidecode | tee ./results/dmidecode.log

tar -czvf ${HOME}/sys-info-results.tar.gz  ./results
EOF
	result=${?}
	set -e

	if [[ ${result} -eq 124 ]]; then
		echo "${FUNCNAME[0]}: Done, failed: timeout." >&2
	elif [[ ${result} -ne 0 ]]; then
		scp ${ssh_opts} ${ssh_host}:sys-info-results.tar.gz ${results_file} || :
		echo "${FUNCNAME[0]}: Done, failed: '${result}'." >&2
	else
		scp ${ssh_opts} ${ssh_host}:sys-info-results.tar.gz ${results_file}
		echo "${FUNCNAME[0]}: Done, success." >&2
	fi
}
