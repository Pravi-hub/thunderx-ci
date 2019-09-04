# ILP32 hello world test plug-in.

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}/.." && pwd)"}

source ${SCRIPTS_TOP}/lib/util.sh

test_usage_ilp32() {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "  ${BASH_SOURCE##*/} - Build and run ILP32 hello world program." >&2
	eval "${old_xtrace}"
}

test_packages_ilp32() {
	local rootfs_type=${1}
	local target_arch=${2}

	case "${rootfs_type}-${target_arch}" in
	alpine-*)
		echo "docker"
		;;
	debian-*)
		echo "docker.io"
		;;
	*)
		;;
	esac
}

test_setup_ilp32() {
	return
}

test_build_ilp32() {
	local rootfs_type=${1}
	local tests_dir=${2}
	mkdir -p ${tests_dir}
	tests_dir="$(cd ${tests_dir} && pwd)"
	local sysroot="$(cd ${3} && pwd)"
	local kernel_src_dir="$(cd ${4} && pwd)"

	local test_name='ilp32'
	local src_repo=${ilp32_src_repo:-"https://github.com/glevand/ilp32--builder.git"}
	local repo_branch=${ilp32_repo_branch:-"master"}
	local src_dir="${tests_dir}/${test_name}-src"
	local build_dir="${tests_dir}/${test_name}-build"
	local archive_file="${tests_dir}/${test_name}.tar.gz"
	local results_file="${tests_dir}/${test_name}-results.tar.gz"

	rm -rf ${build_dir} ${archive_file} ${results_file}

	git_checkout_safe ${src_dir} ${src_repo} ${repo_branch}

	mkdir -p ${build_dir}
	pushd ${build_dir}

#	${src_dir}/scripts/build-docker-image.sh -f --toolup
#	${src_dir}/scripts/build-docker-image.sh -f --builder
	${src_dir}/scripts/build-docker-image.sh --build-top=${build_dir}/auto-build --toolup --builder
	${src_dir}/scripts/build-hello-world.sh --build-top==${build_dir}/auto-build

	tar -C ${build_dir}/auto-build --create -zvf ${archive_file} \
		hello-world \
		sysroot/libilp32 \
		sysroot/lib/ld-linux-aarch64_ilp32.so.1

	tar -C ${src_dir} --append -zvf ${archive_file} \
		docker \
		scripts

	popd
	echo "${FUNCNAME[0]}: Done, success." >&2
}

test_run_ilp32() {
	local tests_dir="$(cd ${1} && pwd)"
	local machine_type=${2}
	local ssh_host=${3}
	local -n _test_run_ilp32__ssh_opts=${4}
	local ssh_opts="${_test_run_ilp32__ssh_opts}"

	local test_name='ilp32'
	local src_repo=${ilp32_src_repo:-"https://github.com/glevand/ilp32--builder.git"}
	local repo_branch=${ilp32_repo_branch:-"master"}
	local src_dir="${tests_dir}/${test_name}-src"
	local build_dir="${tests_dir}/${test_name}-build"
	local archive_file="${tests_dir}/${test_name}.tar.gz"
	local results_file="${tests_dir}/${test_name}-results.tar.gz"
	local timeout=${ilp32_timeout:-"5m"}

	echo "INSIDE @${BASH_SOURCE[0]}:${FUNCNAME[0]}@"
	echo "ssh_opts = @${ssh_opts}@"

	set -x
	rm -rf ${results_file}

	scp ${ssh_opts} ${archive_file} ${ssh_host}:/ilp32-archive.tar.gz

	set +e
	timeout ${timeout} ssh ${ssh_opts} ${ssh_host} 'sh -s' <<'EOF'
export PS4='+ ilp32-test-script:${LINENO}: '

set -ex

mkdir -p /ilp32-test
tar -C /ilp32-test -xf /ilp32-archive.tar.gz
cd /ilp32-test

service docker start

/ilp32-test/???/scripts/build-docker-image.sh -f --runner

mkdir -p ./results

printenv | tee ./results/printenv.log

tar -czvf ${HOME}/ilp32-results.tar.gz  ./results
EOF
	result=${?}
	set -e

	if [[ ${result} -eq 124 ]]; then
		echo "${FUNCNAME[0]}: Done, failed: timeout." >&2
	elif [[ ${result} -ne 0 ]]; then
		scp ${ssh_opts} ${ssh_host}:ilp32-results.tar.gz ${results_file} || :
		echo "${FUNCNAME[0]}: Done, failed: '${result}'." >&2
	else
		scp ${ssh_opts} ${ssh_host}:ilp32-results.tar.gz ${results_file}
		echo "${FUNCNAME[0]}: Done, success." >&2
	fi
}
