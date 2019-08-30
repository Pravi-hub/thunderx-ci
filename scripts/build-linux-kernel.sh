#!/usr/bin/env bash

usage() {
	local target_list="$(clean_ws ${targets})"
	local op_list="$(clean_ws ${ops})"

	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Builds linux kernel." >&2
	echo "Usage: ${name} [flags] <target> <kernel_src> <op>" >&2
	echo "Option flags:" >&2
	echo "  -b --build-dir     - Build directory. Default: '${build_dir}'." >&2
	echo "  -h --help          - Show this help and exit." >&2
	echo "  -i --install-dir   - Target install directory. Default: '${install_dir}'." >&2
	echo "  -l --local-version - Default: '${local_version}'." >&2
	echo "  -v --verbose       - Verbose execution." >&2
	echo "Args:" >&2
	echo "  <target>     - Build target {${target_list}}." >&2
	echo "                 Default: '${target}'." >&2
	echo "  <kernel-src> - Kernel source directory." >&2
	echo "                 Default: '${kernel_src}'." >&2
	echo "  <op>         - Build operation {${op_list}}." >&2
	echo "                 Default: '${op}'." >&2
	echo "Info:" >&2
	echo "  ${cpus} CPUs available." >&2

	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="b:hi:l:v"
	local long_opts="build-dir:,help,install-dir:,local-version:,verbose"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${name}" -- "$@")

	if [ $? != 0 ]; then
		echo "${name}: ERROR: Internal getopt" >&2
		exit 1
	fi

	eval set -- "${opts}"

	while true ; do
		case "${1}" in
		-b | --build-dir)
			build_dir="${2}"
			shift 2
			;;
		-h | --help)
			usage=1
			shift
			;;
		-l | --local-version)
			local_version="${2}"
			shift 2
			;;
		-t | --install-dir)
			install_dir="${2}"
			shift 2
			;;
		-v | --verbose)
			set -x
			verbose=1
			shift
			;;
		--)
			target=${2}
			kernel_src=${3}
			op=${4}
			if ! shift 4; then
				echo "${name}: ERROR: Missing args:" >&2
				echo "${name}:        <target>='${target}'" >&2
				echo "${name}:        <kernel_src>='${kernel_src}'" >&2
				echo "${name}:        <op>='${op}'" >&2
				usage
				exit 1
			fi
			if [[ -n "${1}" ]]; then
				echo "${name}: ERROR: Got extra args: '${@}'" >&2
				usage
				exit 1
			fi
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
	local result=${?}
	local end_time="$(date)"
	local sec="${SECONDS}"

	if [ -d ${tmp_dir} ]; then
		rm -rf ${tmp_dir}
	fi

	set +x
	echo "" >&2
	echo "${name}: Done:          result=${result}" >&2
	echo "${name}: target:        ${target}" >&2
	echo "${name}: op:            ${op}" >&2
	echo "${name}: kernel_src:    ${kernel_src}" >&2
	echo "${name}: build_dir:     ${build_dir}" >&2
	echo "${name}: install_dir:   ${install_dir}" >&2
	echo "${name}: local_version: ${local_version}" >&2
	echo "${name}: make_options:  ${make_options}" >&2
	echo "${name}: start_time:    ${start_time}" >&2
	echo "${name}: end_time:      ${end_time}" >&2
	echo "${name}: duration:      ${sec} sec ($(sec_to_min ${sec} min)" >&2
	exit ${result}
}

make_fresh() {
	cp ${build_dir}/.config ${tmp_dir}/config.tmp
	rm -rf ${build_dir}/{*,.*} &>/dev/null || :
	eval "make ${make_options} mrproper"
	eval "make ${make_options} defconfig"
	cp ${tmp_dir}/config.tmp ${build_dir}/.config
	eval "make ${make_options} olddefconfig"
}

make_targets() {
	eval "make ${make_options} savedefconfig"
	eval "make ${make_options} ${make_targets}"
}

install_image() {
	mkdir -p "${install_dir}/boot"
	cp ${build_dir}/{defconfig,System.map,vmlinux} ${install_dir}/boot/
	cp ${build_dir}/.config ${install_dir}/boot/config
	${target_tool_prefix}strip -s -R .comment ${build_dir}/vmlinux -o ${install_dir}/boot/vmlinux.strip

	if [[ -z ${target_copy} ]]; then
		eval "make ${make_options} install"
	else
		for ((i = 0; i <= ${#target_copy[@]} - 1; i+=2)); do
			cp --no-dereference ${build_dir}/${target_copy[i]} ${install_dir}/${target_copy[i+1]}
		done
	fi
	if [[ -n ${target_copy_opt} ]]; then
		for ((i = 0; i <= ${#target_copy_opt[@]} - 1; i+=2)); do
			if [[ -f ${target_copy_opt[i]} ]]; then
				cp --no-dereference ${build_dir}/${target_copy_opt[i]} ${install_dir}/${target_copy_opt[i+1]}
			fi
		done
	fi
}

install_modules() {
	mkdir -p "${install_dir}/lib/modules"
	eval "make ${make_options} modules_install"
}

#===============================================================================
# program start
#===============================================================================
export PS4='\[\033[0;33m\]+${BASH_SOURCE##*/}:${LINENO}: \[\033[0;37m\]'
set -e

name="${0##*/}"
trap "on_exit 'failed.'" EXIT

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
source ${SCRIPTS_TOP}/lib/util.sh

targets="
	amd64
	arm64
	arm64_be
	native
	ppc32
	ppc64
	ppc64le
	ps3
	x86_64
"
ops="
	all
	defconfig
	fresh
	headers
	install
	modules_install
	rebuild
	savedefconfig
	targets
	gconfig
	menuconfig
	oldconfig
	olddefconfig
	xconfig
"

cpus="$(cpu_count)"

process_opts "${@}"

if [[ -z "${build_dir}" ]]; then
	build_dir="$(pwd)/${target}-kernel-build"
fi

if [[ -z "${install_dir}" ]]; then
	#install_dir="/target/${target}"
	install_dir="${build_dir%-*}-install"
fi

if [[ -z "${local_version}" ]]; then
	local_version="${kernel_src##*/}"
fi

if [[ -n "${usage}" ]]; then
	usage
	exit 0
fi

check_directory "${kernel_src}" "" "usage"

if test -x "$(command -v ccache)"; then
	ccache='ccache '
else
	echo "${name}: INFO: Please install ccache"
fi

declare -a target_copy

case "${target}" in
amd64)
	target_tool_prefix=${target_tool_prefix:-"x86_64-linux-gnu-"}
	target_make_options="ARCH=x86_64 CROSS_COMPILE='${ccache}${target_tool_prefix}'"
	target_defconfig="${target}_defconfig"
	target_copy=(
		vmlinux boot/
	)
	;;
arm64|arm64_be)
	target_tool_prefix=${target_tool_prefix:-"aarch64-linux-gnu-"}
	target_make_options="ARCH=arm64 CROSS_COMPILE='${ccache}${target_tool_prefix}'"
	target_defconfig="defconfig"
	target_copy=(
		vmlinux boot/
		arch/arm64/boot/Image boot/
	)
	;;
native)
	target_make_options="CROSS_COMPILE='${ccache}'"
	target_defconfig="defconfig"
	make_targets="all"
	;;
ppc32|ppc64)
	target_tool_prefix=${target_tool_prefix:-"powerpc-linux-gnu-"}
	target_make_options="ARCH=powerpc CROSS_COMPILE='${ccache}${target_tool_prefix}'"
	target_defconfig="ppc64_defconfig"
	target_copy=(
		vmlinux boot/
	)
	;;
ppc64le)
	target_tool_prefix=${target_tool_prefix:-"powerpc64le-linux-gnu-"}
	target_make_options="ARCH=powerpc CROSS_COMPILE='${ccache}${target_tool_prefix}'"
	target_defconfig="defconfig"
	target_copy=(
		vmlinux boot/
	)
	;;
ps3)
	target_tool_prefix=${target_tool_prefix:-"powerpc-linux-gnu-"}
	target_make_options="ARCH=powerpc CROSS_COMPILE='""${ccache}${target_tool_prefix}""'"
	target_defconfig="${target}_defconfig"
	target_copy=(
		vmlinux boot/
		arch/powerpc/boot/dtbImage.ps3.bin boot/linux
	)
	target_copy_opt=(
		arch/powerpc/boot/otheros.bld boot/
	)
	;;
*)
	echo "${name}: ERROR: Unknown target: '${target}'" >&2
	usage
	exit 1
	;;
esac

if [[ -n "${verbose}" ]]; then
	make_options_extra="V=1"
fi

make_options="-j${cpus} ${target_make_options} INSTALL_MOD_PATH='${install_dir}' INSTALL_PATH='${install_dir}/boot' INSTALLKERNEL=non-existent-file O='${build_dir}' ${make_options_extra} ${make_options_user}"

start_time="$(date)"
SECONDS=0

export CCACHE_DIR=${CCACHE_DIR:-"${build_dir}.ccache"}

mkdir -p ${build_dir}
mkdir -p ${CCACHE_DIR}

cd ${kernel_src}

tmp_dir="$(mktemp --tmpdir --directory ${name}.XXXX)"

case "${op}" in
all)
	make_fresh
	make_targets
	install_image
	install_modules
	;;
defconfig)
	if [[ -n ${target_defconfig} ]]; then
		eval "make ${make_options} ${target_defconfig}"
	else
		eval "make ${make_options} defconfig"
	fi
	eval "make ${make_options} savedefconfig"
	;;
fresh)
	make_fresh
	;;
headers)
	eval "make ${make_options} mrproper"
	eval "make ${make_options} defconfig"
	eval "make ${make_options} prepare"
	;;
install)
	install_image
	install_modules
	;;
modules_install)
	install_modules
	;;
rebuild)
	eval "make ${make_options} clean"
	make_targets
	;;
savedefconfig)
	eval "make ${make_options} savedefconfig"
	;;
targets)
	make_targets
	;;
gconfig | menuconfig | oldconfig | olddefconfig | xconfig)
	eval "make ${make_options} ${op}"
	eval "make ${make_options} savedefconfig"
	;;
*)
	echo "${name}: INFO: Unknown op: '${op}'" >&2
	eval "make ${make_options} ${op}"
	;;
esac
