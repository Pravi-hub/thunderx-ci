#!/usr/bin/env bash

clean_ws() {
	local in="$*"

	shopt -s extglob
	in="${in//+( )/ }" in="${in# }" in="${in% }"
	echo -n "$in"
}

sec_to_min() {
	local sec=${1}
	local min="$((sec / 60))"
	local frac="$(((sec * 100) / 60))"
	local len=${#frac}

	if [[ ${len} -eq 1 ]]; then
		frac="0${frac}"
	elif [[ ${len} -gt 2 ]]; then
		frac=${frac:(-2)}
	fi
	echo "${min}.${frac}"
}

sec_to_min_bc() {
	local sec=${1}
	echo "scale=2; ${sec}/60" | bc -l | sed 's/^\./0./'
}

directory_size_bytes() {
	local dir=${1}

	local size="$(du -sb ${dir})"
	echo ${size%%[[:space:]]*}
}

directory_size_human() {
	local dir=${1}

	local size
	size="$(du -sh ${dir})"
	echo ${size%%[[:space:]]*}
}

check_directory() {
	local src="${1}"
	local msg="${2}"
	local usage="${3}"

	if [[ ! -d "${src}" ]]; then
		echo "${name}: ERROR: Directory not found${msg}: '${src}'" >&2
		[[ -z "${usage}" ]] || usage
		exit 1
	fi
}

check_file() {
	local src="${1}"
	local msg="${2}"
	local usage="${3}"

	if [[ ! -f "${src}" ]]; then
		echo -e "${name}: ERROR: File not found${msg}: '${src}'" >&2
		[[ -z "${usage}" ]] || usage
		exit 1
	fi
}

check_opt() {
	option=${1}
	shift
	value=${@}

	if [[ ! ${value} ]]; then
		echo "${name}: ERROR: Must provide --${option} option." >&2
		usage
		exit 1
	fi
}

relative_path() {
	local base="${1}"
	local target="${2}"
	local root="${3}"

	base="${base##${root}}"
	base="${base%%/}"
	base=${base%/*}
	target="${target%%/}"

	local back=""
	while :; do
		#echo "target: ${target}" >&2
		#echo "base:   ${base}" >&2
		#echo "back:   ${back}" >&2
		if [[ "${base}" == "/" || "${target}" == ${base}/* ]]; then
			break
		fi
		back+="../"
		base=${base%/*}
	done

	echo "${back}${target##${base}/}"
}

copy_file() {
	local src="${1}"
	local dest="${2}"

	check_file ${src}
	cp -f ${src} ${dest}
}

cpu_count() {
	echo "$(getconf _NPROCESSORS_ONLN || echo 1)"
}

get_user_home() {
	local user=${1}
	local result;

	if ! result="$(getent passwd ${user})"; then
		echo "${name}: ERROR: No home for user '${user}'" >&2
		exit 1
	fi
	echo ${result} | cut -d ':' -f 6
}

get_arch() {
	local a=${1}

	case "${a}" in
	arm64|aarch64) echo "arm64" ;;
	amd64|x86_64)  echo "amd64" ;;
	*)
		echo "${name}: ERROR: Bad arch '${a}'" >&2
		exit 1
		;;
	esac
}

sudo_write() {
	sudo tee "${1}" >/dev/null
}

sudo_append() {
	sudo tee -a "${1}" >/dev/null
}

is_ip_addr() {
	local host=${1}
	local regex_ip="[[:digit:]]{1,3}\.[[:digit:]]{1,3}{3}"

	[[ "${host}" =~ ${regex_ip} ]]
}

find_addr() {
	local -n _find_addr__addr=${1}
	local hosts_file=${2}
	local host=${3}

	_find_addr__addr=""

	if is_ip_addr ${host}; then
		_find_addr__addr=${host}
		return
	fi

	if [[ ! -x "$(command -v dig)" ]]; then
		echo "${name}: WARNING: Please install dig (dnsutils)." >&2
	else
		_find_addr__addr="$(dig ${host} +short)"
	fi

	if [[ ! ${_find_addr__addr} ]]; then
		_find_addr__addr="$(egrep -m 1 "${host}[[:space:]]*$" ${hosts_file} \
			| egrep -o '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' || :)"

		if [[ ! ${_find_addr__addr} ]]; then
			echo "${name}: ERROR: '${host}' DNS entry not found." >&2
			exit 1
		fi
	fi
}

my_addr() {
	ip route get 8.8.8.8 | egrep -o 'src [0-9.]*' | cut -f 2 -d ' '
}

wait_pid() {
	local pid="${1}"
	local timeout_sec=${2}
	timeout_sec=${timeout_sec:-300}

	echo "${name}: INFO: Waiting ${timeout_sec}s for pid ${pid}." >&2

	let count=1
	while kill -0 ${pid} &> /dev/null; do
		let count=count+5
		if [[ count -gt ${timeout_sec} ]]; then
			echo "${name}: ERROR: wait_pid failed for pid ${pid}." >&2
			exit -1
		fi
		sleep 5s
	done
}

git_checkout() {
	local dir=${1}
	local repo=${2}
	local branch=${3:-'master'}

	if [[ ! -d "${dir}" ]]; then
		mkdir -p "${dir}/.."
		git clone ${repo} "${dir}"
	fi

	git -C ${dir} remote update
	git -C ${dir} checkout --force ${branch}
	git -C ${dir} pull
}

if [[ ${PS4} == '+ ' ]]; then
	if [[ ${JENKINS_URL} ]]; then
		export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '
	else
		export PS4='\[\033[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}: \[\033[0;37m\]'
	fi
fi

known_rootfs_types="
	alpine
	debian
"

known_test_types="
	http-wrk
	ltp
	sys-info
	unixbench
"

MODULES_ID=${MODULES_ID:-"kernel_modules"}
TARGET_HOSTNAME=${TARGET_HOSTNAME:-"tci-tester"}
