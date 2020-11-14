#!/bin/sh
#
# This code will prepare the hosts to be part of a Kubernetes cluster.
# It applies to both managers and nodes. If your cluster consists of VMs of some flavor,
# it can be used to build a template, so it only has to be run once.
#

# Business as usual, to begin with
apt update
apt -y upgrade
apt -y dist-upgrade
apt -y full-upgrade

# Install a few niceties. Skip those that do not apply to your case
apt install -y qemu-guest-agent apt-transport-https git curl wget ncat bash-completion

# Prepare the firewall as per
# https://github.com/rancher/k3s/issues/24#issuecomment-668315466
# Adapt the IPs according to your choice of `pod-network-cidr`
iptables -I INPUT 1 -i cni0 -s 10.100.0.0/16 -j ACCEPT
iptables -I FORWARD 1 -s 10.100.0.0/15 -j ACCEPT

# Make the rules permanent
iptables-save > /etc/iptables.up.rules
cat <<EOF | sudo tee /etc/network/if-pre-up.d/iptables
#!/bin/sh
/sbin/iptables-restore < /etc/iptables.up.rules
EOF
 
chmod +x /etc/network/if-pre-up.d/iptables 

# Install docker the easy way
curl https://get.docker.com | bash

# Optional. Uncomment if you want to execute `docker` commands without sudo
# Substitute your non-root user for "<your-user>" 
#usermod -G docker <your-user>

# This comes handy if you are going to deploy an ELK stack in this cluster.
# Feel free to comment it out otherwise.
echo "vm.max_map_count=262144" >> /etc/sysctl.conf

# Start with the kubeadm requirements, as per the documentation you'll find
# here: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#letting-iptables-see-bridged-traffic
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sysctl --system

# Installing kubeadm and friends as described in the documentation here:
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF

# Let's go!
apt update
apt install -y kubelet kubeadm kubectl

# Prevent these packages from being upgraded. This is recommended so new versions won't accidentally 
# break your cluster. Comment it out if you feel brave.
apt-mark hold kubelet kubeadm kubectl

# A very handy tool to have when operating with `kubectl` commands. You can either enable it locally to 
# your user (uncomment the line right below)
#echo 'source <(kubectl completion bash)' >> /home/<your-user>/.bashrc
# or enable it system-wide like this:
kubectl completion bash > /etc/bash_completion.d/kubectl

# Done. On to the next step.
