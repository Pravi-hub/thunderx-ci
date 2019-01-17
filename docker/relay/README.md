# CI for Cavium's ARM64 ThunderX processors

## ThunderX-CI tci-relay Service

### Install Service

To build, install and start the tci-relay service use the
[build-relay.sh](docker/relay/build-relay.sh) script:

```sh
docker/relay/build-relay.sh --purge --install --enable --start
```

Once the [build-relay.sh](docker/relay/build-relay.sh) script has
completed the tci-relay service can be managed with commands
like these:

### Check service status:

```sh
docker ps
sudo systemctl status tci-relay.service
```

### Stop service:

```sh
sudo systemctl stop tci-relay.service
```

### Run shell in tci-relay container:

```sh
docker exec -it tci-relay.service bash
```

### Rebuild tci-relay container:

```sh
sudo systemctl stop tci-relay
docker/relay/build-relay.sh -p
sudo systemctl start tci-relay
```

### Completely remove service from system:

```sh
sudo systemctl stop tci-relay.service
sudo systemctl disable tci-relay.service
sudo rm /etc/systemd/system/tci-relay.service
docker rm -f tci-relay.service
docker rmi -f tci-relay:1 alpine:latest
sudo rm -rf /var/tftproot
```

