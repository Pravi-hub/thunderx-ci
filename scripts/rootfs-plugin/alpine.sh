# Alpine linux plug-in routines for build-rootfs.sh.

download_minirootfs() {
	local download_dir=${1}
	local -n _download_minirootfs__archive_file=${3}

	unset _download_minirootfs__archive_file

	case "${target_arch}" in
		amd64) 	alpine_arch="x86_64" ;;
		arm64) 	alpine_arch="aarch64" ;;
		*)
			echo "${name}: ERROR: Unsupported target arch '${target_arch}'." >&2
			exit 1
			;;
	esac
	local base_url="${alpine_os_mirror}/${alpine_arch}"

	mkdir -p ${download_dir}
	pushd ${download_dir}

	local releases_yaml="latest-releases.yaml"
	wget "${base_url}/${releases_yaml}"

	local latest
	latest="$(egrep --only-matching "file: alpine-minirootfs-[0-9.]*-${alpine_arch}.tar.gz" ${releases_yaml})"
	if [[ ! ${latest} ]]; then
		echo "${name}: ERROR: Bad releases file '${releases_yaml}'." >&2
		cat ${releases_yaml}
		exit 1
	fi
	latest=${latest##* }
	wget "${base_url}/${latest}"

	popd
	echo "${name}: INFO: Download '${latest}'." >&2
	_download_minirootfs__archive_file="${download_dir}/${latest}"
}

extract_minirootfs() {
	local archive=${1}
	local out_dir=${2}

	mkdir -p ${out_dir}
	tar -C ${out_dir} -xf ${archive}
}

bootstrap_rootfs() {
	local rootfs=${1}

	local download_dir="${tmp_dir}/downloads"
	local archive_file

	${sudo} rm -rf ${rootfs}

	download_minirootfs ${download_dir} ${alpine_os_mirror} archive_file
	extract_minirootfs ${archive_file} ${rootfs}

	rm -rf ${download_dir}

	setup_resolv_conf ${rootfs}

	enter_chroot ${rootfs} "
		set -e
		apk update
		apk upgrade
		apk add openrc busybox-initscripts
		cat /etc/os-release
		apk info | sort
	"

	${sudo} ln -s /etc/init.d/{hwclock,modules,sysctl,hostname,bootmisc,syslog} \
		${rootfs}/etc/runlevels/boot/
	${sudo} ln -s /etc/init.d/{devfs,dmesg,mdev,hwdrivers} \
		${rootfs}/etc/runlevels/sysinit/
	${sudo} ln -s /etc/init.d/{networking} \
		${rootfs}/etc/runlevels/default/
	${sudo} ln -s /etc/init.d/{mount-ro,killprocs,savecache} \
		${rootfs}/etc/runlevels/shutdown/

	${sudo} sed --in-place 's/^net.ipv4.tcp_syncookies/# net.ipv4.tcp_syncookies/' \
		${rootfs}/etc/sysctl.d/00-alpine.conf
	${sudo} sed --in-place 's/^kernel.panic/# kernel.panic/' \
		${rootfs}/etc/sysctl.d/00-alpine.conf
}

setup_network() {
	local rootfs=${1}

	setup_network_ifupdown ${rootfs}
}

rootfs_cleanup() {
	local rootfs=${1}

	#${sudo} rm -rf ${rootfs}/var/cache/apk
}

setup_packages() {
	local rootfs=${1}
	shift 1
	local packages="${@//,/ }"

	enter_chroot ${rootfs} "
		set -e
		apk add haveged dropbear dropbear-scp ${packages}
		apk add efibootmgr --repository http://dl-3.alpinelinux.org/alpine/edge/testing/ --allow-untrusted
		apk info | sort
	"

	${sudo} ln -s /etc/init.d/{haveged,dropbear} \
		${rootfs}/etc/runlevels/sysinit/
}

setup_initrd_boot() {
	local rootfs=${1}

	ln -s sbin/init ${rootfs}/init
}

setup_login() {
	local rootfs=${1}
	local pw=${2}

	setup_password ${rootfs} ${pw}

	${sudo} sed --in-place \
		's|/sbin/getty|/sbin/getty -n -l /bin/sh|g' \
		${rootfs}/etc/inittab

	${sudo} sed --in-place \
		's|#ttyS0|ttyS0|g' \
		${rootfs}/etc/inittab
}

setup_sshd() {
	local rootfs=${1}
	local srv_key=${2}

	enter_chroot ${rootfs} "
		set -e
		mkdir -p /etc/dropbear/
		/usr/bin/dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
		/usr/bin/dropbearkey -t dss -f /etc/dropbear/dropbear_dss_host_key
		/usr/bin/dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key
	"

	#echo "${name}: USER=@$(id --user --real --name)@" >&2
	${sudo} cp -f "${rootfs}/etc/dropbear/dropbear_rsa_host_key" ${srv_key}
	${sudo} chown $(id --user --real --name): ${srv_key}

	#echo 'DROPBEAR_OPTS=""' | sudo_write ${rootfs}/etc/conf.d/dropbear
}


setup_relay_client() {
	local rootfs=${1}

	local tci_script="/bin/tci-relay-client.sh"
	local tci_service="/etc/init.d/tci-relay-client"

	write_tci_client_script ${rootfs}/${tci_script}

	sudo_write "${rootfs}/${tci_service}" <<EOF
#!/sbin/openrc-run

depend() {
	need net
	after firewall dropbear
}

command="${tci_script}"
pidfile="/run/\${RC_SVCNAME}.pid"
#command_background=true
EOF

	${sudo} chmod u+x ${rootfs}/${tci_service}
	${sudo} ln -s ${tci_service} ${rootfs}/etc/runlevels/sysinit/
}


alpine_os_mirror="http://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/"

default_packages=${alpine_default_packages:-"
	net-tools
	netcat-openbsd
	pciutils
	strace
	tcpdump
"}
