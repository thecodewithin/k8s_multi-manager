#!/bin/sh
#
# This script will prepare the software load balancer for the control plane
# and start the cluster on the first node
# Then it will allow your non-root user to interact with it and install a 
# Container Network Interface (CNI)
#

# Creating a kube-vip manifest so the software load balancer will start with the cluster
docker run -it --rm plndr/kube-vip:0.1.1 /kube-vip sample manifest     | sed "s|plndr/kube-vip:'|plndr/kube-vip:0.1.1'|"     | sudo tee /etc/kubernetes/manifests/kube-vip.yaml

# Initializing the cluster
sudo kubeadm init --pod-network-cidr=10.100.0.0/16 --control-plane-endpoint "k8sclps1:8443" --apiserver-bind-port 6444 --upload-certs

# Allowing your regular user to interact with the cluster 
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Installing Calico as Container Network Interface, as recommended in the documentation here:
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#pod-network
kubectl apply -f https://docs.projectcalico.org/v3.16/manifests/calico.yaml

