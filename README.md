# k8s_multi-manager

*Deploying a multi-manager Kubernetes cluster, step by step.*

***

In this example we are going to deploy a 6 node Kubernetes cluster, 3 managers and 3 nodes, following the official documentation from https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/

My setup:
 - **6 VMs** on a Proxmox:
   - Debian 10
   - 8GB of RAM 
   - without swap space
   - 2 CPUs
 - **container runtime**: Docker
 - **software load balancing**: kube-vip
 - **cluster approach**: stacked control plane nodes

The hosts:

| Role | IP | Hostname |
|:----|:----|:----|
|Manager | 192.168.1.23 | k8sclp01 |
|Manager | 192.168.1.24 | k8sclp02 |
|Manager | 192.168.1.25 | k8sclp03 |
|Node | 192.168.1.26 | k8sclp04 |
|Node | 192.168.1.27 | k8sclp05 |
|Node | 192.168.1.28 | k8sclp06 |
|VIP | 192.168.1.130 | k8sclps1 |

## TL;DR;

 1. As root (not with sudo, mind you) run `run-prereq.sh` on all your cluster hosts, managers and nodes alike
 1. Reserve an IP in your network for your control plane's VIP
 1. Add your non-root user to the `docker` group and switch to your non-root user
    `usermod -G docker <your-non-root-user>`
 1. Create a `/etc/kube-vip/config.yaml` file for the "Kube-VIP" on each manager (see below)
 1. Run `run-1stmngr.sh` on the first manager
 1. One by one, join the other managers
 1. One by one, join the nodes

## Step by step process

### Before you start

When creating a multi-master Kubernetes cluster, a load balancer for the kube-apiserver is needed, so reserve an IP in your network with a corresponding FQDN. In this example I'll use 192.168.1.130, paired with k8sclps1.example.com.

You should also add your non-root user to the `docker` group. You can have `run-prereq.sh` do it for you by uncommenting that line on the script and substituting your user name in it.

### On all hosts

If you are on bare metal, have all your Kubernetes hosts ready and copy and run `run-prereq.sh` on each and all of them, managers and nodes alike.

If you are on a VM environment, have just one VM ready, copy and run `run-prereq.sh` on it and turn the VM into a template. Now you can create all your Kubernetes hosts from this template.

Either way, I recommend you take a look at the code to see what it's doing. It's pretty straightforward and has links to the documentation.

### On the first manager

Create a configuraton file for the kube-apiserver load balancer. Check the docs here: https://kube-vip.io/control-plane/ and here: https://github.com/kubernetes/kubeadm/blob/master/docs/ha-considerations.md#kube-vip To do so, create the directory where the config is expected

```
thecodewithin@k8sclp01:~$ sudo mkdir /etc/kube-vip
```
Then create a file named `config.yaml` whith the following contents:

```
thecodewithin@k8sclp01:~$ sudo vi /etc/kube-vip/config.yaml 
localPeer:
  id: k8sclp01
  address: 192.168.1.23
  port: 10000
remotePeers:
- id: k8sclp02
  address: 192.168.1.24
  port: 10000
- id: k8sclp03
  address: 192.168.1.25
  port: 10000
#- id: ${PEER1_ID}
#  address: ${PEER1_IPADDR}
#  port: 10000
# [...]
vip: 192.168.1.130
gratuitousARP: true
singleNode: false
startAsLeader: true
interface: ens18
loadBalancers:
- name: Kubernetes Control Plane
  type: tcp
  port: 8443
  bindToVip: true
  backends:
  - port: 6444
    address: 192.168.1.23
  - port: 6444
    address: 192.168.1.24
  - port: 6444
    address: 192.168.1.25
```

Clone this repository to your first manager. Run `run-1stmngr.sh`. Again, take a look at the code. 

This script will 
 - create a manifest for the kube-vip, the software load balancing I choose for the kube-apiserver, using the config you just created, so it will start up together with the cluster 
 - it will then initiate the cluster on your first node
 - and prepare your non-root user to interact with the kubernetes API through `kubectl` commands
 - finally, it will install a Container Network Interface (CNI) on your cluster.

#### Initiating the cluster

When the cluster is initiated with `kubeadm init <...>` the output will contain the necessary commands to join the other managers, as well as the nodes. It will look something like this:

```
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

Give the newly started cluster a few moments and then check wether all the pods are running. Run this command as a regular user:

```
thecodewithin@k8sclp01:~$ kubectl get pods --all-namespaces
```
You should see an output similar to this:

```
NAMESPACE     NAME                                     READY   STATUS    RESTARTS   AGE
kube-system   calico-kube-controllers-7d569d95-9twlt   1/1     Running   0          52s
kube-system   calico-node-ct6zs                        1/1     Running   0          53s
kube-system   coredns-f9fd979d6-hnt2d                  1/1     Running   0          2m49s
kube-system   coredns-f9fd979d6-tvws7                  1/1     Running   0          2m49s
kube-system   etcd-k8sclp01                           1/1     Running   0          2m57s
kube-system   kube-apiserver-k8sclp01                 1/1     Running   0          2m58s
kube-system   kube-controller-manager-k8sclp01        1/1     Running   0          2m58s
kube-system   kube-proxy-f5h8k                         1/1     Running   0          2m49s
kube-system   kube-scheduler-k8sclp01                 1/1     Running   0          2m58s
kube-system   kube-vip-k8sclp01                       1/1     Running   0          2m57s
```
### Add the other managers to the control plane

Now, on each of the remaining managers, create the kube-apiserver load balancer's configuration file. Be careful to change the `localPeer` configuration and to set `startAsLeader` to `false` for each of them.

Then create the manifests. See my examples below.

This is for the second manager:

```
thecodewithin@k8sclp02:~$ sudo mkdir /etc/kube-vip

thecodewithin@k8sclp02:~$ sudo vi /etc/kube-vip/config.yaml 
localPeer:
  id: k8sclp02
  address: 192.168.1.24
  port: 10000
remotePeers:
- id: k8sclp01
  address: 192.168.1.23
  port: 10000
- id: k8sclp03
  address: 192.168.1.25
  port: 10000
#- id: ${PEER1_ID}
#  address: ${PEER1_IPADDR}
#  port: 10000
# [...]
vip: 192.168.1.130
gratuitousARP: true
singleNode: false
startAsLeader: false
interface: ens18
loadBalancers:
- name: Kubernetes Control Plane
  type: tcp
  port: 8443
  bindToVip: true
  backends:
  - port: 6444
    address: 192.168.1.23
  - port: 6444
    address: 192.168.1.24
  - port: 6444
    address: 192.168.1.25
```

```
thecodewithin@k8sclp02:~$ docker run -it --rm plndr/kube-vip:0.1.1 /kube-vip sample manifest     | sed "s|plndr/kube-vip:'|plndr/kube-vip:0.1.1'|"     | sudo tee /etc/kubernetes/manifests/kube-vip.yaml
```
And for the third one:

```
thecodewithin@k8sclp03:~$ sudo mkdir /etc/kube-vip

thecodewithin@k8sclp03:~$ sudo vi /etc/kube-vip/config.yaml
localPeer:
  id: k8sclp03
  address: 192.168.1.25
  port: 10000
remotePeers:
- id: k8sclp01
  address: 192.168.1.23
  port: 10000
- id: k8sclp02
  address: 192.168.1.24
  port: 10000
#- id: ${PEER1_ID}
#  address: ${PEER1_IPADDR}
#  port: 10000
# [...]
vip: 192.168.1.130
gratuitousARP: true
singleNode: false
startAsLeader: false
interface: ens18
loadBalancers:
- name: Kubernetes Control Plane
  type: tcp
  port: 8443
  bindToVip: true
  backends:
  - port: 6444
    address: 192.168.1.23
  - port: 6444
    address: 192.168.1.24
  - port: 6444
    address: 192.168.1.25
```

```
thecodewithin@k8sclp03:~$ docker run -it --rm plndr/kube-vip:0.1.1 /kube-vip sample manifest     | sed "s|plndr/kube-vip:'|plndr/kube-vip:0.1.1'|"     | sudo tee /etc/kubernetes/manifests/kube-vip.yaml
```
Now we can join the managers to the cluster.

First on the second manager:

```
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

```
thecodewithin@k8sclp02:~$ mkdir -p $HOME/.kube
thecodewithin@k8sclp02:~$ sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
thecodewithin@k8sclp02:~$ sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

And then the same for the third one.

### Add the nodes to the cluster

On each of them, execute the `kubeadm join <...>` command:

Here's the example for the first node:

```
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

When finished, check that the nodes are added to the cluster. Go back to one of the managers and list the cluster's nodes:

```
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

```
thecodewithin@k8sclp01:~$ kubectl get pods -o wide --all-namespaces
NAMESPACE     NAME                                     READY   STATUS    RESTARTS   AGE     IP               NODE        NOMINATED NODE   READINESS GATES
kube-system   calico-kube-controllers-7d569d95-kcjql   1/1     Running   2          9d    10.100.116.1     k8sasp05   <none>           <none>
kube-system   calico-node-2959d                        1/1     Running   0          9d    192.168.1.24     k8sasp02   <none>           <none>
kube-system   calico-node-57wl4                        1/1     Running   0          9d    192.168.1.26     k8sasp04   <none>           <none>
kube-system   calico-node-6vwg2                        1/1     Running   1          9d    192.168.1.27     k8sasp05   <none>           <none>
kube-system   calico-node-jnqfl                        1/1     Running   1          9d    192.168.1.23     k8sasp01   <none>           <none>
kube-system   calico-node-nbqh2                        1/1     Running   0          9d    192.168.1.28     k8sasp06   <none>           <none>
kube-system   calico-node-vnczh                        1/1     Running   1          9d    192.168.1.25     k8sasp03   <none>           <none>
kube-system   coredns-f9fd979d6-6v9f5                  1/1     Running   0          9d    10.100.92.129    k8sasp04   <none>           <none>
kube-system   coredns-f9fd979d6-pcbd5                  1/1     Running   1          9d    10.100.100.196   k8sasp01   <none>           <none>
kube-system   etcd-k8sasp01                            1/1     Running   4          9d    192.168.1.23     k8sasp01   <none>           <none>
kube-system   etcd-k8sasp02                            1/1     Running   1          9d    192.168.1.24     k8sasp02   <none>           <none>
kube-system   etcd-k8sasp03                            1/1     Running   0          9d    192.168.1.25     k8sasp03   <none>           <none>
kube-system   kube-apiserver-k8sasp01                  1/1     Running   4          9d    192.168.1.23     k8sasp01   <none>           <none>
kube-system   kube-apiserver-k8sasp02                  1/1     Running   0          9d    192.168.1.24     k8sasp02   <none>           <none>
kube-system   kube-apiserver-k8sasp03                  1/1     Running   2          9d    192.168.1.25     k8sasp03   <none>           <none>
kube-system   kube-controller-manager-k8sasp01         1/1     Running   5          9d    192.168.1.23     k8sasp01   <none>           <none>
kube-system   kube-controller-manager-k8sasp02         1/1     Running   3          9d    192.168.1.24     k8sasp02   <none>           <none>
kube-system   kube-controller-manager-k8sasp03         1/1     Running   3          9d    192.168.1.25     k8sasp03   <none>           <none>
kube-system   kube-proxy-2f7tb                         1/1     Running   0          9d    192.168.1.27     k8sasp05   <none>           <none>
kube-system   kube-proxy-7rt2t                         1/1     Running   0          9d    192.168.1.28     k8sasp06   <none>           <none>
kube-system   kube-proxy-969dg                         1/1     Running   0          9d    192.168.1.26     k8sasp04   <none>           <none>
kube-system   kube-proxy-g6ggg                         1/1     Running   0          9d    192.168.1.24     k8sasp02   <none>           <none>
kube-system   kube-proxy-jlw5s                         1/1     Running   0          9d    192.168.1.25     k8sasp03   <none>           <none>
kube-system   kube-proxy-r5575                         1/1     Running   1          9d    192.168.1.23     k8sasp01   <none>           <none>
kube-system   kube-scheduler-k8sasp01                  1/1     Running   3          9d    192.168.1.23     k8sasp01   <none>           <none>
kube-system   kube-scheduler-k8sasp02                  1/1     Running   4          9d    192.168.1.24     k8sasp02   <none>           <none>
kube-system   kube-scheduler-k8sasp03                  1/1     Running   3          9d    192.168.1.25     k8sasp03   <none>           <none>
kube-system   kube-vip-k8sasp01                        1/1     Running   1          9d    192.168.1.23     k8sasp01   <none>           <none>
kube-system   kube-vip-k8sasp02                        1/1     Running   0          9d    192.168.1.24     k8sasp02   <none>           <none>
kube-system   kube-vip-k8sasp03                        1/1     Running   0          9d    192.168.1.25     k8sasp03   <none>           <none>
```

Done!

