# Debian plug-in routines for build-rootfs.sh.

debug_check() {
	local info=${1}

	echo "debug_check: (${info}) vvvv" >&2
	set +e
	${sudo} true
	mount
	${sudo} ls -l /var/run/sudo/ts
	set -e
	echo "debug_check: (${info}) ^^^^" >&2
}

bootstrap_rootfs() {
	local rootfs=${1}

	debug_check "${FUNCNAME[0]}:${LINENO}"

	(${sudo} debootstrap --foreign --arch ${target_arch} --no-check-gpg \
		${debian_os_release} ${rootfs} ${debian_os_mirror})

	debug_check "${FUNCNAME[0]}:${LINENO}"

	copy_qemu_static ${rootfs}

	${sudo} mount -l -t proc
	${sudo} ls -la ${rootfs}
	${sudo} find ${rootfs} -type l -exec ls -la {} \; | egrep ' -> /'
	${sudo} rm -f ${rootfs}/proc
	${sudo} mkdir -p  ${rootfs}/proc
	${sudo} mount -t proc -o nosuid,nodev,noexec /proc ${rootfs}/proc
	${sudo} mount -l -t proc

	${sudo} LANG=C.UTF-8 chroot ${rootfs} /bin/sh -x <<EOF
/debootstrap/debootstrap --second-stage
EOF

	${sudo} mount -l -t proc
	${sudo} umount ${rootfs}/proc | :
	${sudo} mount -l -t proc

	clean_qemu_static ${rootfs}

	debug_check "${FUNCNAME[0]}:${LINENO}"

	${sudo} sed --in-place 's/$/ contrib non-free/' \
		${rootfs}/etc/apt/sources.list

	enter_chroot ${rootfs} "
		export DEBIAN_FRONTEND=noninteractive
		apt-get update
	"

	debug_check "${FUNCNAME[0]}:${LINENO}"
}

rootfs_cleanup() {
	local rootfs=${1}

	debug_check "${FUNCNAME[0]}:${LINENO}"
	enter_chroot ${rootfs} "
		export DEBIAN_FRONTEND=noninteractive
		apt-get -y autoremove
		rm -rf /var/lib/apt/lists/*
	"
	debug_check "${FUNCNAME[0]}:${LINENO}"
}

setup_packages() {
	local rootfs=${1}
	shift 1
	local packages="${@//,/ }"

	debug_check "${FUNCNAME[0]}:${LINENO}"

	enter_chroot ${rootfs} "
		export DEBIAN_FRONTEND=noninteractive
		apt-get update
		apt-get -y upgrade
		apt-get -y install ${packages}
	"
	debug_check "${FUNCNAME[0]}:${LINENO}"

}

setup_initrd_boot() {
	local rootfs=${1}

	${sudo} ln -sf "lib/systemd/systemd" "${rootfs}/init"
	${sudo} cp -a "${rootfs}/etc/os-release" "${rootfs}/etc/initrd-release"
}

setup_network() {
	local rootfs=${1}

	setup_network_systemd ${rootfs}
}

setup_login() {
	local rootfs=${1}
	local pw=${2}

	setup_password ${rootfs} ${pw}

	${sudo} sed --in-place \
		's|-/sbin/agetty -o|-/sbin/agetty --autologin root -o|' \
		${rootfs}/lib/systemd/system/serial-getty@.service

	${sudo} sed --in-place \
		's|-/sbin/agetty -o|-/sbin/agetty --autologin root -o|' \
		${rootfs}/lib/systemd/system/getty@.service
}

setup_sshd() {
	local rootfs=${1}
	local srv_key=${2}

	sshd_config() {
		local key=${1}
		local value=${2}
		
		${sudo} sed --in-place "s/^${key}.*$//" \
			${rootfs}/etc/ssh/sshd_config
		echo "${key} ${value}" | sudo_append "${rootfs}/etc/ssh/sshd_config"
	}

	sshd_config "PermitRootLogin" "yes"
	sshd_config "UseDNS" "no"
	sshd_config "PermitEmptyPasswords" "yes"

	if [[ ! -f "${rootfs}/etc/ssh/ssh_host_rsa_key" ]]; then
		echo "${name}: ERROR: Not found: ${rootfs}/etc/ssh/ssh_host_rsa_key" >&2
		exit 1
	fi

	${sudo} cp -f ${rootfs}/etc/ssh/ssh_host_rsa_key ${srv_key}
	echo "${name}: USER=@$(id --user --real --name)@" >&2
	#printenv
	#${sudo} chown $(id --user --real --name): ${srv_key}
}

setup_relay_client() {
	local rootfs=${1}

	local tci_script="/bin/tci-relay-client.sh"
	local tci_service="tci-relay-client.service"

	write_tci_client_script "${rootfs}${tci_script}"

	sudo_write "${rootfs}/etc/systemd/system/${tci_service}" <<EOF
[Unit]
Description=TCI Relay Client Service
#Requires=network-online.target ssh.service
BindsTo=network-online.target ssh.service
After=network-online.target ssh.service default.target

[Service]
Type=simple
Restart=on-failure
RestartSec=30
StandardOutput=journal+console
StandardError=journal+console
ExecStart=${tci_script}

[Install]
WantedBy=default.target network-online.target
EOF

# FIXME
#[  139.055550] systemd-networkd-wait-online[2293]: Event loop failed: Connection timed out
#systemd-networkd-wait-online.service: Main process exited, code=exited, status=1/FAILURE
#systemd-networkd-wait-online.service: Failed with result 'exit-code'.
#Startup finished in 16.250s (kernel) + 0 (initrd) + 2min 2.838s (userspace) = 2min 19.089s.

	enter_chroot ${rootfs} "
		systemctl enable \
			${tci_service} \
			systemd-networkd-wait-online.service \
	"
}

debian_os_release="buster"
debian_os_mirror="http://ftp.us.debian.org/debian"

default_packages=${debian_default_packages:-"
	efibootmgr
	firmware-qlogic
	firmware-bnx2x
	haveged
	net-tools
	netcat-openbsd
	openssh-server
	pciutils
	strace
	tcpdump
"}
