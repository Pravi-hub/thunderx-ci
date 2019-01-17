# ThunderX-CI image for compiling linux kernel, creating test rootfs, running QEMU.

ARG DOCKER_FROM

FROM ${DOCKER_FROM}

ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

ENV TCI_BUILDER 1

RUN echo 'deb-src http://deb.debian.org/debian buster main' >> /etc/apt/sources.list \
	&& apt-get update \
	&& apt-get -y upgrade \
	&& DEBIAN_FRONTEND=noninteractive apt-get -y install \
		apt-utils \
		bash \
		bash-completion \
		binfmt-support \
		ccache \
		debootstrap \
		dnsutils \
		dosfstools \
		git \
		gcc-x86-64-linux-gnu \
		inotify-tools \
		ipmitool \
		isc-dhcp-server \
		libncurses5-dev \
		netcat-openbsd \
		net-tools \
		ovmf \
		procps \
		qemu-system-x86-64 \
		qemu-user-static \
		qemu-utils \
		sudo \
		tcpdump \
		tftp-hpa \
		vim \
		wget \
	&& apt-get -y build-dep linux \
	&& DEBIAN_FRONTEND=noninteractive apt-get -y install \
		gcc-aarch64-linux-gnu \
		qemu-efi-aarch64 \
		qemu-system-aarch64 \
	&& DEBIAN_FRONTEND=noninteractive apt-get -y autoremove \
	&& rm -rf /var/lib/apt/lists/* \
	&& mv /usr/sbin/tcpdump /usr/bin/tcpdump

CMD /bin/bash
