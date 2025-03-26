#!/bin/bash

#############################################################
# Kubernetes Cluster Reset/Uninstall Script
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
LOG_FILE="/tmp/k8s_reset_$(date +%Y%m%d%H%M%S).log"
IS_MASTER=false
ROLLBACK_STEPS=()
INITIAL_STATE=()

# Banner
echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║             Kubernetes Cluster Reset Script                ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Initialize log file
echo "Kubernetes Reset Log - $(date)" > $LOG_FILE
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

# Function to save initial state
save_initial_state() {
    echo "Saving initial system state..." | tee -a $LOG_FILE
    
    # Check if kubelet is installed and running
    if systemctl is-active kubelet &>/dev/null; then
        INITIAL_STATE+=("kubelet_active")
    else
        INITIAL_STATE+=("kubelet_inactive")
    fi
    
    # Check if containerd is installed and running
    if systemctl is-active containerd &>/dev/null; then
        INITIAL_STATE+=("containerd_active")
    else
        INITIAL_STATE+=("containerd_inactive")
    fi
    
    # Check if this is a master node
    if [ -f /etc/kubernetes/admin.conf ]; then
        IS_MASTER=true
        INITIAL_STATE+=("is_master")
    else
        INITIAL_STATE+=("is_node")
    fi
    
    echo "Initial state saved: ${INITIAL_STATE[*]}" >> $LOG_FILE
}

# Function to perform rollback
perform_rollback() {
    echo "Starting rollback process..." | tee -a $LOG_FILE
    
    # Execute rollback steps in reverse order
    for ((i=${#ROLLBACK_STEPS[@]}-1; i>=0; i--)); do
        echo "Executing: ${ROLLBACK_STEPS[$i]}" >> $LOG_FILE
        eval "${ROLLBACK_STEPS[$i]}" >> $LOG_FILE 2>&1 || echo "Rollback step failed: ${ROLLBACK_STEPS[$i]}" >> $LOG_FILE
    done
    
    # Restore initial services state if required
    if [[ " ${INITIAL_STATE[*]} " =~ " kubelet_active " ]]; then
        echo "Restoring kubelet service..." >> $LOG_FILE
        systemctl start kubelet || echo "Failed to restore kubelet service" >> $LOG_FILE
    fi
    
    if [[ " ${INITIAL_STATE[*]} " =~ " containerd_active " ]]; then
        echo "Restoring containerd service..." >> $LOG_FILE
        systemctl start containerd || echo "Failed to restore containerd service" >> $LOG_FILE
    fi
    
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
}

# Function to configure Chinese mirrors for faster operations
configure_mirrors() {
    echo "Configuring Chinese mirrors..." | tee -a $LOG_FILE
    show_progress 5 "Configuring Chinese mirrors for faster operations..."
    
    if [ "$PKG_MANAGER" = "dnf" ]; then
        # Configure Alibaba Cloud mirror for DNF
        echo "fastestmirror=true" >> /etc/dnf/dnf.conf
        echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
    elif [ "$PKG_MANAGER" = "yum" ]; then
        # No need to configure yum mirrors for reset 
        echo "Using default YUM configuration for reset operations" >> $LOG_FILE
    fi
    
    echo -e "${GREEN}✓ Chinese mirrors configured successfully${NC}"
}

# Function to stop Kubernetes services
stop_kubernetes_services() {
    echo "Stopping Kubernetes services..." | tee -a $LOG_FILE
    show_progress 5 "Stopping Kubernetes services..."
    
    # Stop and disable kubelet
    systemctl stop kubelet || true
    systemctl disable kubelet || true
    
    echo -e "${GREEN}✓ Kubernetes services stopped successfully${NC}"
}

# Function to reset Kubernetes cluster
reset_kubernetes() {
    echo "Resetting Kubernetes cluster..." | tee -a $LOG_FILE
    show_progress 10 "Resetting Kubernetes cluster..."
    
    # Run kubeadm reset
    echo "Running kubeadm reset..." >> $LOG_FILE
    kubeadm reset -f >> $LOG_FILE 2>&1 || echo "Warning: kubeadm reset encountered issues" | tee -a $LOG_FILE
    
    # Remove config directories
    echo "Removing Kubernetes configuration directories..." >> $LOG_FILE
    rm -rf /etc/kubernetes/ || echo "Warning: Failed to remove /etc/kubernetes/" | tee -a $LOG_FILE
    rm -rf $HOME/.kube || echo "Warning: Failed to remove $HOME/.kube" | tee -a $LOG_FILE
    rm -f /etc/sysctl.d/k8s.conf || echo "Warning: Failed to remove /etc/sysctl.d/k8s.conf" | tee -a $LOG_FILE
    
    echo -e "${GREEN}✓ Kubernetes cluster reset successfully${NC}"
}

# Function to clean container runtime
clean_container_runtime() {
    echo "Cleaning container runtime..." | tee -a $LOG_FILE
    show_progress 10 "Cleaning container runtime..."
    
    # Stop and disable containerd
    systemctl stop containerd || true
    systemctl disable containerd || true
    
    # Remove containerd configuration
    rm -rf /etc/containerd || echo "Warning: Failed to remove /etc/containerd" | tee -a $LOG_FILE
    
    echo -e "${GREEN}✓ Container runtime cleaned successfully${NC}"
}

# Function to remove Kubernetes packages
remove_kubernetes_packages() {
    echo "Removing Kubernetes packages..." | tee -a $LOG_FILE
    show_progress 15 "Removing Kubernetes packages..."
    
    # Remove Kubernetes packages
    $PKG_MANAGER remove -y kubelet kubeadm kubectl --noautoremove >> $LOG_FILE 2>&1 || echo "Warning: Failed to remove some Kubernetes packages" | tee -a $LOG_FILE
    
    # Remove containerd package
    $PKG_MANAGER remove -y containerd.io >> $LOG_FILE 2>&1 || echo "Warning: Failed to remove containerd.io" | tee -a $LOG_FILE
    
    # Remove Kubernetes repo
    rm -f /etc/yum.repos.d/kubernetes.repo || echo "Warning: Failed to remove Kubernetes repo" | tee -a $LOG_FILE
    
    echo -e "${GREEN}✓ Kubernetes packages removed successfully${NC}"
}

# Function to clean network configurations
clean_network_configurations() {
    echo "Cleaning network configurations..." | tee -a $LOG_FILE
    show_progress 10 "Cleaning network configurations..."
    
    # Remove CNI configurations
    rm -rf /etc/cni/net.d/* || echo "Warning: Failed to remove CNI configurations" | tee -a $LOG_FILE
    
    # Remove CNI binaries
    rm -rf /opt/cni || echo "Warning: Failed to remove CNI binaries" | tee -a $LOG_FILE
    
    # Reset iptables
    echo "Resetting iptables rules..." >> $LOG_FILE
    iptables -F >> $LOG_FILE 2>&1 || echo "Warning: Failed to flush iptables rules" | tee -a $LOG_FILE
    iptables -X >> $LOG_FILE 2>&1 || echo "Warning: Failed to delete iptables chains" | tee -a $LOG_FILE
    iptables -t nat -F >> $LOG_FILE 2>&1 || echo "Warning: Failed to flush nat table" | tee -a $LOG_FILE
    iptables -t nat -X >> $LOG_FILE 2>&1 || echo "Warning: Failed to delete nat chains" | tee -a $LOG_FILE
    iptables -t mangle -F >> $LOG_FILE 2>&1 || echo "Warning: Failed to flush mangle table" | tee -a $LOG_FILE
    iptables -t mangle -X >> $LOG_FILE 2>&1 || echo "Warning: Failed to delete mangle chains" | tee -a $LOG_FILE
    
    # Remove IP routes
    echo "Removing IP routes..." >> $LOG_FILE
    ip route flush proto bird >> $LOG_FILE 2>&1 || echo "Warning: Failed to flush bird routes" | tee -a $LOG_FILE
    
    echo -e "${GREEN}✓ Network configurations cleaned successfully${NC}"
}

# Function to clean Kubernetes data directories
clean_data_directories() {
    echo "Cleaning Kubernetes data directories..." | tee -a $LOG_FILE
    show_progress 10 "Cleaning Kubernetes data directories..."
    
    # Remove Kubernetes data directories
    rm -rf /var/lib/kubelet || echo "Warning: Failed to remove /var/lib/kubelet" | tee -a $LOG_FILE
    rm -rf /var/lib/etcd || echo "Warning: Failed to remove /var/lib/etcd" | tee -a $LOG_FILE
    rm -rf /var/lib/cni || echo "Warning: Failed to remove /var/lib/cni" | tee -a $LOG_FILE
    rm -rf /var/run/kubernetes || echo "Warning: Failed to remove /var/run/kubernetes" | tee -a $LOG_FILE
    rm -rf /var/lib/calico || echo "Warning: Failed to remove /var/lib/calico" | tee -a $LOG_FILE
    rm -rf /var/lib/weave || echo "Warning: Failed to remove /var/lib/weave" | tee -a $LOG_FILE
    rm -rf /var/lib/flannel || echo "Warning: Failed to remove /var/lib/flannel" | tee -a $LOG_FILE
    
    echo -e "${GREEN}✓ Kubernetes data directories cleaned successfully${NC}"
}

# Function to restore system settings
restore_system_settings() {
    echo "Restoring system settings..." | tee -a $LOG_FILE
    show_progress 5 "Restoring system settings..."
    
    # Re-enable SELinux if it was disabled
    if [ -f /etc/selinux/config.backup ]; then
        echo "Restoring SELinux configuration..." >> $LOG_FILE
        cp /etc/selinux/config.backup /etc/selinux/config || echo "Warning: Failed to restore SELinux configuration" | tee -a $LOG_FILE
    fi
    
    # Restore swap if it was disabled
    if [ -f /etc/fstab.backup ]; then
        echo "Restoring swap configuration..." >> $LOG_FILE
        cp /etc/fstab.backup /etc/fstab || echo "Warning: Failed to restore swap configuration" | tee -a $LOG_FILE
        swapon -a || echo "Warning: Failed to enable swap" | tee -a $LOG_FILE
    fi
    
    # Reset kernel parameters
    echo "Resetting kernel parameters..." >> $LOG_FILE
    sysctl --system >> $LOG_FILE 2>&1 || echo "Warning: Failed to reset kernel parameters" | tee -a $LOG_FILE
    
    echo -e "${GREEN}✓ System settings restored successfully${NC}"
}

# Function to clean orphaned files
clean_orphaned_files() {
    echo "Cleaning orphaned files..." | tee -a $LOG_FILE
    show_progress 5 "Cleaning orphaned files..."
    
    # Remove modules-load.d configuration
    rm -f /etc/modules-load.d/k8s.conf || echo "Warning: Failed to remove k8s module configuration" | tee -a $LOG_FILE
    
    # Remove Docker repo
    rm -f /etc/yum.repos.d/docker-ce.repo || echo "Warning: Failed to remove Docker repo" | tee -a $LOG_FILE
    
    # Clear package manager cache
    $PKG_MANAGER clean all >> $LOG_FILE 2>&1 || echo "Warning: Failed to clean package manager cache" | tee -a $LOG_FILE
    
    echo -e "${GREEN}✓ Orphaned files cleaned successfully${NC}"
}

# Function to verify reset
verify_reset() {
    echo "Verifying reset..." | tee -a $LOG_FILE
    show_progress 5 "Verifying Kubernetes is completely removed..."
    
    # Check if Kubernetes services are running
    if systemctl is-active kubelet &>/dev/null; then
        echo -e "${YELLOW}Warning: kubelet service is still active${NC}" | tee -a $LOG_FILE
    fi
    
    if systemctl is-active containerd &>/dev/null; then
        echo -e "${YELLOW}Warning: containerd service is still active${NC}" | tee -a $LOG_FILE
    fi
    
    # Check for Kubernetes directories
    for dir in /etc/kubernetes /var/lib/kubelet /var/lib/etcd /etc/cni/net.d; do
        if [ -d "$dir" ]; then
            echo -e "${YELLOW}Warning: Directory $dir still exists${NC}" | tee -a $LOG_FILE
        fi
    done
    
    echo -e "${GREEN}✓ Reset verification completed${NC}"
}

# Function to prompt before reset
prompt_before_reset() {
    echo -e "${RED}WARNING: This will completely remove Kubernetes from this system!${NC}"
    echo -e "${RED}All Kubernetes configurations, data, and containers will be deleted.${NC}"
    echo -e "${YELLOW}This operation cannot be undone.${NC}"
    echo ""
    echo -e "${YELLOW}Do you want to continue? (yes/no)${NC}"
    read -r confirm
    
    if [ "$confirm" != "yes" ]; then
        echo -e "${GREEN}Reset operation cancelled.${NC}"
        exit 0
    fi
}

# Main function
main() {
    prompt_before_reset
    save_initial_state
    
    echo -e "${BLUE}Starting Kubernetes reset process...${NC}"
    
    # Run reset steps
    detect_system
    configure_mirrors
    stop_kubernetes_services
    reset_kubernetes
    clean_container_runtime
    remove_kubernetes_packages
    clean_network_configurations
    clean_data_directories
    restore_system_settings
    clean_orphaned_files
    verify_reset
    
    # Print summary
    echo -e "\n${GREEN}Kubernetes has been successfully removed from this system!${NC}"
    echo -e "\nFor more details check the log file: $LOG_FILE\n"
    
    # If there were any warnings, display them
    if grep -q "Warning:" $LOG_FILE; then
        echo -e "${YELLOW}The following warnings were encountered during reset:${NC}"
        grep "Warning:" $LOG_FILE | sed 's/Warning: /- /'
        echo -e "\n${YELLOW}These warnings might indicate some components weren't completely removed.${NC}"
        echo -e "${YELLOW}Check the log file for more details.${NC}\n"
    fi
}

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script must be run as root${NC}" >&2
    exit 1
fi

# Run the main function
main 