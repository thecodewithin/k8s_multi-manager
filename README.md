# k8s_multi-manager

*My first (kinda successful) try at deploying a multi-manager Kubernetes cluster, step by step.*

***

In this example we are going to deploy a 6 node Kubernetes cluster, 3 managers and 3 nodes, following the official documentation from https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/, a MetalLB load balancer and Traefik v2.3.3


My setup:
 - **6 VMs** on a Proxmox:
   - Debian 10
   - 8GB of RAM 
   - without swap space
   - 2 CPUs
 - **container runtime**: Docker
 - **software load balancing**: kube-vip
 - **cluster approach**: stacked control plane nodes
 - **Container Network Interface**: Cilium
 - **Storage**: nfs server, 192.168.1.xxx
 - **Load Balancer IP**: 192.168.1.30

The hosts:

| Role | IP | Hostname |
|:----|:----|:----|
|Manager | 192.168.1.23 | k8sclp01 |
|Manager | 192.168.1.24 | k8sclp02 |
|Manager | 192.168.1.25 | k8sclp03 |
|Node | 192.168.1.26 | k8sclp04 |
|Node | 192.168.1.27 | k8sclp05 |
|Node | 192.168.1.28 | k8sclp06 |
|VIP | 192.168.1.20 | k8sclps1 |

## TL;DR;

 1. As root, run `run-prereq.sh` on all your cluster hosts, managers and nodes alike
 1. Reserve an IP in your network for your control plane's VIP
 1. Add your non-root user to the `docker` group and switch to your non-root user  
    `usermod -G docker <your-non-root-user>`
 1. Create a `/etc/kube-vip/config.yaml` file for the "Kube-VIP" on each manager (see below)
 1. Run `run-1stmngr.sh` on the first manager
 1. One by one, join the other managers
 1. Add the other managers to the VIP
 1. Install the Container Network Interface
 1. One by one, join the nodes
 1. Install Helm v3
 1. Install MetalLB
 1. Install nfs-client-provisioner
 1. Install Traefik 2.3.3
 1. Install External-DNS
 1. Sprinkle some cheese on top of it

## Set up the Kubernetes cluster, step by step

### Before you start

When creating a multi-master Kubernetes cluster, a load balancer for the kube-apiserver is needed, so reserve an IP in your network with a corresponding FQDN. In this example I'll use 192.168.1.20, paired with k8sclps1.mydomain.local.

You should also add your non-root user to the `docker` group. You can have `run-prereq.sh` do it for you by uncommenting that line on the script and substituting your user name in it.

In order for Traefik to work, a Load Balancer is needed to provide it with an IP. To that efect, reserve (at least) one IP for the MetalLB Load Balancer configuration. I'll use 192.168.1.30.

### On all hosts

If you are on bare metal, have all your Kubernetes hosts ready and copy and run `run-prereq.sh` on each and all of them, managers and nodes alike.

If you are on a VM environment, have just one VM ready, copy and run `run-prereq.sh` on it and turn the VM into a template. Now you can create all your Kubernetes hosts from this template.

Either way, I recommend you take a look at the code to see what it's doing. It's pretty straightforward and has links to the documentation.

### On the first manager

Create a configuraton file for the kube-apiserver load balancer. Check the docs here: https://kube-vip.io/control-plane/ and here: https://github.com/kubernetes/kubeadm/blob/master/docs/ha-considerations.md#kube-vip To do so, create the directory where the config is expected

```console
thecodewithin@k8sclp01:~$ sudo mkdir /etc/kube-vip
```
Then create a file named `config.yaml` whith the following contents:

```console
thecodewithin@k8sclp01:~$ sudo vi /etc/kube-vip/config.yaml 
```
```yaml
AddPeersAsBackends: false
Address: ""
BGPConfig:
  AS: 0
  IPv6: false
  NextHop: ""
  Peers: null
  RouterID: ""
  SourceIF: ""
  SourceIP: ""
BGPPeerConfig:
  AS: 0
  Address: ""
EnableBGP: false
EnableLeaderElection: false
EnableLoadBalancer: true
EnablePacket: false
GratuitousARP: true
Interface: ens18
LeaseDuration: 0
LoadBalancers:
- BackendPort: 0
  Backends:
  - Address: 192.168.1.21
    ParsedURL: null
    Port: 6444
    RawURL: ""
  - Address: 192.168.1.22
    ParsedURL: null
    Port: 6444
    RawURL: ""
  - Address: 192.168.1.23
    ParsedURL: null
    Port: 6444
    RawURL: ""
  BindToVip: true
  Name: Kubernetes Control Plane
  Port: 8443
  Type: tcp
LocalPeer:
  Address: 192.168.1.21
  ID: k8sclp01
  Port: 10000
PacketAPIKey: ""
PacketProject: ""
RemotePeers:
- Address: 192.168.1.22
  ID: k8sclp02
  Port: 10000
- Address: 192.168.1.23
  ID: k8sclp03
  Port: 10000
RenewDeadline: 0
RetryPeriod: 0
SingleNode: false
StartAsLeader: true
VIP: 192.168.1.20
VIPCIDR: ""
```

Clone this repository to your first manager. Run `run-1stmngr.sh`. Again, take a look at the script to see what it does.

This script will 
 - create a manifest for the kube-vip, the software load balancing I choose for the kube-apiserver, using the config you just created, so it will start up together with the cluster 
 - it will then initiate the cluster on your first node
 - and prepare your non-root user to interact with the kubernetes API through `kubectl` commands

#### Initiating the cluster

When the cluster is initiated with `kubeadm init <...>` the output will contain the necessary commands to join the other managers, as well as the nodes. It will look something like this:

```console
W1031 19:07:41.748567  127070 configset.go:348] WARNING: kubeadm cannot validate component configs for API groups [kubelet.config.k8s.io kubeproxy.config.k8s.io]
[init] Using Kubernetes version: v1.19.3
[preflight] Running pre-flight checks
	[WARNING IsDockerSystemdCheck]: detected "cgroupfs" as the Docker cgroup driver. The recommended driver is "systemd". Please follow the guide at https://kubernetes.io/docs/setup/cri/
	[WARNING SystemVerification]: missing optional cgroups: hugetlb
[preflight] Pulling images required for setting up a Kubernetes cluster
[preflight] This might take a minute or two, depending on the speed of your internet connection
[preflight] You can also perform this action in beforehand using 'kubeadm config images pull'
[certs] Using certificateDir folder "/etc/kubernetes/pki"
[certs] Generating "ca" certificate and key
[certs] Generating "apiserver" certificate and key
[certs] apiserver serving cert is signed for DNS names [k8sclp01 k8sclps1 kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local] and IPs [10.96.0.1 192.168.1.23]
[certs] Generating "apiserver-kubelet-client" certificate and key
[certs] Generating "front-proxy-ca" certificate and key
[certs] Generating "front-proxy-client" certificate and key
[certs] Generating "etcd/ca" certificate and key
[certs] Generating "etcd/server" certificate and key
[certs] etcd/server serving cert is signed for DNS names [k8sclp01 localhost] and IPs [192.168.1.23 127.0.0.1 ::1]
[certs] Generating "etcd/peer" certificate and key
[certs] etcd/peer serving cert is signed for DNS names [k8sclp01 localhost] and IPs [192.168.1.23 127.0.0.1 ::1]
[certs] Generating "etcd/healthcheck-client" certificate and key
[certs] Generating "apiserver-etcd-client" certificate and key
[certs] Generating "sa" key and public key
[kubeconfig] Using kubeconfig folder "/etc/kubernetes"
[endpoint] WARNING: port specified in controlPlaneEndpoint overrides bindPort in the controlplane address
[kubeconfig] Writing "admin.conf" kubeconfig file
[endpoint] WARNING: port specified in controlPlaneEndpoint overrides bindPort in the controlplane address
[kubeconfig] Writing "kubelet.conf" kubeconfig file
[endpoint] WARNING: port specified in controlPlaneEndpoint overrides bindPort in the controlplane address
[kubeconfig] Writing "controller-manager.conf" kubeconfig file
[endpoint] WARNING: port specified in controlPlaneEndpoint overrides bindPort in the controlplane address
[kubeconfig] Writing "scheduler.conf" kubeconfig file
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Starting the kubelet
[control-plane] Using manifest folder "/etc/kubernetes/manifests"
[control-plane] Creating static Pod manifest for "kube-apiserver"
[control-plane] Creating static Pod manifest for "kube-controller-manager"
[control-plane] Creating static Pod manifest for "kube-scheduler"
[etcd] Creating static Pod manifest for local etcd in "/etc/kubernetes/manifests"
[wait-control-plane] Waiting for the kubelet to boot up the control plane as static Pods from directory "/etc/kubernetes/manifests". This can take up to 4m0s
[apiclient] All control plane components are healthy after 18.029906 seconds
[upload-config] Storing the configuration used in ConfigMap "kubeadm-config" in the "kube-system" Namespace
[kubelet] Creating a ConfigMap "kubelet-config-1.19" in namespace kube-system with the configuration for the kubelets in the cluster
[upload-certs] Storing the certificates in Secret "kubeadm-certs" in the "kube-system" Namespace
[upload-certs] Using certificate key:
403b0f2b3947be4160b0f31d090930ba239fca1c2b6024c0b1b71dabfc5b5fb6
[mark-control-plane] Marking the node k8sclp01 as control-plane by adding the label "node-role.kubernetes.io/master=''"
[mark-control-plane] Marking the node k8sclp01 as control-plane by adding the taints [node-role.kubernetes.io/master:NoSchedule]
[bootstrap-token] Using token: rgh8a9.vh1mzx5l9m79c38a
[bootstrap-token] Configuring bootstrap tokens, cluster-info ConfigMap, RBAC Roles
[bootstrap-token] configured RBAC rules to allow Node Bootstrap tokens to get nodes
[bootstrap-token] configured RBAC rules to allow Node Bootstrap tokens to post CSRs in order for nodes to get long term certificate credentials
[bootstrap-token] configured RBAC rules to allow the csrapprover controller automatically approve CSRs from a Node Bootstrap Token
[bootstrap-token] configured RBAC rules to allow certificate rotation for all node client certificates in the cluster
[bootstrap-token] Creating the "cluster-info" ConfigMap in the "kube-public" namespace
[kubelet-finalize] Updating "/etc/kubernetes/kubelet.conf" to point to a rotatable kubelet client certificate and key
[addons] Applied essential addon: CoreDNS
[endpoint] WARNING: port specified in controlPlaneEndpoint overrides bindPort in the controlplane address
[addons] Applied essential addon: kube-proxy

Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

You can now join any number of the control-plane node running the following command on each as root:

  kubeadm join k8sclps1:8443 --token rgh8a9.vh1mzx5l9m79c38a \
    --discovery-token-ca-cert-hash sha256:b78bbe13037b9bb03640051cdf1d5037566db5b31e6a5dd80c6ca5274ad72094 \
    --control-plane --certificate-key 403b0f2b3947be4160b0f31d090930ba239fca1c2b6024c0b1b71dabfc5b5fb6

Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
As a safeguard, uploaded-certs will be deleted in two hours; If necessary, you can use
"kubeadm init phase upload-certs --upload-certs" to reload certs afterward.

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join k8sclps1:8443 --token rgh8a9.vh1mzx5l9m79c38a \
    --discovery-token-ca-cert-hash sha256:b78bbe13037b9bb03640051cdf1d5037566db5b31e6a5dd80c6ca5274ad72094 
```

Take note of the two `kubeadm join <...>` commands. You'll need them in a moment.

#### Check the pods

Give the newly started cluster a few moments and then check whether all the pods are running. Run this command as a regular user:

```console
thecodewithin@k8sclp01:~$ kubectl get pods --all-namespaces
```
You should see an output similar to this:

```console
NAMESPACE     NAME                                     READY   STATUS    RESTARTS   AGE
kube-system   coredns-f9fd979d6-hnt2d                  0/1     Pending   0          2m49s
kube-system   coredns-f9fd979d6-tvws7                  0/1     Pending   0          2m49s
kube-system   etcd-k8sclp01                           1/1     Running   0          2m57s
kube-system   kube-apiserver-k8sclp01                 1/1     Running   0          2m58s
kube-system   kube-controller-manager-k8sclp01        1/1     Running   0          2m58s
kube-system   kube-proxy-f5h8k                         1/1     Running   0          2m49s
kube-system   kube-scheduler-k8sclp01                 1/1     Running   0          2m58s
kube-system   kube-vip-k8sclp01                       1/1     Running   0          2m57s
```

The two `coredns` pods will not start until the CNI is properly installed.

### Add the other managers to the control plane

Now, on each of the remaining managers, create the kube-apiserver load balancer's configuration file. Be careful to change the `LocalPeer` and `RemotePeers` configurations and to set `StartAsLeader` to `false` for each of them.

Then create the manifests. See examples below.

This is for the second manager:

```console
thecodewithin@k8sclp02:~$ sudo mkdir /etc/kube-vip

thecodewithin@k8sclp02:~$ sudo vi /etc/kube-vip/config.yaml 
```
```yaml
AddPeersAsBackends: false
Address: ""
BGPConfig:
  AS: 0
  IPv6: false
  NextHop: ""
  Peers: null
  RouterID: ""
  SourceIF: ""
  SourceIP: ""
BGPPeerConfig:
  AS: 0
  Address: ""
EnableBGP: false
EnableLeaderElection: false
EnableLoadBalancer: true
EnablePacket: false
GratuitousARP: true
Interface: ens18
LeaseDuration: 0
LoadBalancers:
- BackendPort: 0
  Backends:
  - Address: 192.168.1.21
    ParsedURL: null
    Port: 6444
    RawURL: ""
  - Address: 192.168.1.22
    ParsedURL: null
    Port: 6444
    RawURL: ""
  - Address: 192.168.1.23
    ParsedURL: null
    Port: 6444
    RawURL: ""
  BindToVip: true
  Name: Kubernetes Control Plane
  Port: 8443
  Type: tcp
LocalPeer:
  Address: 192.168.1.22
  ID: k8sclp02
  Port: 10000
PacketAPIKey: ""
PacketProject: ""
RemotePeers:
- Address: 192.168.1.21
  ID: k8sclp01
  Port: 10000
- Address: 192.168.1.23
  ID: k8sclp03
  Port: 10000
RenewDeadline: 0
RetryPeriod: 0
SingleNode: false
StartAsLeader: false
VIP: 192.168.1.20
VIPCIDR: ""
```

And for the third one:

```console
thecodewithin@k8sclp03:~$ sudo mkdir /etc/kube-vip

thecodewithin@k8sclp03:~$ sudo vi /etc/kube-vip/config.yaml
```
```yaml
AddPeersAsBackends: false
Address: ""
BGPConfig:
  AS: 0
  IPv6: false
  NextHop: ""
  Peers: null
  RouterID: ""
  SourceIF: ""
  SourceIP: ""
BGPPeerConfig:
  AS: 0
  Address: ""
EnableBGP: false
EnableLeaderElection: false
EnableLoadBalancer: true
EnablePacket: false
GratuitousARP: true
Interface: ens18
LeaseDuration: 0
LoadBalancers:
- BackendPort: 0
  Backends:
  - Address: 192.168.1.21
    ParsedURL: null
    Port: 6444
    RawURL: ""
  - Address: 192.168.1.22
    ParsedURL: null
    Port: 6444
    RawURL: ""
  - Address: 192.168.1.23
    ParsedURL: null
    Port: 6444
    RawURL: ""
  BindToVip: true
  Name: Kubernetes Control Plane
  Port: 8443
  Type: tcp
LocalPeer:
  Address: 192.168.1.23
  ID: k8sclp03
  Port: 10000
PacketAPIKey: ""
PacketProject: ""
RemotePeers:
- Address: 192.168.1.22
  ID: k8sclp02
  Port: 10000
- Address: 192.168.1.21
  ID: k8sclp01
  Port: 10000
RenewDeadline: 0
RetryPeriod: 0
SingleNode: false
StartAsLeader: false
VIP: 192.168.1.20
VIPCIDR: ""
```

Now we can join the managers to the cluster.

First on the second manager:

```console
thecodewithin@k8sclp02:~$ sudo kubeadm join k8sclps1:8443 --token rgh8a9.vh1mzx5l9m79c38a     --discovery-token-ca-cert-hash sha256:b78bbe13037b9bb03640051cdf1d5037566db5b31e6a5dd80c6ca5274ad72094     --control-plane --certificate-key 403b0f2b3947be4160b0f31d090930ba239fca1c2b6024c0b1b71dabfc5b5fb6
[preflight] Running pre-flight checks
	[WARNING IsDockerSystemdCheck]: detected "cgroupfs" as the Docker cgroup driver. The recommended driver is "systemd". Please follow the guide at https://kubernetes.io/docs/setup/cri/
	[WARNING SystemVerification]: missing optional cgroups: hugetlb
[preflight] Reading configuration from the cluster...
[preflight] FYI: You can look at this config file with 'kubectl -n kube-system get cm kubeadm-config -oyaml'
[preflight] Running pre-flight checks before initializing the new control plane instance
[preflight] Pulling images required for setting up a Kubernetes cluster
[preflight] This might take a minute or two, depending on the speed of your internet connection
[preflight] You can also perform this action in beforehand using 'kubeadm config images pull'
[download-certs] Downloading the certificates in Secret "kubeadm-certs" in the "kube-system" Namespace
[certs] Using certificateDir folder "/etc/kubernetes/pki"
[certs] Generating "etcd/peer" certificate and key
[certs] etcd/peer serving cert is signed for DNS names [k8sclp02 localhost] and IPs [192.168.1.24 127.0.0.1 ::1]
[certs] Generating "etcd/healthcheck-client" certificate and key
[certs] Generating "apiserver-etcd-client" certificate and key
[certs] Generating "etcd/server" certificate and key
[certs] etcd/server serving cert is signed for DNS names [k8sclp02 localhost] and IPs [192.168.1.24 127.0.0.1 ::1]
[certs] Generating "apiserver-kubelet-client" certificate and key
[certs] Generating "apiserver" certificate and key
[certs] apiserver serving cert is signed for DNS names [k8sclp02 k8sclps1 kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local] and IPs [10.96.0.1 192.168.1.24]
[certs] Generating "front-proxy-client" certificate and key
[certs] Valid certificates and keys now exist in "/etc/kubernetes/pki"
[certs] Using the existing "sa" key
[kubeconfig] Generating kubeconfig files
[kubeconfig] Using kubeconfig folder "/etc/kubernetes"
[endpoint] WARNING: port specified in controlPlaneEndpoint overrides bindPort in the controlplane address
[kubeconfig] Writing "admin.conf" kubeconfig file
[endpoint] WARNING: port specified in controlPlaneEndpoint overrides bindPort in the controlplane address
[kubeconfig] Writing "controller-manager.conf" kubeconfig file
[endpoint] WARNING: port specified in controlPlaneEndpoint overrides bindPort in the controlplane address
[kubeconfig] Writing "scheduler.conf" kubeconfig file
[control-plane] Using manifest folder "/etc/kubernetes/manifests"
[control-plane] Creating static Pod manifest for "kube-apiserver"
[control-plane] Creating static Pod manifest for "kube-controller-manager"
[control-plane] Creating static Pod manifest for "kube-scheduler"
[check-etcd] Checking that the etcd cluster is healthy
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Starting the kubelet
[kubelet-start] Waiting for the kubelet to perform the TLS Bootstrap...
[etcd] Announced new etcd member joining to the existing etcd cluster
[etcd] Creating static Pod manifest for "etcd"
[etcd] Waiting for the new etcd member to join the cluster. This can take up to 40s
[upload-config] Storing the configuration used in ConfigMap "kubeadm-config" in the "kube-system" Namespace
[kubelet-check] Initial timeout of 40s passed.
[mark-control-plane] Marking the node k8sclp02 as control-plane by adding the label "node-role.kubernetes.io/master=''"
[mark-control-plane] Marking the node k8sclp02 as control-plane by adding the taints [node-role.kubernetes.io/master:NoSchedule]

This node has joined the cluster and a new control plane instance was created:

* Certificate signing request was sent to apiserver and approval was received.
* The Kubelet was informed of the new secure connection details.
* Control plane (master) label and taint were applied to the new node.
* The Kubernetes control plane instances scaled up.
* A new etcd member was added to the local/stacked etcd cluster.

To start administering your cluster from this node, you need to run the following as a regular user:

	mkdir -p $HOME/.kube
	sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
	sudo chown $(id -u):$(id -g) $HOME/.kube/config

Run 'kubectl get nodes' to see this node join the cluster.
```

Get your non-root user ready to operate `kubectl` commands:

```console
thecodewithin@k8sclp02:~$ mkdir -p $HOME/.kube
thecodewithin@k8sclp02:~$ sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
thecodewithin@k8sclp02:~$ sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

And finally create the manifest, so *kube-vip* will start up together with the cluster.

```console
thecodewithin@k8sclp02:~$ sudo docker run -it --rm plndr/kube-vip:0.2.0 sample manifest | sudo tee /etc/kubernetes/manifests/kube-vip.yaml
```

And then repeat for the third one.

Finally, install the CNI. The parameter `cluster-pool-ipv4-cidr` in the cilium config has to be equal to our `pod-network-cidr`.

```console
thecodewithin@k8sclp01:~$ curl https://raw.githubusercontent.com/cilium/cilium/v1.9/install/kubernetes/quick-install.yaml | sed -e 's/10.0.0.0\/8/10.100.0.0\/16/g' | kubectl apply -f -
```

### Add the nodes to the cluster

On each of them, execute the `kubeadm join <...>` command. Here's the example for the first node:

```console
thecodewithin@k8sclp04:~$ sudo kubeadm join k8sclps1:8443 --token rgh8a9.vh1mzx5l9m79c38a     --discovery-token-ca-cert-hash sha256:b78bbe13037b9bb03640051cdf1d5037566db5b31e6a5dd80c6ca5274ad72094
[preflight] Running pre-flight checks
	[WARNING IsDockerSystemdCheck]: detected "cgroupfs" as the Docker cgroup driver. The recommended driver is "systemd". Please follow the guide at https://kubernetes.io/docs/setup/cri/
	[WARNING SystemVerification]: missing optional cgroups: hugetlb
[preflight] Reading configuration from the cluster...
[preflight] FYI: You can look at this config file with 'kubectl -n kube-system get cm kubeadm-config -oyaml'
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Starting the kubelet
[kubelet-start] Waiting for the kubelet to perform the TLS Bootstrap...

This node has joined the cluster:
* Certificate signing request was sent to apiserver and a response was received.
* The Kubelet was informed of the new secure connection details.

Run 'kubectl get nodes' on the control-plane to see this node join the cluster.
```

Repeat for each of your other nodes.

When finished, check that all the nodes have been added to the cluster. Go back to one of the managers and list the cluster's nodes:

```console
thecodewithin@k8sclp01:~$ kubectl get nodes
NAME       STATUS   ROLES    AGE   VERSION
k8sclp01   Ready    master   9d    v1.19.3
k8sclp02   Ready    master   9d    v1.19.3
k8sclp03   Ready    master   9d    v1.19.3
k8sclp04   Ready    <none>   9d    v1.19.3
k8sclp05   Ready    <none>   9d    v1.19.3
k8sclp06   Ready    <none>   9d    v1.19.3
```

And check that all expected pods are up and running. You should see an output similar to this one:

```console
thecodewithin@k8sclp01:~$ kubectl get pods -o wide --all-namespaces
NAMESPACE     NAME                                                 READY   STATUS    RESTARTS   AGE     IP             NODE       NOMINATED NODE   READINESS GATES
kube-system   cilium-7v4hp                                         1/1     Running   7          25h     192.168.1.25   k8sclp05   <none>           <none>
kube-system   cilium-fzqpj                                         1/1     Running   6          25h     192.168.1.26   k8sclp06   <none>           <none>
kube-system   cilium-hm7b7                                         1/1     Running   0          28h     192.168.1.23   k8sclp03   <none>           <none>
kube-system   cilium-lzfhr                                         1/1     Running   0          28h     192.168.1.22   k8sclp02   <none>           <none>
kube-system   cilium-nm8k6                                         1/1     Running   7          25h     192.168.1.24   k8sclp04   <none>           <none>
kube-system   cilium-operator-5d8498fc44-2dt7k                     1/1     Running   2          26h     192.168.1.23   k8sclp03   <none>           <none>
kube-system   cilium-operator-5d8498fc44-k7cmt                     1/1     Running   8          28h     192.168.1.21   k8sclp01   <none>           <none>
kube-system   cilium-v6ndw                                         1/1     Running   0          28h     192.168.1.21   k8sclp01   <none>           <none>
kube-system   coredns-f9fd979d6-cw8rf                              1/1     Running   0          28h     10.100.0.141   k8sclp01   <none>           <none>
kube-system   coredns-f9fd979d6-kwvqf                              1/1     Running   0          28h     10.100.1.224   k8sclp02   <none>           <none>
kube-system   etcd-k8sclp01                                        1/1     Running   0          28h     192.168.1.21   k8sclp01   <none>           <none>
kube-system   etcd-k8sclp02                                        1/1     Running   0          28h     192.168.1.22   k8sclp02   <none>           <none>
kube-system   etcd-k8sclp03                                        1/1     Running   0          28h     192.168.1.23   k8sclp03   <none>           <none>
kube-system   kube-apiserver-k8sclp01                              1/1     Running   0          28h     192.168.1.21   k8sclp01   <none>           <none>
kube-system   kube-apiserver-k8sclp02                              1/1     Running   0          28h     192.168.1.22   k8sclp02   <none>           <none>
kube-system   kube-apiserver-k8sclp03                              1/1     Running   0          28h     192.168.1.23   k8sclp03   <none>           <none>
kube-system   kube-controller-manager-k8sclp01                     1/1     Running   1          28h     192.168.1.21   k8sclp01   <none>           <none>
kube-system   kube-controller-manager-k8sclp02                     1/1     Running   1          28h     192.168.1.22   k8sclp02   <none>           <none>
kube-system   kube-controller-manager-k8sclp03                     1/1     Running   1          28h     192.168.1.23   k8sclp03   <none>           <none>
kube-system   kube-proxy-6ngvl                                     1/1     Running   0          28h     192.168.1.22   k8sclp02   <none>           <none>
kube-system   kube-proxy-6ql9q                                     1/1     Running   1          25h     192.168.1.24   k8sclp04   <none>           <none>
kube-system   kube-proxy-d86qx                                     1/1     Running   0          28h     192.168.1.21   k8sclp01   <none>           <none>
kube-system   kube-proxy-ggbpf                                     1/1     Running   1          25h     192.168.1.25   k8sclp05   <none>           <none>
kube-system   kube-proxy-mqzlw                                     1/1     Running   0          28h     192.168.1.23   k8sclp03   <none>           <none>
kube-system   kube-proxy-vng2h                                     1/1     Running   1          25h     192.168.1.26   k8sclp06   <none>           <none>
kube-system   kube-scheduler-k8sclp01                              1/1     Running   1          28h     192.168.1.21   k8sclp01   <none>           <none>
kube-system   kube-scheduler-k8sclp02                              1/1     Running   0          28h     192.168.1.22   k8sclp02   <none>           <none>
kube-system   kube-scheduler-k8sclp03                              1/1     Running   0          28h     192.168.1.23   k8sclp03   <none>           <none>
kube-system   kube-vip-k8sclp01                                    1/1     Running   0          28h     192.168.1.21   k8sclp01   <none>           <none>
kube-system   kube-vip-k8sclp02                                    1/1     Running   0          28h     192.168.1.22   k8sclp02   <none>           <none>
kube-system   kube-vip-k8sclp03                                    1/1     Running   0          26h     192.168.1.23   k8sclp03   <none>           <none>
```

Done!

## Install Helm v3

Install Helm from packages following instructions here: https://helm.sh/docs/intro/install/#from-apt-debianubuntu

```console
thecodewithin@k8sclp01:~$ curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
thecodewithin@k8sclp01:~$ sudo apt-get install apt-transport-https --yes
thecodewithin@k8sclp01:~$ echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
thecodewithin@k8sclp01:~$ sudo apt-get update
thecodewithin@k8sclp01:~$ sudo apt-get install helm
```

Since we do not want to deploy all our services on the default namespace, let's create a few.

```console
thecodewithin@k8sclp01:~$ kubectl create ns networking
thecodewithin@k8sclp01:~$ kubectl create ns storage
```

## Install MetalLB

Install MetalLB using the Bitnami Helm repo. Download the repo and edit `values.yaml` to add the Layer 2 configuration

```console
thecodewithin@k8sclp01:~/charts$ helm repo add bitnami https://charts.bitnami.com/bitnami
thecodewithin@k8sclp01:~/charts$ helm fetch bitnami/metallb
```

Now unzip the file, `cd` into the `metallb` directory, and edit `values.yaml`. Go to the `configInline:` section and add your config, like so:

```yaml
configInline:
  # The address-pools section lists the IP addresses that MetalLB is
  # allowed to allocate, along with settings for how to advertise
  # those addresses over BGP once assigned. You can have as many
  # address pools as you want.
  address-pools:
  - # A name for the address pool. Services can request allocation
    # from a specific address pool using this name, by listing this
    # name under the 'metallb.universe.tf/address-pool' annotation.
    name: generic-cluster-pool
    # Protocol can be used to select how the announcement is done.
    # Supported values are bgp and layer2.
    protocol: layer2
    # A list of IP address ranges over which MetalLB has
    # authority. You can list multiple ranges in a single pool, they
    # will all share the same settings. Each range can be either a
    # CIDR prefix, or an explicit start-end range of IPs.
    addresses:
    - 192.168.1.30-192.168.1.39
```

Only one IP is needed for our purposes here, but I reserved a range of 10 IPs, from 192.168.1.30 to 192.168.1.39. Just because.

Now, install the chart:

```console
thecodewithin@k8sclp01:~/charts/metallb$ helm install metallb --namespace networking -f values.yaml .
```

Don't miss the dot at the end!

## Install nfs-client-provisioner

Install the nfs provisioner from superteleman's hem chart. Download it and edit `values.yaml`.

```console
thecodewithin@k8sclp01:~/charts$ helm repo add supertetelman https://supertetelman.github.io/charts/
thecodewithin@k8sclp01:~/charts$ helm fetch supertetelman/nfs-client-provisioner
```

Now unzip the file, `cd` into the directory and edit `values.yaml` to set up your nfs share. Configure the `nfs:` and `storageClass` parts:

```yaml
nfs:
  server: 192.168.1.xxx
  path: /data/virtuals/storage
  mountOptions:
    - nolock
    - soft
    - rw
    - intr

# For creating the StorageClass automatically:
storageClass:
  create: true

  # Set a provisioner name. If unset, a name will be generated.
  # provisionerName:

  # Set StorageClass as the default StorageClass
  # Ignored if storageClass.create is false
  defaultClass: false

  # Set a StorageClass name
  # Ignored if storageClass.create is false
  name: nfs-client

  # Allow volume to be expanded dynamically
  allowVolumeExpansion: true

  # Method used to reclaim an obsoleted volume
  #reclaimPolicy: Delete
  reclaimPolicy: Retain

  # When set to false your PVs will not be archived by the provisioner upon deletion of the PVC.
  archiveOnDelete: true

  # Set access mode - ReadWriteOnce, ReadOnlyMany or ReadWriteMany
  accessModes: ReadWriteOnce

```

Now, install the chart:

```console
thecodewithin@k8sclp01:~/charts/nfs-client-provisioner$ helm install nfs-client --namespace storage -f values.yaml .
```

## Install Traefik 2.3.3

Again, install from helm by fetching and editing. 

```console
thecodewithin@k8sclp01:~/charts$ helm repo add traefik https://helm.traefik.io/traefik
thecodewithin@k8sclp01:~/charts$ helm fetch traefik/traefik
```

Unzip the file, `cd` into the directory and edit `values.yaml`. In order for External-DNS to be able to see your Traefik, you need to enable `publishedService` under `providers`:

```yaml
providers:
  kubernetesCRD:
    enabled: true
    namespaces: []
      # - "default"
  kubernetesIngress:
    enabled: true
    namespaces: []
      # - "default"
    # IP used for Kubernetes Ingress endpoints
    publishedService:
      #enabled: false
      enabled: true
      # Published Kubernetes Service to copy status from. Format: namespace/servicename
      # By default this Traefik service
      # pathOverride: ""
```

Now define the ingressclass by supplying an additional argument:

```yaml
#additionalArguments: []
additionalArguments:
  - "--api.insecure=true"
  - "--api.dashboard=true"
  - "--providers.kubernetesingress.ingressclass=traefik-internal"
  - "--log.level=DEBUG"
```

To access the console, besides adding `--api.insecure=true` and `--api.dashboard=true` to your arguments, as seen above, toggle `expose` to `enable` for port 9000, under `ports: traefik`.

Next add the load balancer IP to the service's spec:

```yaml
service:
  enabled: true
  type: LoadBalancer
  # Additional annotations (e.g. for cloud provider specific config)
  annotations: {}
  # Additional service labels (e.g. for filtering Service by custom labels)
  labels: {}
  # Additional entries here will be added to the service spec. Cannot contains
  # type, selector or ports entries.
  #spec: {}
  spec:
    # externalTrafficPolicy: Cluster
    # loadBalancerIP: "1.2.3.4"
    loadBalancerIP: "192.168.1.30"
    # clusterIP: "2.3.4.5"
  loadBalancerSourceRanges: []
    # - 192.168.0.1/32
    # - 172.16.0.0/16
  externalIPs: []
    # - 1.2.3.4
```

And finally, enable persistence and configure `accessMode` and `storageClass`:

```yaml
persistence:
  #enabled: false
  enabled: true
#  existingClaim: ""
  #accessMode: ReadWriteOnce
  accessMode: ReadWriteMany
  size: 128Mi
  storageClass: "nfs-client"
  path: /data
  annotations: {}
  # subPath: "" # only mount a subpath of the Volume into the pod
```

Of course, check the rest of the file and adapt any parameters to your needs. When you are ready, install the chart:

```console
thecodewithin@k8sclp01:~/charts/traefik$ helm install traefik --namespace networking -f values.yaml .
```

You won't see the dashboard at this stage, yet. There are two of tings missing. The first one is an `ingress` for your traefik service. Here's my example:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: traefik
  annotations:
    kubernetes.io/ingress.class: traefik-internal
spec:
  rules:
  - host: traefik.mydomain.local
    http:
      paths:
      - pathType: Prefix
        path: /
        backend:
          service:
            name: traefik
            port:
              number: 9000
```

Activate it with 

```console
thecodewithin@k8sclp01:~/charts/traefik$ kubectl apply -f dashboard-traefik.yaml
```
or whatever name you gave it.

And the second missing thing is *External-DNS*, responsible for converting *traefik.mydomain.local* into an IP. Let's get to it.

## Install External-DNS

This is a bit more tricky. You need to have access to a DNS server of one of the types supported by External-DNS. Check the list, and instructions for each one, here: https://github.com/kubernetes-sigs/external-dns/tree/master/docs/tutorials

In this example, I configured a Bind server with external-dns provider [RFC2136](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/rfc2136.md)

Configuring Bind is beyond the scope of this document, but I'll provide my configuration as example. This is my `named.conf.options`, on `dnsbindserver`:

```
acl "trusted" {
        192.168.1.0/24;   
        192.168.3.0/24;   
        127.0.0.1;
};

options {
        directory "/var/cache/bind";

        recursion yes;                 # enables resursive queries
        allow-recursion { trusted; };  # allows recursive queries from "trusted" clients
        listen-on { <IP to my dnsbindserver>; };   # ns1 private IP address - listen on private network only
        allow-transfer { none; };      # disable zone transfers by default

        forwarders {
                <IP to my internet router acting as dns>;
         };

listen-on-v6 { none; };
};
```

I created a key with `tsig-keygen` and pasted the output into a file that I namded `externaldns-key`:

```console
root@dnsbindserver:/etc/bind:$ tsig-keygen -a hmac-sha256 externaldns-key
key "externaldns-key" {
	algorithm hmac-sha256;
	secret "someverylongsupersecretgibberishofasecurityK";
};
```

This is my `named.conf.local`:

```
//
// Do any local configuration here
//

// Consider adding the 1918 zones here, if they are not used in your
// organization
//include "/etc/bind/zones.rfc1918";
include "/etc/bind/externaldns-key";

zone "mydomain.local" {
        type master;
        file "/var/cache/bind/zones/db.mydomain";
        allow-transfer {
                key "externaldns-key";
        };
        update-policy {
                grant externaldns-key zonesub ANY;
        };
};

zone "168.192.in-addr.arpa" {
        type master;
        file "/var/cache/bind/zones/db.192.168";  # 192.168.0.0/16 subnet
        allow-transfer { <IP to my internet router acting as dns>; };  # ns2 private IP address - secondary 
};

```

And I created my zones files under `/var/cache/bind/` so that user `bind` can write to the files:

```console
root@dnsbindserver:/var/cache/bind$ ls -ltr
total 8
-rw-r--r-- 1 bind bind  221 Nov 27 14:31 managed-keys.bind
drwxr-xr-x 2 bind bind 4096 Dec  7 12:17 zones
root@dnsbindserver:/var/cache/bind$ ls -ltr zones/
total 20
-rw-r--r-- 1 bind bind 2528 Dec  7 07:40 db.192.168
-rw-r--r-- 1 bind bind  554 Dec  7 09:20 k8s.zone
-rw-r--r-- 1 bind bind 4576 Dec  7 12:05 db.mydomain.jnl
-rw-r--r-- 1 bind bind 3831 Dec  7 12:17 db.mydomain
```

Now, over to our cluster, install from helm by fetching and editing. 

```console
thecodewithin@k8sclp01:~/charts$ helm repo add bitnami https://charts.bitnami.com/bitnami
thecodewithin@k8sclp01:~/charts$ helm fetch bitnami/external-dns
```

Now unzip the file, `cd` into the directory and edit `values-production.yaml`. Change your provider to `rfc2136`:

```yaml
## DNS provider where the DNS records will be created. Available providers are:
## - alibabacloud, aws, azure, cloudflare, coredns, designate, digitalocoean, google, infoblox, rfc2136, transip
##
#provider: aws
provider: rfc2136
```

Scroll down until you get to the configuration for this provider, and configure its parameters:

```yaml
## RFC 2136 configuration to be set via arguments/env. variables
##
rfc2136:
  host: "<IP to my dnsbindserver>"
  port: 53
  zone: "mydomain.local"
  tsigSecret: "someverylongsupersecretgibberishofasecurityK"
  tsigSecretAlg: hmac-sha256
  tsigKeyname: externaldns-key
  tsigAxfr: true
  #tsigAxfr: false
  ## Possible units [ns, us, ms, s, m, h], see more https://golang.org/pkg/time/#ParseDuration
  minTTL: "0s"
```

Keep scrolling down, past the other providers' configurations, and activate `dryRun` for now:

```yaml
## When enabled, prints DNS record changes rather than actually performing them
##
#dryRun: false
dryRun: true
```

I added a `txtOwnerId`:

```yaml
## TXT Registry Identifier
##
txtOwnerId: "k8s"
```

To avoid some warnings when installing this helm, change the *rbac*'s version to `v1`:

```yaml
## RBAC parameteres (clusterRole and clusterRoleBinding)
## https://kubernetes.io/docs/reference/access-authn-authz/rbac/
##
rbac:
  create: true
  ## Deploys ClusterRole by Default
  clusterRole: true
  ## RBAC API version
  ##
  #apiVersion: v1beta1
  apiVersion: v1
  ## Podsecuritypolicy
  ##
  pspEnabled: false
```

Whith this we should be ready to go. Install this helm in `dryRun` mode:

```console
thecodewithin@k8sclp01:~/charts/external-dns$ helm -n networking install external-dns -f values-production.yaml .
```

If everything goes well, delete the chart with 

```console
thecodewithin@k8sclp01:~/charts/external-dns$ helm -n networking delete external-dns
```

deactivate `dryRun` by editing `values-production.yaml`, and install again, for real.

You should now see an entry like this in your `/var/cache/bind/zones/db.mydomain`, over at your dns server:

```
traefik			A	192.168.1.31
			TXT	"heritage=external-dns,external-dns/owner=k8s,external-dns/resource=service/networking/traefik"
```

And the *traefik* dashboard should be accessible at http://traefik.mydomain.local.

## Cheese!

To top it all, let's sprinkle some cheese all over it!

Let's deploy some pods, services and an ingress so the platform can be tested.

To deploy the pods, copy this yaml code into `cheese-deployments.yaml`.

```yaml
---
kind: Deployment
apiVersion: apps/v1
metadata:
  name: stilton
  labels:
    app: cheese
    cheese: stilton
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cheese
      task: stilton
  template:
    metadata:
      labels:
        app: cheese
        task: stilton
        version: v0.0.1
    spec:
      containers:
      - name: cheese
        image: errm/cheese:stilton
        ports:
        - containerPort: 80
---
kind: Deployment
apiVersion: apps/v1
metadata:
  name: cheddar
  labels:
    app: cheese
    cheese: cheddar
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cheese
      task: cheddar
  template:
    metadata:
      labels:
        app: cheese
        task: cheddar
        version: v0.0.1
    spec:
      containers:
      - name: cheese
        image: errm/cheese:cheddar
        ports:
        - containerPort: 80
---
kind: Deployment
apiVersion: apps/v1
metadata:
  name: wensleydale
  labels:
    app: cheese
    cheese: wensleydale
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cheese
      task: wensleydale
  template:
    metadata:
      labels:
        app: cheese
        task: wensleydale
        version: v0.0.1
    spec:
      containers:
      - name: cheese
        image: errm/cheese:wensleydale
        ports:
        - containerPort: 80
```
Apply the deployment:

```console
thecodewithin@k8sclp01:~/cheese$ kubectl apply -f cheese-deployments.yaml
```

The services are defined in `cheese-services.yaml`

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: stilton
spec:
  ports:
  - name: http
    targetPort: 80
    port: 80
  selector:
    app: cheese
    task: stilton
---
apiVersion: v1
kind: Service
metadata:
  name: cheddar
spec:
  ports:
  - name: http
    targetPort: 80
    port: 80
  selector:
    app: cheese
    task: cheddar
---
apiVersion: v1
kind: Service
metadata:
  name: wensleydale
  annotations:
    traefik.backend.circuitbreaker: "NetworkErrorRatio() > 0.5"
spec:
  ports:
  - name: http
    targetPort: 80
    port: 80
  selector:
    app: cheese
    task: wensleydale
```
Ready to apply them:

```console
thecodewithin@k8sclp01:~/cheese$ kubectl apply -f cheese-services.yaml
```

And finally the ingress. `cheese-ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: cheese
  annotations:
    kubernetes.io/ingress.class: traefik-internal
spec:
  rules:
  - host: stilton.mydomain.local
    http:
      paths:
      - pathType: Prefix
        path: /
        backend:
          service:
            name: stilton
            port: 
              number: 80
  - host: cheddar.mydomain.local
    http:
      paths:
      - pathType: Prefix
        path: /
        backend:
          service:
            name: cheddar
            port: 
              number: 80
  - host: wensleydale.mydomain.local
    http:
      paths:
      - pathType: Prefix
        path: /
        backend:
          service:
            name: wensleydale
            port: 
              number: 80
```
Apply.

```console
thecodewithin@k8sclp01:~/cheese$ kubectl apply -f cheese-ingress.yaml
```

Now you should be able to access any of the three cheeses from a browser in any computer on your 192.168.1.0/24 network by pointing it to http:/stilton.mydomain.local, http:/cheddar.mydomain.local or http:/wensleydale.mydomain.local. Check your `/var/cache/bind/zones/db.mydomain` over at your dns server for new entries as well.

## Congratulations!

You have deployed a multi-master, multi-node Kubernetes cluster with `kubeadm`, using ***kube-vip*** for the control panel's VIP, ***Cilium*** as CNI, ***MetalLB*** as load balancer, ***Traefik*** as ingress controller and ***External-DNS*** to synchronize your exposed services with your DNS, and have tested the platform by deploying some cheesy services and accessing them by name from your network outside the cluster.

The platform is now ready for some real work.
