# Kubernetes-master-worker-setup-using-kubeadm
complete master-worker set using kubeadm using script file 
Step 0: Prerequisites
OS: Ubuntu 22.04 on all nodes
Users: Root access (or sudo)
Network: All nodes can reach each other via private IP
Hardware:
**Master: 2 CPUs, 2GB RAM minimum
Worker: 1 CPU, 2GB RAM minimum
Worker: 1 CPU, 2GB RAM minimum**

Disable swap on all nodes (your script already does this)
Open necessary ports (optional if using ufw):
Master node: 6443 (API server), 2379-2380 (etcd), 10250 (kubelet), 10251 (scheduler), 10252 (controller manager), 30000-32767 (NodePort services)
Workers: 10250 (kubelet), 30000-32767 (NodePort)

**Step 1: Run your script on the master node**
        1.1 Make the script executable:
          **chmod +x k8s-cluster-setup.sh**
        1.2 Run the script with the master IP
          **sudo ./k8s-cluster-setup.sh --master <MASTER_PRIVATE_IP>**

  The script will:
  Install containerd
  Install kubeadm, kubelet, kubectl
  Disable swap
  Load kernel modules
  Initialize master node
  Apply Calico CNI
  Print the kubeadm join ... command

**Step 2: Prepare worker nodes**
Copy the k8s-cluster-setup.sh script to each worker nodes both workernode-1 and workernode-2.
Run the script with the join command from master:

**Run the below command in Workernode-1**
sudo ./k8s-cluster-setup.sh --worker "kubeadm join <MASTER_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>"

example:
**cd /home/ubuntu
chmod +x k8s-cluster-setup.sh**
**sudo ./k8s-cluster-setup.sh --worker "kubeadm join 172.31.38.6:6443 --token 4egq92.mkxl57dxzpgv02xs --discovery-token-ca-cert-hash sha256:ace74c46cfea3df7be4d8e6312d1eb4b3bb21656cbec0df1fc5abbeb615d1895"**

**Run the below command in Workernode-2**

**cd /home/ubuntu
chmod +x k8s-cluster-setup.sh
sudo ./k8s-cluster-setup.sh --worker "kubeadm join 172.31.38.6:6443 --token 4egq92.mkxl57dxzpgv02xs --discovery-token-ca-cert-hash sha256:ace74c46cfea3df7be4d8e6312d1eb4b3bb21656cbec0df1fc5abbeb615d1895"**

The script will:
Install containerd, kubeadm, kubelet
Disable swap
Join the node to the cluster

**Step 3: Verify cluster status**
On the master node:
Check node status:
**kubectl get nodes**

**You should secc the output**
| NAME    | STATUS | ROLES  | AGE | VERSION |
| ------- | ------ | ------ | --- | ------- |
| master  | Ready  | master | 5m  | v1.30   |
| worker1 | Ready  | <none> | 2m  | v1.30   |
| worker2 | Ready  | <none> | 1m  | v1.30   |

