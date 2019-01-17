# CI for Cavium's ARM64 ThunderX processors

## ThunderX-CI tftpd Service

### Install Service

To build, install and start the ThunderX-CI tftpd service use the
[build-tftpd.sh](docker/tftpd/build-tftpd.sh) script:

```sh
sudo mkdir -p /var/tftproot
docker/tftpd/build-tftpd.sh --purge --install --enable --start
```

Once the [build-tftpd.sh](docker/tftpd/build-tftpd.sh) script has
completed the status of the tci-tftpd.service can be checked with commands
like these:

```sh
docker ps
sudo systemctl status tci-tftpd.service
```

Files are served from the `/var/tftproot/` directory.

### Check service status:

```sh
docker ps
sudo systemctl status tci-tftpd.service
```

### Stop service:

```sh
sudo systemctl stop tci-tftpd.service
```

### Run shell in tftpd container:

```sh
docker exec -it tci-tftpd.service bash
```

### Completely remove service from system:

```sh
sudo systemctl stop tci-tftpd.service
sudo systemctl disable tci-tftpd.service
sudo rm /etc/systemd/system/tci-tftpd.service
docker rm -f tci-tftpd.service
docker rmi -f tci-tftpd:1 alpine:latest
sudo rm -rf /var/tftproot
```

