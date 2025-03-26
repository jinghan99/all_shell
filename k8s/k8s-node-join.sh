#!/bin/bash

#############################################################
# Kubernetes Node Join Script
# Features:
# - Auto-detects Linux distribution
# - Uses dnf if available, otherwise yum
# - Uses Chinese mirrors for faster downloads
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
LOG_FILE="/tmp/k8s_node_join_$(date +%Y%m%d%H%M%S).log"
K8S_VERSION="1.24.0"
ROLLBACK_STEPS=()
JOIN_COMMAND=""

# Banner
echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║                Kubernetes Node Join Script                 ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Initialize log file
echo "Kubernetes Node Join Log - $(date)" > $LOG_FILE
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
    echo "安装先决条件..." | tee -a $LOG_FILE
    show_progress 10 "安装系统先决条件..."
    
    # 添加回滚步骤
    add_rollback_step "$PKG_MANAGER -y remove curl wget yum-utils device-mapper-persistent-data lvm2 chrony 2>/dev/null || true"
    
    # 安装必要的软件包
    $PKG_MANAGER -y install curl wget yum-utils device-mapper-persistent-data lvm2 >> $LOG_FILE 2>&1 || error_exit "安装先决条件失败"
    
    # 安装并配置 chronyd 进行时间同步 (不再尝试安装 ntp，只安装 chrony)
    $PKG_MANAGER -y install chrony >> $LOG_FILE 2>&1 || error_exit "安装时间同步工具失败"
    systemctl enable chronyd >> $LOG_FILE 2>&1
    systemctl start chronyd >> $LOG_FILE 2>&1
    
    echo -e "${GREEN}✓ 先决条件安装成功${NC}"
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
    show_progress 15 "Installing kubelet and kubeadm..."
    
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
    $PKG_MANAGER install -y kubelet-$K8S_VERSION kubeadm-$K8S_VERSION >> $LOG_FILE 2>&1 || error_exit "Failed to install Kubernetes components"
    add_rollback_step "$PKG_MANAGER remove -y kubelet kubeadm"
    
    # Enable kubelet
    systemctl enable kubelet >> $LOG_FILE 2>&1
    
    echo -e "${GREEN}✓ Kubernetes components installed successfully${NC}"
}

# Function to join the node to cluster
join_cluster() {
    echo "Joining the Kubernetes cluster..." | tee -a $LOG_FILE
    show_progress 10 "Joining the Kubernetes cluster..."
    
    # Run join command
    echo "Running join command: $JOIN_COMMAND" >> $LOG_FILE
    eval "$JOIN_COMMAND" >> $LOG_FILE 2>&1 || error_exit "Failed to join the cluster"
    add_rollback_step "kubeadm reset -f"
    
    echo -e "${GREEN}✓ Node successfully joined the Kubernetes cluster${NC}"
}

# Function to verify node status
verify_join() {
    echo "Verifying node joined status..." | tee -a $LOG_FILE
    show_progress 5 "Verifying node status..."
    
    # Check if kubelet is running
    systemctl status kubelet >> $LOG_FILE 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Warning: kubelet service is not running properly${NC}" | tee -a $LOG_FILE
    else
        echo -e "${GREEN}✓ Kubelet service is running${NC}"
    fi
    
    echo -e "${GREEN}✓ Node join verification completed${NC}"
    echo -e "${YELLOW}Note: The master node needs to verify this node's status using 'kubectl get nodes'${NC}"
}

# Function to prompt for join command
prompt_for_join_command() {
    echo -e "${BLUE}Kubernetes Node Join Configuration${NC}"
    echo "=================================================="
    
    # Prompt for join command
    echo -e "${YELLOW}Enter the join command from the master node:${NC}"
    read -r JOIN_COMMAND
    
    if [ -z "$JOIN_COMMAND" ]; then
        error_exit "Join command cannot be empty"
    fi
    
    # Prompt for Kubernetes version
    echo -e "${YELLOW}Enter Kubernetes version (leave empty for default: $K8S_VERSION):${NC}"
    read -r user_version
    if [ -n "$user_version" ]; then
        K8S_VERSION=$user_version
    fi
    
    echo "=================================================="
    echo -e "${BLUE}Node will join with these settings:${NC}"
    echo "Kubernetes Version: $K8S_VERSION"
    echo "Join Command: $JOIN_COMMAND"
    echo "=================================================="
    
    echo -e "${YELLOW}Press Enter to continue or Ctrl+C to cancel...${NC}"
    read -r
}

# Main function
main() {
    prompt_for_join_command
    
    echo -e "${BLUE}Starting Kubernetes node join process...${NC}"
    
    # Run installation steps
    detect_system
    configure_mirrors
    install_prerequisites
    configure_system
    install_container_runtime
    install_kubernetes
    join_cluster
    verify_join
    
    # Print summary
    echo -e "\n${GREEN}Kubernetes node has successfully joined the cluster!${NC}"
    echo -e "\nFor more details check the log file: $LOG_FILE\n"
    echo -e "${YELLOW}To verify this node joined the cluster, run 'kubectl get nodes' on the master node.${NC}\n"
}

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script must be run as root${NC}" >&2
    exit 1
fi

# Run the main function
main 