#!/bin/sh
#
# This script will migrate a host's runtime to `containerd`.
# It applies to both managers and nodes.
#
# WARNING!
# This script assumes the cluster was deployed using `run-prereq.sh` from
# https://github.com/thecodewithin/k8s_multi-manager
# It does not uninstall docker, as it is used to generate the kube-vip manifest
#

# Business as usual, to begin with
apt update
apt -y full-upgrade

# Install a few niceties. Skip those that do not apply to your case
apt install -y vim apt-transport-https git curl wget ncat bash-completion nfs-client gnupg2 ca-certificates software-properties-common

# Install `containerd` as CRI runtime, as per the instructions on https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd

# Prerequisites:
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Configure containerd
[ ! -d "/etc/containerd/" ] && mkdir -p /etc/containerd
#containerd config default > /etc/containerd/config.toml
containerd config default | sed '/runtimes.runc.options]$/a\            SystemdCgroup = true' | sudo tee /etc/containerd/config.toml
# Restart containerd
systemctl restart containerd

# Configure Kubelet to use systemd as cgroup driver
cat /var/lib/kubelet/config.yaml | sed -e 's/cgroupDriver:.*/cgroupDriver: systemd/g' | sudo tee /var/lib/kubelet/config.yaml

# configure kubelet to use containerd as runtime
cat << EOF | sudo tee  /etc/systemd/system/kubelet.service.d/0-containerd.conf
[Service]
Environment="KUBELET_EXTRA_ARGS=--container-runtime=remote --runtime-request-timeout=15m --container-runtime-endpoint=unix:///run/containerd/containerd.sock"
EOF

# Upgrade kubeadm and friends
apt-mark unhold kubelet kubeadm kubectl
apt -y full-upgrade
apt-mark hold kubelet kubeadm kubectl
systemctl daemon-reload
systemctl restart kubelet

# Delete all docker containers
docker rm -f $(docker ps -aq)

# Clean up
apt -y autoremove
apt clean

# Restart the node
#shutdown -r now
echo "Please reboot this node at your earliest convenience"

