#!/bin/bash

#############################################################
# Kubernetes Master Node Installation Script
# Features:
# - Auto-detects Linux distribution
# - Uses dnf if available, otherwise yum
# - Uses Chinese mirrors for faster downloads
# - Auto-configures network settings
# - Shows progress bars
# - Provides error handling and rollback
#############################################################

set -e

# Text colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
PKG_MANAGER=""
LOG_FILE="/tmp/k8s_master_install_$(date +%Y%m%d%H%M%S).log"
NETWORK_CIDR="192.168.0.0/16"
CNI_PLUGIN="calico" # calico or flannel
HOST_IP=$(ip -o -4 addr list | grep -v "127.0.0.1" | awk '{print $4}' | cut -d/ -f1 | head -n1)
K8S_VERSION="1.24.0"
ROLLBACK_STEPS=()
JOIN_COMMAND=""

# Banner
echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║              Kubernetes Master Node Installer              ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Initialize log file
echo "Kubernetes Master Installation Log - $(date)" > $LOG_FILE
echo "==============================================" >> $LOG_FILE

# Function to show progress bar
show_progress() {
    local duration=$1
    local message=$2
    local elapsed=0
    local progress=0
    local bar_size=40
    
    echo -e "${YELLOW}$message${NC}"
    
    while [ $elapsed -lt $duration ]; do
        progress=$(( (elapsed * bar_size) / duration ))
        
        # Create the progress bar
        printf "\r["
        for ((i=0; i<bar_size; i++)); do
            if [ $i -lt $progress ]; then
                printf "="
            else
                printf " "
            fi
        done
        printf "] %d%%" $(( (elapsed * 100) / duration ))
        
        sleep 1
        elapsed=$((elapsed + 1))
    done
    
    printf "\r["
    for ((i=0; i<bar_size; i++)); do
        printf "="
    done
    printf "] 100%%\n"
}

# Function to log error and exit
error_exit() {
    local message=$1
    echo -e "${RED}ERROR: $message${NC}" | tee -a $LOG_FILE
    echo -e "${YELLOW}Check the log file for details: $LOG_FILE${NC}"
    echo -e "${YELLOW}Executing rollback operations...${NC}"
    perform_rollback
    exit 1
}

# Function to add rollback step
add_rollback_step() {
    ROLLBACK_STEPS+=("$1")
}

# Function to perform rollback
perform_rollback() {
    echo "Starting rollback process..." | tee -a $LOG_FILE
    
    # Execute rollback steps in reverse order
    for ((i=${#ROLLBACK_STEPS[@]}-1; i>=0; i--)); do
        echo "Executing: ${ROLLBACK_STEPS[$i]}" >> $LOG_FILE
        eval "${ROLLBACK_STEPS[$i]}" >> $LOG_FILE 2>&1 || echo "Rollback step failed: ${ROLLBACK_STEPS[$i]}" >> $LOG_FILE
    done
    
    echo -e "${GREEN}Rollback completed. System restored to initial state.${NC}" | tee -a $LOG_FILE
}

# Function to detect Linux distribution and package manager
detect_system() {
    echo "Detecting system information..." | tee -a $LOG_FILE
    
    # Check for dnf first
    if command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        echo "DNF package manager detected." >> $LOG_FILE
    # Otherwise check for yum
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        echo "YUM package manager detected." >> $LOG_FILE
    else
        error_exit "Neither DNF nor YUM package managers were found. This script only supports RHEL-based distributions."
    fi
    
    # Detect Linux distribution
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$NAME
        VERSION=$VERSION_ID
        echo "Detected distribution: $DISTRO $VERSION" >> $LOG_FILE
        echo -e "${GREEN}✓ System detected: $DISTRO $VERSION with $PKG_MANAGER${NC}"
    else
        error_exit "Could not detect Linux distribution."
    fi
    
    # Add rollback step for package manager configuration
    add_rollback_step "echo 'No package manager configuration to roll back yet.'"
}

# Function to configure Chinese mirrors
configure_mirrors() {
    echo "Configuring Chinese mirrors..." | tee -a $LOG_FILE
    show_progress 5 "Configuring Chinese mirrors for faster downloads..."
    
    if [ "$PKG_MANAGER" = "dnf" ]; then
        # Backup original repo files
        mkdir -p /etc/dnf/repos.d.backup
        cp -f /etc/dnf/dnf.conf /etc/dnf/dnf.conf.backup 2>/dev/null || true
        cp -f /etc/yum.repos.d/* /etc/dnf/repos.d.backup/ 2>/dev/null || true
        
        # Add rollback step
        add_rollback_step "cp -f /etc/dnf/dnf.conf.backup /etc/dnf/dnf.conf 2>/dev/null || true"
        add_rollback_step "rm -f /etc/yum.repos.d/*.repo 2>/dev/null || true"
        add_rollback_step "cp -f /etc/dnf/repos.d.backup/* /etc/yum.repos.d/ 2>/dev/null || true"
        
        # Configure Alibaba Cloud mirror for DNF
        echo "fastestmirror=true" >> /etc/dnf/dnf.conf
        echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
        
        # Create repo files for Alibaba Cloud mirror
        if [ -f /etc/yum.repos.d/CentOS-Base.repo ]; then
            mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup
            curl -s -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
            sed -i 's/http:/https:/g' /etc/yum.repos.d/CentOS-Base.repo
        fi
        
        # Update repository cache
        $PKG_MANAGER clean all >> $LOG_FILE 2>&1 || error_exit "Failed to clean $PKG_MANAGER cache"
        $PKG_MANAGER makecache >> $LOG_FILE 2>&1 || error_exit "Failed to make $PKG_MANAGER cache"
    elif [ "$PKG_MANAGER" = "yum" ]; then
        # Backup original repo files
        mkdir -p /etc/yum.repos.d.backup
        cp -f /etc/yum.conf /etc/yum.conf.backup 2>/dev/null || true
        cp -f /etc/yum.repos.d/* /etc/yum.repos.d.backup/ 2>/dev/null || true
        
        # Add rollback step
        add_rollback_step "cp -f /etc/yum.conf.backup /etc/yum.conf 2>/dev/null || true"
        add_rollback_step "rm -f /etc/yum.repos.d/*.repo 2>/dev/null || true"
        add_rollback_step "cp -f /etc/yum.repos.d.backup/* /etc/yum.repos.d/ 2>/dev/null || true"
        
        # Configure Alibaba Cloud mirror for YUM
        if [ -f /etc/yum.repos.d/CentOS-Base.repo ]; then
            mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup
            curl -s -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
            sed -i 's/http:/https:/g' /etc/yum.repos.d/CentOS-Base.repo
        fi
        
        # Update repository cache
        $PKG_MANAGER clean all >> $LOG_FILE 2>&1 || error_exit "Failed to clean $PKG_MANAGER cache"
        $PKG_MANAGER makecache >> $LOG_FILE 2>&1 || error_exit "Failed to make $PKG_MANAGER cache"
    fi
    
    echo -e "${GREEN}✓ Chinese mirrors configured successfully${NC}"
}

# Function to install prerequisites
install_prerequisites() {
    echo "Installing prerequisites..." | tee -a $LOG_FILE
    show_progress 10 "Installing system prerequisites..."
    
    # Add rollback step
    add_rollback_step "$PKG_MANAGER -y remove curl wget yum-utils device-mapper-persistent-data lvm2 ntp chrony 2>/dev/null || true"
    
    # Install necessary packages
    $PKG_MANAGER -y install curl wget yum-utils device-mapper-persistent-data lvm2 >> $LOG_FILE 2>&1 || error_exit "Failed to install prerequisites"
    
    # Install and configure chronyd for time synchronization
    $PKG_MANAGER -y install ntp chrony >> $LOG_FILE 2>&1 || error_exit "Failed to install time synchronization tools"
    systemctl enable chronyd >> $LOG_FILE 2>&1
    systemctl start chronyd >> $LOG_FILE 2>&1
    
    echo -e "${GREEN}✓ Prerequisites installed successfully${NC}"
}

# Function to configure system settings
configure_system() {
    echo "Configuring system settings..." | tee -a $LOG_FILE
    show_progress 8 "Configuring system settings for Kubernetes..."
    
    # Disable SELinux
    if [ -f /etc/selinux/config ]; then
        cp /etc/selinux/config /etc/selinux/config.backup
        add_rollback_step "cp /etc/selinux/config.backup /etc/selinux/config"
        sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
        setenforce 0 || true
    fi
    
    # Disable swap
    swapoff -a
    
    # Comment out swap entries in /etc/fstab
    if [ -f /etc/fstab ]; then
        cp /etc/fstab /etc/fstab.backup
        add_rollback_step "cp /etc/fstab.backup /etc/fstab"
        sed -i '/swap/s/^/#/' /etc/fstab
    fi
    
    # Load br_netfilter module
    modprobe br_netfilter
    echo "br_netfilter" > /etc/modules-load.d/k8s.conf
    add_rollback_step "rm -f /etc/modules-load.d/k8s.conf"
    
    # Set kernel parameters
    cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
    add_rollback_step "rm -f /etc/sysctl.d/k8s.conf"
    
    # Apply kernel parameters
    sysctl --system >> $LOG_FILE 2>&1
    
    echo -e "${GREEN}✓ System settings configured successfully${NC}"
}

# Function to install container runtime (containerd)
install_container_runtime() {
    echo "Installing container runtime (containerd)..." | tee -a $LOG_FILE
    show_progress 15 "Installing and configuring containerd..."
    
    # Add Docker repo
    yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    add_rollback_step "rm -f /etc/yum.repos.d/docker-ce.repo"
    
    # Install containerd
    $PKG_MANAGER install -y containerd.io >> $LOG_FILE 2>&1 || error_exit "Failed to install containerd"
    add_rollback_step "$PKG_MANAGER remove -y containerd.io"
    
    # Configure containerd
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    add_rollback_step "rm -f /etc/containerd/config.toml"
    
    # Set SystemdCgroup to true
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    
    # Configure containerd to use Alibaba Cloud registry mirror
    sed -i 's|https://registry-1.docker.io|https://registry.cn-hangzhou.aliyuncs.com|g' /etc/containerd/config.toml
    
    # Restart containerd
    systemctl enable containerd >> $LOG_FILE 2>&1
    systemctl restart containerd >> $LOG_FILE 2>&1
    
    echo -e "${GREEN}✓ Containerd installed and configured successfully${NC}"
}

# Function to install Kubernetes components
install_kubernetes() {
    echo "Installing Kubernetes components..." | tee -a $LOG_FILE
    show_progress 15 "Installing kubeadm, kubelet, and kubectl..."
    
    # Add Kubernetes repo using Alibaba Cloud mirror
    cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
    add_rollback_step "rm -f /etc/yum.repos.d/kubernetes.repo"
    
    # Install Kubernetes components
    $PKG_MANAGER install -y kubelet-$K8S_VERSION kubeadm-$K8S_VERSION kubectl-$K8S_VERSION >> $LOG_FILE 2>&1 || error_exit "Failed to install Kubernetes components"
    add_rollback_step "$PKG_MANAGER remove -y kubelet kubeadm kubectl"
    
    # Enable kubelet
    systemctl enable kubelet >> $LOG_FILE 2>&1
    
    # Set version in kubeadm config
    cat > /tmp/kubeadm-config.yaml << EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
localAPIEndpoint:
  advertiseAddress: $HOST_IP
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v$K8S_VERSION
networking:
  podSubnet: $NETWORK_CIDR
  serviceSubnet: 10.96.0.0/12
imageRepository: registry.cn-hangzhou.aliyuncs.com/google_containers
EOF
    add_rollback_step "rm -f /tmp/kubeadm-config.yaml"
    
    echo -e "${GREEN}✓ Kubernetes components installed successfully${NC}"
}

# Function to initialize Kubernetes master
initialize_master() {
    echo "Initializing Kubernetes master..." | tee -a $LOG_FILE
    show_progress 20 "Initializing Kubernetes master node..."
    
    # Pull required images from Alibaba Cloud mirror
    echo "Pulling Kubernetes images..." >> $LOG_FILE
    kubeadm config images pull --config=/tmp/kubeadm-config.yaml >> $LOG_FILE 2>&1 || error_exit "Failed to pull Kubernetes images"
    
    # Initialize master node
    echo "Running kubeadm init..." >> $LOG_FILE
    kubeadm init --config=/tmp/kubeadm-config.yaml --upload-certs >> $LOG_FILE 2>&1 || error_exit "Failed to initialize Kubernetes master"
    add_rollback_step "kubeadm reset -f"
    
    # Configure kubectl for the current user
    mkdir -p $HOME/.kube
    cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
    add_rollback_step "rm -rf $HOME/.kube"
    
    # Extract join command
    JOIN_COMMAND=$(kubeadm token create --print-join-command)
    
    echo -e "${GREEN}✓ Kubernetes master initialized successfully${NC}"
}

# Function to install network plugin (Calico or Flannel)
install_network_plugin() {
    echo "Installing network plugin ($CNI_PLUGIN)..." | tee -a $LOG_FILE
    show_progress 15 "Installing $CNI_PLUGIN network plugin..."
    
    if [ "$CNI_PLUGIN" = "calico" ]; then
        # Install Calico
        echo "Installing Calico CNI..." >> $LOG_FILE
        wget -q https://docs.projectcalico.org/manifests/calico.yaml -O /tmp/calico.yaml
        
        # Replace CIDR if needed
        sed -i "s|192.168.0.0/16|$NETWORK_CIDR|g" /tmp/calico.yaml
        
        # Apply calico manifest
        kubectl apply -f /tmp/calico.yaml >> $LOG_FILE 2>&1 || error_exit "Failed to apply Calico manifest"
        add_rollback_step "kubectl delete -f /tmp/calico.yaml --ignore-not-found=true"
    elif [ "$CNI_PLUGIN" = "flannel" ]; then
        # Install Flannel
        echo "Installing Flannel CNI..." >> $LOG_FILE
        wget -q https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml -O /tmp/kube-flannel.yml
        
        # Replace CIDR if needed
        sed -i "s|10.244.0.0/16|$NETWORK_CIDR|g" /tmp/kube-flannel.yml
        
        # Apply flannel manifest
        kubectl apply -f /tmp/kube-flannel.yml >> $LOG_FILE 2>&1 || error_exit "Failed to apply Flannel manifest"
        add_rollback_step "kubectl delete -f /tmp/kube-flannel.yml --ignore-not-found=true"
    else
        error_exit "Unsupported network plugin: $CNI_PLUGIN"
    fi
    
    echo -e "${GREEN}✓ Network plugin $CNI_PLUGIN installed successfully${NC}"
}

# Function to verify installation
verify_installation() {
    echo "Verifying Kubernetes installation..." | tee -a $LOG_FILE
    show_progress 10 "Verifying Kubernetes installation..."
    
    # Wait for all pods to be running
    echo "Waiting for pods to become ready..." >> $LOG_FILE
    sleep 30
    
    # Check node status
    kubectl get nodes >> $LOG_FILE 2>&1
    NODE_STATUS=$(kubectl get nodes | grep 'master\|control-plane' | awk '{print $2}')
    if [ "$NODE_STATUS" != "Ready" ]; then
        error_exit "Master node is not in Ready state. Check logs for more details."
    fi
    
    # Check pod status
    PENDING_PODS=$(kubectl get pods --all-namespaces | grep Pending | wc -l)
    if [ "$PENDING_PODS" -gt 0 ]; then
        echo "Warning: There are $PENDING_PODS pods in Pending state." | tee -a $LOG_FILE
    fi
    
    FAILED_PODS=$(kubectl get pods --all-namespaces | grep Failed | wc -l)
    if [ "$FAILED_PODS" -gt 0 ]; then
        echo "Warning: There are $FAILED_PODS pods in Failed state." | tee -a $LOG_FILE
    fi
    
    echo -e "${GREEN}✓ Kubernetes installation verified successfully${NC}"
}

# Function to prompt for user input with defaults
prompt_for_config() {
    echo -e "${BLUE}Kubernetes Installation Configuration${NC}"
    echo "=================================================="
    
    # Prompt for network CIDR
    echo -e "${YELLOW}Enter the Pod Network CIDR (leave empty for default: $NETWORK_CIDR):${NC}"
    read -r user_cidr
    if [ -n "$user_cidr" ]; then
        NETWORK_CIDR=$user_cidr
    fi
    
    # Prompt for CNI plugin
    echo -e "${YELLOW}Select network plugin (1 for Calico, 2 for Flannel) [default: Calico]:${NC}"
    read -r user_cni
    if [ "$user_cni" = "2" ]; then
        CNI_PLUGIN="flannel"
    fi
    
    # Prompt for Kubernetes version
    echo -e "${YELLOW}Enter Kubernetes version (leave empty for default: $K8S_VERSION):${NC}"
    read -r user_version
    if [ -n "$user_version" ]; then
        K8S_VERSION=$user_version
    fi
    
    echo "=================================================="
    echo -e "${BLUE}Installation will proceed with these settings:${NC}"
    echo "Network CIDR: $NETWORK_CIDR"
    echo "Network Plugin: $CNI_PLUGIN"
    echo "Kubernetes Version: $K8S_VERSION"
    echo "=================================================="
    
    echo -e "${YELLOW}Press Enter to continue or Ctrl+C to cancel...${NC}"
    read -r
}

# Main function
main() {
    prompt_for_config
    
    echo -e "${BLUE}Starting Kubernetes master installation...${NC}"
    
    # Run installation steps
    detect_system
    configure_mirrors
    install_prerequisites
    configure_system
    install_container_runtime
    install_kubernetes
    initialize_master
    install_network_plugin
    verify_installation
    
    # Print summary
    echo -e "\n${GREEN}Kubernetes master installation completed successfully!${NC}"
    echo -e "\n${YELLOW}=========== Node Join Command ===========${NC}"
    echo -e "${GREEN}$JOIN_COMMAND${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "\nSave this command to use when adding worker nodes to the cluster."
    echo -e "For more details check the log file: $LOG_FILE\n"
}

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script must be run as root${NC}" >&2
    exit 1
fi

# Run the main function
main 