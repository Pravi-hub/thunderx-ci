# wrk - HTTP benchmark test plug-in.

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"}

source ${SCRIPTS_TOP}/lib/util.sh

test_packages_http_wrk() {
	local rootfs_type=${1}

	echo ''
}

test_setup_http_wrk() {
	local rootfs_type=${1}
	local rootfs=${2}

	return
}

test_build_http_wrk() {
	local rootfs_type=${1}
	local tests_dir=${2}
	mkdir -p ${tests_dir}
	tests_dir="$(cd ${tests_dir} && pwd)"
	local sysroot="$(cd ${3} && pwd)"
	local kernel_src_dir="$(cd ${4} && pwd)"

	local test_name='http-wrk'
	local src_repo=${http_wrk_src_repo:-"https://github.com/wg/wrk.git"}
	local repo_branch=${http_wrk_repo_branch:-"master"}
	local src_dir="${tests_dir}/${test_name}-src"
	local build_dir="${tests_dir}/${test_name}-build"
	local archive_file="${tests_dir}/${test_name}.tar.gz"
	local results_file="${tests_dir}/${test_name}-results.tar.gz"

	check_directory "${sysroot}"

	rm -rf ${build_dir} ${archive_file} ${results_file}

	if [[ ! -d "${src_dir}" ]]; then
		git clone ${src_repo} "${src_dir}"
	fi

	(cd ${src_dir} && git remote update &&
		git checkout --force ${repo_branch})

	mkdir -p ${build_dir}
	rsync -av --delete --exclude='.git' ${src_dir}/ ${build_dir}/

	pushd ${build_dir}

	if [[ "${host_arch}" != "${target_arch}" ]]; then
		case "${target_arch}" in
		amd64)
			# FIXME:
			echo "${FUNCNAME[0]}: ERROR: No amd64 support yet." >&2
			configure_opts='--host=x86_64-linux-gnu ???'
			exit 1
			;;
		arm64)
			configure_opts='--host=aarch64-linux-gnu'
			;;
		esac
	fi

	export SYSROOT="${sysroot}"
	export CPPFLAGS="-I${SYSROOT}/usr/include -I${SYSROOT}/include -I${SYSROOT}"
	export LDFLAGS="-L${SYSROOT}/usr/lib -L${SYSROOT}/lib"
	export DESTDIR="${build_dir}/install"
	export SKIP_IDCHECK=1

	echo "${FUNCNAME[0]}: TODO." >&2
	touch ${archive_file}

	popd
	echo "${FUNCNAME[0]}: Done, success." >&2
}

test_run_http_wrk() {
	local tests_dir="$(cd ${1} && pwd)"
	local machine_type=${2}
	local ssh_host=${3}
	local -n _test_run_http_wrk__ssh_opts=${4}

	local test_name='http-wrk'
	local archive_file="${tests_dir}/${test_name}.tar.gz"
	local results_file="${tests_dir}/${test_name}-results.tar.gz"
	local timeout=${http_wrk_timeout:-"5m"}

	echo "INSIDE @${BASH_SOURCE[0]}:${FUNCNAME[0]}@"
	echo "ssh_opts = @${_test_run_http_wrk__ssh_opts}@"

	echo "${FUNCNAME[0]}: TODO." >&2
	touch ${results_file}

	echo "${FUNCNAME[0]}: Done, success." >&2
}
