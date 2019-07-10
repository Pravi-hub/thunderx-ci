#kselftest test plug-in

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"}

source ${SCRIPTS_TOP}/lib/util.sh

test_usage_kselftest() {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${BASH_SOURCE##*/} - Linux Kernel Selftests." >&2
	echo "    The kernel contains a set of 'self tests' under the"
	echo "    tools/testing/selftests/ directory. These are intended to be small"
	echo "    tests to exercise individual code paths in the kernel. Tests are"
	echo "    intended to be run after building, installing and booting a kernel."
	echo "  More Info:" >&2
	echo "    https://www.kernel.org/doc/html/v4.16/dev-tools/kselftest.html" >&2
	echo "    https://www.kernel.org/doc/Documentation/kselftest.txt" >&2
	eval "${old_xtrace}"
}

test_packages_kselftest() {
	local rootfs_type=${1}

	case "${rootfs_type}" in
	alpine)
		echo ''
		;;
	debian)
		echo 'libaio-dev \
			libcap-dev \
			libcap-ng-dev \
			libfuse-dev \
			linux-libc-dev-arm64-cross \
			libnuma-dev \
		'
		;;
	*)
		echo "${FUNCNAME[0]}: ERROR: Unknown rootfs type: '${rootfs_type}'" >&2
		exit 1
		;;
	esac
}

test_setup_kselftest() {
	local rootfs_type=${1}
	local rootfs=${2}

	return
}

test_build_kselftest() {
	local rootfs_type=${1}
	local tests_dir=${2}
	mkdir -p ${tests_dir}
	tests_dir="$(cd ${tests_dir} && pwd)"
	local sysroot="$(cd ${3} && pwd)"
	local kernel_src_dir="$(cd ${4} && pwd)"

	local test_name='kselftest'
	local build_dir="${tests_dir}/${test_name}-build"
	local archive_file="${tests_dir}/${test_name}.tar.gz"
	local results_file="${tests_dir}/${test_name}-results.tar.gz"

	check_directory "${sysroot}"
	check_directory "${kernel_src_dir}"

	rm -rf ${tests_dir}

	mkdir -p ${build_dir}
	rsync -av --delete --exclude='.git' ${kernel_src_dir}/ ${build_dir}/

	pushd ${build_dir}/tools/testing/selftests

	if [[ "${host_arch}" != "${target_arch}" ]]; then
		case "${target_arch}" in
		amd64)
			echo "${FUNCNAME[0]}: ERROR: No amd64 support yet." >&2
			make_opts='x86_64-linux-gnu-gcc ???'
			exit 1
			;;
		arm64)
			make_opts='ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-'
			;;
		esac
	fi

	export SYSROOT="${sysroot}"
	export CPPFLAGS="-I${SYSROOT}/usr/include -I${SYSROOT}/include -I${SYSROOT}"
	export LDFLAGS="-L${SYSROOT}/usr/lib -L${SYSROOT}/lib"

	make clean
	eval "make ${make_opts}"
	eval "make ${make_opts} install"
	tar -czf ${archive_file} install

	popd
	echo "${FUNCNAME[0]}: Done, success." >&2
}

test_run_kselftest() {
	local tests_dir="$(cd ${1} && pwd)"
	local machine_type=${2}
	local ssh_host=${3}
	local -n _test_run_kselftest__ssh_opts=${4}
	local ssh_opts="${_test_run_kselftest__ssh_opts}"

	local test_name='kselftest'
	local archive_file="${tests_dir}/${test_name}.tar.gz"
	local results_file="${tests_dir}/${test_name}-results.tar.gz"

	echo "INSIDE @${BASH_SOURCE[0]}:${FUNCNAME[0]}@"
	echo "ssh_opts = @${_test_run_kselftest__ssh_opts}@"

	set -x
	rm -rf ${results_file}

	scp ${ssh_opts} ${archive_file} ${ssh_host}:kselftest.tar.gz

	ssh ${ssh_opts} ${ssh_host} 'sh -s' <<'EOF'
export PS4='+kselftest-test-script:${LINENO}: '
set -ex

cat /proc/partitions
printenv

rootfs_type=$(egrep '^ID=' /etc/os-release)
rootfs_type=${rootfs_type#ID=}

mkdir -p kselftest-test
tar -C kselftest-test -xf kselftest.tar.gz
cd ./kselftest-test/install

rm -rf ftarce
set +e
#./run_kselftest.sh --summary
echo "skippping tests for debug!!!"; touch output.log
result=${?}
set -e

mkdir results && mv output.log results

tar -czvf ${HOME}/kselftest-results.tar.gz ./results

EOF

	scp ${ssh_opts} ${ssh_host}:kselftest-results.tar.gz ${results_file}

}
