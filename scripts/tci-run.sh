#!/usr/bin/env bash

usage() {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Builds TCI container image, Linux kernel, root file system images, runs test suites." >&2
	echo "Usage: ${name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  --arch            - Target architecture. Default: ${target_arch}." >&2
	echo "  -a --help-all     - Show test help and exit." >&2
	echo "  -c --config-file  - ${name} config file. Default: '${config_file}'." >&2
	echo "  -h --help         - Show this help and exit." >&2
	echo "  -v --verbose      - Verbose execution." >&2
	echo "  --build-name      - Build name. Default: '${build_name}'." >&2
	echo "  --linux-branch    - Linux kernel git repository branch. Default: ${kernel_branch}." >&2
	echo "  --linux-config    - URL of an alternate kernel config. Default: ${kernel_config}." >&2
	echo "  --linux-repo      - Linux kernel git repository URL. Default: ${kernel_repo}." >&2
	echo "  --linux-src-dir   - Linux kernel git working tree. Default: ${kernel_src_dir}." >&2
	echo "  --test-machine    - Test machine name. Default: '${test_machine}'." >&2
	echo "  --systemd-debug   - Run systemd with debug options. Default: '${systemd_debug}'." >&2
	echo "  --rootfs-types    - Rootfs types to build {$(clean_ws ${known_rootfs_types}) all}." >&2
	echo "                      Default: '${rootfs_types}'." >&2
	echo "  --test-types      - Test types to run {$(clean_ws ${known_test_types}) all}." >&2
	echo "                      Default: '${test_types}'." >&2
	echo "Option steps:" >&2
	echo "  --enter               - Enter container, no builds." >&2
	echo "  -1 --build-kernel     - Build kernel." >&2
	echo "  -2 --build-bootstrap  - Build rootfs bootstrap." >&2
	echo "  -3 --build-rootfs     - Build rootfs." >&2
	echo "  -4 --build-tests      - Build tests." >&2
	echo "  -5 --run-qemu-tests   - Run Tests." >&2
	echo "  -6 --run-remote-tests - Run Tests." >&2
	echo "Environment:" >&2
	echo "  TCI_ROOT            - Default: '${TCI_ROOT}'." >&2
	echo "  TCI_TEST_ROOT       - Default: '${TCI_TEST_ROOT}'." >&2
	echo "  TCI_CHECKOUT_SERVER - Default: '${TCI_CHECKOUT_SERVER}'." >&2
	echo "  TCI_RELAY_SERVER    - Default: '${TCI_RELAY_SERVER}'." >&2
	echo "  TCI_TFTP_SERVER     - Default: '${TCI_TFTP_SERVER}'." >&2
	echo "  TCI_HISTFILE        - Default: '${TCI_HISTFILE}'." >&2
	eval "${old_xtrace}"
}

test_usage() {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "Test Plugin Info:" >&2
	for test in ${known_test_types}; do
		test_usage_${test/-/_}
		echo "" >&2
	done
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="ac:hv123456"
	local long_opts="\
arch:,help-all,config-file:,help,verbose,\
build-name:,linux-branch:,linux-config:,linux-repo:,linux-src-dir:,\
test-machine:,systemd-debug,rootfs-types:,test-types:,\
enter,build-kernel,build-bootstrap,build-rootfs,build-tests,run-qemu-tests,\
run-remote-tests"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		#echo "${FUNCNAME[0]}: @${1}@ @${2}@"
		case "${1}" in
		--arch)
			target_arch=$(get_arch "${2}")
			shift 2
			;;
		-a | --help-all)
			help_all=1
			shift
			;;
		-c | --config-file)
			config_file="${2}"
			shift 2
			;;
		-h | --help)
			usage=1
			shift
			;;
		-v | --verbose)
			set -x
			verbose=1
			shift
			;;
		--build-name)
			build_name="${2}"
			shift 2
			;;
		--linux-branch)
			kernel_branch="${2}"
			shift 2
			;;
		--linux-config)
			kernel_config="${2}"
			shift 2
			;;
		--linux-repo)
			kernel_repo="${2}"
			shift 2
			;;
		--linux-src-dir)
			kernel_src_dir="${2}"
			shift 2
			;;
		--test-machine)
			test_machine="${2}"
			shift 2
			;;
		--systemd-debug)
			systemd_debug=1
			shift
			;;
		--rootfs-types)
			rootfs_types="${2}"
			shift 2
			;;
		--test-types)
			test_types="${2}"
			shift 2
			;;
		--enter)
			step_enter=1
			shift
			;;
		-1 | --build-kernel)
			step_build_kernel=1
			shift
			;;
		-2 | --build-bootstrap)
			step_build_bootstrap=1
			shift
			;;
		-3 | --build-rootfs)
			step_build_rootfs=1
			shift
			;;
		-4 | --build-tests)
			step_build_tests=1
			shift
			;;
		-5 | --run-qemu-tests)
			step_run_qemu_tests=1
			shift
			;;
		-6 | --run-remote-tests)
			step_run_remote_tests=1
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

	local end_time="$(date)"
	local end_sec="${SECONDS}"
	local end_min
	if test -x "$(command -v bc)"; then
		end_min="$(bc <<< "scale=2; ${end_sec} / 60")"
	else
		end_min="$((end_sec / 60)).$(((end_sec * 100) / 60))"
	fi

	set +x
	echo "${name}: start time: ${start_time}" >&2
	echo "${name}: end time:   ${end_time}" >&2
	echo "${name}: duration:   ${end_sec} seconds (${end_min} min)" >&2
	echo "${name}: Done:       ${result}" >&2
}

check_rootfs_types() {
	local given
	local known
	local found
	local all

	for given in ${rootfs_types}; do
		found="n"
		if [[ "${given}" == "all" ]]; then
			all=1
			continue
		fi
		for known in ${known_rootfs_types}; do
			if [[ "${given}" == "${known}" ]]; then
				found="y"
				break
			fi
		done
		if [[ "${found}" != "y" ]]; then
			echo "${name}: ERROR: Unknown rootfs-type '${given}'." >&2
			exit 1
		fi
		#echo "${FUNCNAME[0]}: Found '${given}'." >&2
	done

	if [[ ${all} ]]; then
		rootfs_types="$(clean_ws ${known_rootfs_types})"
	fi
}

check_test_types() {
	local given
	local known
	local found
	local all

	for given in ${test_types}; do
		found="n"
		if [[ "${given}" == "all" ]]; then
			all=1
			continue
		fi
		for known in ${known_test_types}; do
			if [[ "${given}" == "${known}" ]]; then
				found="y"
				break
			fi
		done
		if [[ "${found}" != "y" ]]; then
			echo "${name}: ERROR: Unknown test-type '${given}'." >&2
			usage
			exit 1
		fi
		#echo "${FUNCNAME[0]}: Found '${given}'." >&2
	done

	if [[ ${all} ]]; then
		test_types="$(clean_ws ${known_test_types})"
	fi
}

build_kernel() {
	local repo=${1}
	local branch=${2}
	local config=${3}
	local fixup_spec=${4}
	local platform_args=${5}
	local src_dir=${6}
	local build_dir=${7}
	local install_dir=${8}

	rm -rf ${build_dir} ${install_dir}

	git_checkout_safe ${src_dir} ${repo} ${branch}

	${SCRIPTS_TOP}/build-linux-kernel.sh \
		--build-dir=${build_dir} \
		--install-dir=${install_dir} \
		${target_arch} ${src_dir} defconfig

	if [[ ${config} != 'defconfig' ]]; then
		if [[ -f ${config} ]]; then
			cp -vf ${config} ${build_dir}/.config
		else
			curl --silent --show-error --location ${config} \
				> ${build_dir}/.config
		fi
	else
		bash -x ${SCRIPTS_TOP}/set-config-opts.sh \
			--verbose \
			${platform_args:+"--platform-args='${platform_args}'"} \
			${fixup_spec} ${build_dir}/.config
	fi

	bash -x ${SCRIPTS_TOP}/build-linux-kernel.sh \
		--build-dir=${build_dir} \
		--install-dir=${install_dir} \
		${verbose:+--verbose} \
		${target_arch} ${src_dir} all
}

build_kernel_with_initrd() {
	local src_dir=${1}
	local build_dir=${2}
	local install_dir=${3}
	local image_dir=${4}

	check_file ${image_dir}/initrd
	ln -sf ./initrd ${image_dir}/initrd.cpio

	#export make_options_user="CONFIG_INITRAMFS_SOURCE=${image_dir}/initrd.cpio"

	make_options_user="CONFIG_INITRAMFS_SOURCE=${image_dir}/initrd.cpio" ${SCRIPTS_TOP}/build-linux-kernel.sh \
		--build-dir=${build_dir} \
		--install-dir=${install_dir} \
		${verbose:+--verbose} \
		${target_arch} ${src_dir} Image.gz
}

build_bootstrap() {
	local rootfs_type=${1}
	local bootstrap_dir=${2}

	${sudo} rm -rf ${bootstrap_dir}

	${SCRIPTS_TOP}/build-rootfs.sh \
		--arch=${target_arch} \
		--output-dir=${bootstrap_dir} \
		--rootfs-type=${rootfs_type} \
		--bootstrap \
		--verbose
}

build_rootfs() {
	local rootfs_type=${1}
	local test_name=${2}
	local image_dir=${3}
	local bootstrap_dir=${4}
	local kernel_dir=${5}

	check_directory "${bootstrap_dir}"
	check_directory "${kernel_dir}"

	rm -rf ${image_dir}
	mkdir -p ${image_dir}

	local modules
	modules="$(find ${kernel_dir}/lib/modules/* -maxdepth 0 -type d)"
	check_directory "${modules}"

	local extra_packages
	extra_packages+="$(test_packages_${test_name//-/_} ${rootfs_type} ${target_arch})"

	${SCRIPTS_TOP}/build-rootfs.sh \
		--arch=${target_arch} \
		--output-dir=${image_dir} \
		--rootfs-type=${rootfs_type} \
		--bootstrap-src="${bootstrap_dir}" \
		--kernel-modules="${modules}" \
		--extra-packages="${extra_packages}" \
		--rootfs-setup \
		--make-image \
		--verbose

	test_setup_${test_name//-/_} ${rootfs_type} ${image_dir}/rootfs
}

create_sysroot() {
	local rootfs_type=${1}
	local rootfs=${2}
	local sysroot=${3}

	check_directory "${rootfs}"

	mkdir -p ${sysroot}
	${sudo} rsync -a --delete ${rootfs}/ ${sysroot}/
	${sudo} chown $(id --user --real --name): ${sysroot}

	${SCRIPTS_TOP}/prepare-sysroot.sh ${sysroot}
}

build_tests() {
	local rootfs_type=${1}
	local test_name=${2}
	local tests_dir=${3}
	local sysroot=${4}
	local kernel_src=${5}

	check_directory "${sysroot}"
	check_directory "${kernel_src}"

	test_build_${test_name//-/_} ${rootfs_type} ${tests_dir} ${sysroot} \
		${kernel_src}
}

run_qemu_tests() {
	local kernel=${1}
	local image_dir=${2}
	local tests_dir=${3}
	local results_dir=${4}

	echo "${name}: run_qemu_tests" >&2

	check_file ${kernel}
	check_directory ${image_dir}
	check_file ${image_dir}/initrd
	check_file ${image_dir}/login-key
	check_directory ${tests_dir}

	if [[ ${systemd_debug} ]]; then
		local extra_args="--systemd-debug"
	fi

	bash -x ${SCRIPTS_TOP}/run-kernel-qemu-tests.sh \
		--kernel=${kernel} \
		--initrd=${image_dir}/initrd \
		--ssh-login-key=${image_dir}/login-key \
		--test-name=${test_name} \
		--tests-dir=${tests_dir} \
		--out-file=${results_dir}/qemu-console.txt \
		--result-file=${results_dir}/qemu-result.txt \
		--arch=${target_arch} \
		${extra_args} \
		--verbose
}

run_remote_tests() {
	local kernel=${1}
	local image_dir=${2}
	local tests_dir=${3}
	local results_dir=${4}

	echo "${name}: run_remote_tests" >&2

	check_file ${kernel}
	check_directory ${image_dir}
	check_file ${image_dir}/initrd
	check_file ${image_dir}/login-key
	check_directory ${tests_dir}

	if [[ ${systemd_debug} ]]; then
		local extra_args="--systemd-debug"
	fi

	${SCRIPTS_TOP}/run-kernel-remote-tests.sh \
		--kernel=${kernel} \
		--initrd=${image_dir}/initrd \
		--ssh-login-key=${image_dir}/login-key \
		--tests-dir=${tests_dir} \
		--test-name=${test_name} \
		--tests-dir=${tests_dir} \
		--out-file=${results_dir}/${test_machine}-console.txt \
		--result-file=${results_dir}/${test_machine}-result.txt \
		--test-machine=${test_machine} \
		${extra_args} \
		--verbose
}

#===============================================================================
# program start
#===============================================================================
name="${0##*/}"

trap "on_exit 'failed.'" EXIT
set -e

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
DOCKER_TOP=${DOCKER_TOP:-"$(cd "${SCRIPTS_TOP}/../docker" && pwd)"}

source ${SCRIPTS_TOP}/lib/util.sh
source ${SCRIPTS_TOP}/rootfs-plugin/rootfs-plugin.sh
source ${SCRIPTS_TOP}/test-plugin/test-plugin.sh

config_file="${config_file:-${SCRIPTS_TOP}/tci-run.conf}"

check_file ${config_file} " --config-file" "usage"
source ${config_file}

for test in ${known_test_types}; do
	check_file ${SCRIPTS_TOP}/test-plugin/${test}.sh
	source ${SCRIPTS_TOP}/test-plugin/${test}.sh
done

sudo="sudo -S"
parent_ops="$@"

start_time="$(date)"
SECONDS=0


process_opts "${@}"

set -x

work_dir=${work_dir:-"/tci--test"}
test_machine=${test_machine:-"t88"}
build_name=${build_name:-"${name%.*}-$(date +%m.%d)"}
target_arch=${target_arch:-"arm64"}
host_arch=$(get_arch "$(uname -m)")

top_build_dir="$(pwd)/${build_name}"

TCI_ROOT=${TCI_ROOT:-"$(cd ${SCRIPTS_TOP}/.. && pwd)"}
TCI_TEST_ROOT=${TCI_TEST_ROOT:-"${TEST_ROOT}"}
TCI_TEST_ROOT=${TCI_TEST_ROOT:-"$(pwd)"}
TCI_HISTFILE=${TCI_HISTFILE:-"${work_dir}/${build_name}--bash_history"}

rootfs_types=${rootfs_types:-"debian"}
rootfs_types="${rootfs_types//,/ }"

test_types=${test_types:-"sys-info"}
test_types="${test_types//,/ }"

kernel_repo=${kernel_repo:-"https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git"}
kernel_branch=${kernel_branch:-"linux-5.2.y"}
kernel_config=${kernel_config:-"defconfig"}
kernel_repo_name="${kernel_repo##*/}"
kernel_repo_name="${kernel_repo_name%.*}"
kernel_src_dir=${kernel_src_dir:-"$(pwd)/${kernel_repo_name}"}
kernel_build_dir="${top_build_dir}/${target_arch}-kernel-build"
kernel_install_dir="${top_build_dir}/${target_arch}-kernel-install"

case ${target_arch} in
arm64)
	fixup_spec="${SCRIPTS_TOP}/tx2-fixup.spec"
	kernel_image="${kernel_install_dir}/boot/Image"
	;;
ppc*)
	fixup_spec="${SCRIPTS_TOP}/ppc-fixup.spec"
	kernel_image="${kernel_install_dir}/boot/vmlinux.strip"
	;;
*)
	fixup_spec="${SCRIPTS_TOP}/generic-fixup.spec"
	kernel_image="${kernel_install_dir}/boot/vmlinux.strip"
	;;
esac

if [[ ${help_all} ]]; then
	set +o xtrace
	usage
	echo "" >&2
	test_usage
	trap - EXIT
	exit 0
fi

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

if [[ ${TCI_BUILDER} ]]; then
	if [[ ${step_enter} ]]; then
		echo "${name}: ERROR: Already in tci-builder." >&2
		exit 1
	fi
else
	check_directory ${TCI_ROOT} "" "usage"
	check_directory ${TCI_TEST_ROOT} "" "usage"

	${DOCKER_TOP}/builder/build-builder.sh

	echo "${name}: Entering ${build_name} container..." >&2

	if [[ ${step_enter} ]]; then
		docker_cmd="/bin/bash"
	else
		docker_cmd="/tci/scripts/tci-run.sh ${parent_ops}"
	fi

	${SCRIPTS_TOP}/run-builder.sh \
		--verbose \
		--container-name="${build_name}" \
		--docker-args="\
			-e build_name \
			-v ${TCI_ROOT}:/tci:ro \
			-e TCI_ROOT=/tci \
			-v ${TCI_TEST_ROOT}:${work_dir}:rw,z \
			-e TCI_TEST_ROOT=${work_dir} \
			-w ${work_dir} \
			-e HISTFILE=${TCI_HISTFILE} \
		" \
		-- "${docker_cmd}"

	trap "on_exit 'container success.'" EXIT
	exit 0
fi

check_rootfs_types
check_test_types

step_code="${step_build_kernel:-"0"}${step_build_bootstrap:-"0"}\
${step_build_rootfs:-"0"}${step_build_tests:-"0"}${step_run_qemu_tests:-"0"}\
${step_run_remote_tests:-"0"}"

if [[ "${step_code}" == "000000" ]]; then
	echo "${name}: ERROR: No step options provided." >&2
	usage
	exit 1
fi

printenv

if [[ ${step_build_bootstrap} || ${step_build_rootfs} ]]; then
	${sudo} true
fi

mkdir -p ${top_build_dir}

if [[ ${step_build_kernel} ]]; then
	trap "on_exit 'build_kernel failed.'" EXIT

	build_kernel ${kernel_repo} ${kernel_branch} ${kernel_config} \
		${fixup_spec} "${kernel_platform_args}" ${kernel_src_dir} \
		${kernel_build_dir} ${kernel_install_dir}
fi

for rootfs_type in ${rootfs_types}; do

	bootstrap_prefix="${top_build_dir}/${target_arch}-${rootfs_type}"
	bootstrap_dir="${top_build_dir}/${target_arch}-${rootfs_type}.bootstrap"

	if [[ ${step_build_bootstrap} ]]; then
		trap "on_exit 'build_bootstrap failed.'" EXIT
		build_bootstrap ${rootfs_type} ${bootstrap_dir}
	fi

	for test_name in ${test_types}; do
		trap "on_exit 'test loop failed.'" EXIT

		output_prefix="${bootstrap_prefix}-${test_name}"
		image_dir=${output_prefix}.image
		tests_dir=${output_prefix}.tests
		results_dir=${output_prefix}.results
	
		echo "${name}: INFO: ${test_name} => ${output_prefix}" >&2

		if [[ ${step_build_rootfs} ]]; then
			trap "on_exit 'build_rootfs failed.'" EXIT
			build_rootfs ${rootfs_type} ${test_name} ${image_dir} \
				${bootstrap_dir} ${kernel_install_dir}
			create_sysroot ${rootfs_type} ${image_dir}/rootfs \
				${image_dir}/sysroot
			#build_kernel_with_initrd ${kernel_src_dir} \
			#	${kernel_build_dir} ${kernel_install_dir} \
			#	${image_dir}
		fi

		if [[ ${step_build_tests} ]]; then
			trap "on_exit 'build_tests failed.'" EXIT
			build_tests ${rootfs_type} ${test_name} ${tests_dir} \
				${image_dir}/sysroot ${kernel_src_dir}
		fi

		if [[ ${step_run_qemu_tests} ]]; then
			trap "on_exit 'run_qemu_tests failed.'" EXIT
			run_qemu_tests ${kernel_image} \
				${image_dir} ${tests_dir} ${results_dir}
		fi

		if [[ ${step_run_remote_tests} ]]; then
			trap "on_exit 'run_remote_tests failed.'" EXIT
			run_remote_tests ${kernel_image} \
				${image_dir} ${tests_dir} ${results_dir}
		fi
	done
done

trap "on_exit 'Success.'" EXIT
exit 0
