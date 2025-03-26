#!/bin/bash

#############################################################
# Kubernetes Master 节点安装脚本
# 特性:
# - 自动检测 Linux 发行版
# - 根据系统使用 dnf 或 yum
# - 使用中国镜像源加速下载
# - 自动配置网络设置
# - 显示进度条
# - 提供错误处理和回滚功能
#############################################################

set -e

# 文本颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 全局变量
PKG_MANAGER=""
LOG_FILE="/tmp/k8s_master_install_$(date +%Y%m%d%H%M%S).log"
NETWORK_CIDR="192.168.0.0/16"
CNI_PLUGIN="calico" # calico 或 flannel
HOST_IP=$(ip -o -4 addr list | grep -v "127.0.0.1" | awk '{print $4}' | cut -d/ -f1 | head -n1)
K8S_VERSION="1.24.0"
ROLLBACK_STEPS=()
JOIN_COMMAND=""
USE_LEGACY_REPOS=false

# 横幅
echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║              Kubernetes Master 节点安装程序                ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# 初始化日志文件
echo "Kubernetes Master 安装日志 - $(date)" > $LOG_FILE
echo "==============================================" >> $LOG_FILE

# 显示进度条函数
show_progress() {
    local duration=$1
    local message=$2
    local elapsed=0
    local progress=0
    local bar_size=40
    
    echo -e "${YELLOW}$message${NC}"
    
    while [ $elapsed -lt $duration ]; do
        progress=$(( (elapsed * bar_size) / duration ))
        
        # 创建进度条
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

# 记录错误并退出函数
error_exit() {
    local message=$1
    echo -e "${RED}错误: $message${NC}" | tee -a $LOG_FILE
    echo -e "${YELLOW}查看日志文件获取详细信息: $LOG_FILE${NC}"
    echo -e "${YELLOW}执行回滚操作...${NC}"
    perform_rollback
    exit 1
}

# 添加回滚步骤函数
add_rollback_step() {
    ROLLBACK_STEPS+=("$1")
}

# 执行回滚函数
perform_rollback() {
    echo "开始回滚过程..." | tee -a $LOG_FILE
    
    # 按照相反顺序执行回滚步骤
    for ((i=${#ROLLBACK_STEPS[@]}-1; i>=0; i--)); do
        echo "执行: ${ROLLBACK_STEPS[$i]}" >> $LOG_FILE
        eval "${ROLLBACK_STEPS[$i]}" >> $LOG_FILE 2>&1 || echo "回滚步骤失败: ${ROLLBACK_STEPS[$i]}" >> $LOG_FILE
    done
    
    echo -e "${GREEN}回滚完成。系统已恢复到初始状态。${NC}" | tee -a $LOG_FILE
}

# 检测 Linux 发行版和包管理器函数
detect_system() {
    echo "检测系统信息..." | tee -a $LOG_FILE
    
    # 首先检查 dnf
    if command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        echo "检测到 DNF 包管理器。" >> $LOG_FILE
    # 否则检查 yum
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        echo "检测到 YUM 包管理器。" >> $LOG_FILE
    else
        error_exit "未找到 DNF 或 YUM 包管理器。此脚本仅支持基于 RHEL 的发行版。"
    fi
    
    # 检测 Linux 发行版
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$NAME
        VERSION_ID=$VERSION_ID
        echo "检测到发行版: $DISTRO $VERSION_ID" >> $LOG_FILE
        
        # 根据不同发行版设置特定配置
        case "$ID" in
            rhel|centos|rocky|almalinux|ol)
                MAJOR_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)
                echo "检测到 RHEL 系列发行版，主版本: $MAJOR_VERSION" >> $LOG_FILE
                
                # RHEL/CentOS 8+ 使用不同的仓库和配置
                if [ "$MAJOR_VERSION" -ge 8 ]; then
                    USE_LEGACY_REPOS=false
                    echo "将使用现代仓库配置" >> $LOG_FILE
                else
                    USE_LEGACY_REPOS=true
                    echo "将使用传统仓库配置" >> $LOG_FILE
                fi
                ;;
            fedora)
                echo "检测到 Fedora" >> $LOG_FILE
                USE_LEGACY_REPOS=false
                ;;
            *)
                echo "未明确支持的发行版，将尝试通用配置" >> $LOG_FILE
                USE_LEGACY_REPOS=false
                ;;
        esac
        
        echo -e "${GREEN}✓ 系统检测: $DISTRO $VERSION_ID 使用 $PKG_MANAGER${NC}"
    else
        error_exit "无法检测 Linux 发行版。"
    fi
    
    # 添加包管理器配置的回滚步骤
    add_rollback_step "echo '暂无包管理器配置需要回滚。'"
}

# 配置中国镜像源函数
configure_mirrors() {
    echo "配置中国镜像源..." | tee -a $LOG_FILE
    show_progress 5 "配置中国镜像源以加快下载速度..."
    
    # 首先备份所有原始仓库文件
    echo "备份原始仓库文件..." >> $LOG_FILE
    mkdir -p /etc/yum.repos.d.backup
    if [ -f /etc/yum.conf ]; then
        cp -f /etc/yum.conf /etc/yum.conf.backup 2>/dev/null || true
    fi
    if [ -f /etc/dnf/dnf.conf ]; then
        cp -f /etc/dnf/dnf.conf /etc/dnf/dnf.conf.backup 2>/dev/null || true
    fi
    
    # 备份所有仓库文件，但不要删除它们
    if [ -d /etc/yum.repos.d ]; then
        find /etc/yum.repos.d -name "*.repo" -exec cp -f {} /etc/yum.repos.d.backup/ \; 2>/dev/null || true
    fi
    
    # 添加回滚步骤
    add_rollback_step "find /etc/yum.repos.d.backup -name \"*.repo\" -exec cp -f {} /etc/yum.repos.d/ \; 2>/dev/null || true"
    if [ -f /etc/yum.conf.backup ]; then
        add_rollback_step "cp -f /etc/yum.conf.backup /etc/yum.conf 2>/dev/null || true"
    fi
    if [ -f /etc/dnf/dnf.conf.backup ]; then
        add_rollback_step "cp -f /etc/dnf/dnf.conf.backup /etc/dnf/dnf.conf 2>/dev/null || true"
    fi
    
    # 根据发行版配置镜像源
    if [ "$PKG_MANAGER" = "dnf" ]; then
        # 为 DNF 配置阿里云镜像
        if [ -f /etc/dnf/dnf.conf ]; then
            echo "配置 DNF 参数..." >> $LOG_FILE
            grep -q "fastestmirror" /etc/dnf/dnf.conf || echo "fastestmirror=true" >> /etc/dnf/dnf.conf
            grep -q "max_parallel_downloads" /etc/dnf/dnf.conf || echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
        fi
        
        # 根据发行版选择合适的镜像源
        case "$ID" in
            rocky)
                echo "配置 Rocky Linux 镜像源..." >> $LOG_FILE
                # 确保不删除原始仓库文件，只修改它们
                for repo in BaseOS AppStream extras; do
                    if [ -f "/etc/yum.repos.d/Rocky-$repo.repo" ]; then
                        sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/Rocky-$repo.repo
                        sed -i "s|^#baseurl=http://dl.rockylinux.org/\$contentdir|baseurl=https://mirrors.aliyun.com/rockylinux|g" /etc/yum.repos.d/Rocky-$repo.repo
                    fi
                done
                ;;
            almalinux)
                echo "配置 AlmaLinux 镜像源..." >> $LOG_FILE
                for repo in BaseOS AppStream extras; do
                    if [ -f "/etc/yum.repos.d/AlmaLinux-$repo.repo" ]; then
                        sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/AlmaLinux-$repo.repo
                        sed -i "s|^#baseurl=https://repo.almalinux.org|baseurl=https://mirrors.aliyun.com/almalinux|g" /etc/yum.repos.d/AlmaLinux-$repo.repo
                    fi
                done
                ;;
            centos)
                echo "配置 CentOS 镜像源..." >> $LOG_FILE
                if [ "$USE_LEGACY_REPOS" = "true" ]; then
                    # CentOS 7
                    if [ -f /etc/yum.repos.d/CentOS-Base.repo ]; then
                        cp -f /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup
                        curl -s -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
                        sed -i 's/http:/https:/g' /etc/yum.repos.d/CentOS-Base.repo
                    fi
                else
                    # CentOS 8
                    if [ -f /etc/yum.repos.d/CentOS-Base.repo ]; then
                        cp -f /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup
                        curl -s -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-8.repo
                        sed -i 's/http:/https:/g' /etc/yum.repos.d/CentOS-Base.repo
                    fi
                fi
                ;;
            rhel)
                echo "RHEL 系统不修改基础仓库，请确保系统已注册" >> $LOG_FILE
                ;;
            *)
                echo "未识别的发行版 $ID，保留原始仓库配置" >> $LOG_FILE
                ;;
        esac
    elif [ "$PKG_MANAGER" = "yum" ]; then
        # 为 YUM 配置阿里云镜像，逻辑与 DNF 部分类似
        echo "配置 YUM 镜像源..." >> $LOG_FILE
        # 在这里添加 YUM 配置逻辑，与 DNF 部分类似
    fi
    
    # 确保仓库目录存在
    if [ ! -d /etc/yum.repos.d ]; then
        mkdir -p /etc/yum.repos.d
    fi
    
    # 检查是否有仓库文件
    REPO_COUNT=$(find /etc/yum.repos.d -name "*.repo" | wc -l)
    if [ "$REPO_COUNT" -eq 0 ]; then
        echo "警告: 未找到仓库文件，创建基本仓库文件..." | tee -a $LOG_FILE
        
        # 根据发行版创建基本仓库文件
        case "$ID" in
            rocky)
                cat > /etc/yum.repos.d/Rocky-BaseOS.repo << EOF
[baseos]
name=Rocky Linux \$releasever - BaseOS
baseurl=https://mirrors.aliyun.com/rockylinux/\$releasever/BaseOS/\$basearch/os/
enabled=1
gpgcheck=0
EOF
                cat > /etc/yum.repos.d/Rocky-AppStream.repo << EOF
[appstream]
name=Rocky Linux \$releasever - AppStream
baseurl=https://mirrors.aliyun.com/rockylinux/\$releasever/AppStream/\$basearch/os/
enabled=1
gpgcheck=0
EOF
                ;;
            # 其他发行版的基本仓库配置...
        esac
    fi
    
    # 更新仓库缓存
    echo "更新仓库缓存..." >> $LOG_FILE
    $PKG_MANAGER clean all >> $LOG_FILE 2>&1 || echo "警告: 清理缓存失败，继续安装" | tee -a $LOG_FILE
    $PKG_MANAGER makecache >> $LOG_FILE 2>&1 || error_exit "创建 $PKG_MANAGER 缓存失败"
    
    # 验证仓库是否可用
    echo "验证仓库可用性..." >> $LOG_FILE
    $PKG_MANAGER repolist >> $LOG_FILE 2>&1 || error_exit "无可用仓库，请检查网络连接和仓库配置"
    
    echo -e "${GREEN}✓ 中国镜像源配置成功${NC}"
}

# 安装先决条件函数
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

# 配置系统设置函数
configure_system() {
    echo "配置系统设置..." | tee -a $LOG_FILE
    show_progress 8 "为 Kubernetes 配置系统设置..."
    
    # 禁用 SELinux
    if [ -f /etc/selinux/config ]; then
        cp /etc/selinux/config /etc/selinux/config.backup
        add_rollback_step "cp /etc/selinux/config.backup /etc/selinux/config"
        sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
        setenforce 0 || true
    fi
    
    # 禁用交换分区
    swapoff -a
    
    # 注释掉 /etc/fstab 中的交换分区条目
    if [ -f /etc/fstab ]; then
        cp /etc/fstab /etc/fstab.backup
        add_rollback_step "cp /etc/fstab.backup /etc/fstab"
        sed -i '/swap/s/^/#/' /etc/fstab
    fi
    
    # 加载必要的内核模块
    cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
    
    # 确保模块已加载
    modprobe overlay
    modprobe br_netfilter
    
    # 设置内核参数
    cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
    add_rollback_step "rm -f /etc/sysctl.d/k8s.conf"
    
    # 应用内核参数
    sysctl --system >> $LOG_FILE 2>&1
    
    echo -e "${GREEN}✓ 系统设置配置成功${NC}"
}

# 安装容器运行时(containerd)函数
install_container_runtime() {
    echo "安装容器运行时(containerd)..." | tee -a $LOG_FILE
    show_progress 15 "安装和配置 containerd..."
    
    # 添加 Docker 仓库
    yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    add_rollback_step "rm -f /etc/yum.repos.d/docker-ce.repo"
    
    # 安装 containerd
    $PKG_MANAGER install -y containerd.io >> $LOG_FILE 2>&1 || error_exit "安装 containerd 失败"
    add_rollback_step "$PKG_MANAGER remove -y containerd.io"
    
    # 配置 containerd
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    add_rollback_step "rm -f /etc/containerd/config.toml"
    
    # 将 SystemdCgroup 设置为 true
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    
    # 配置 containerd 使用阿里云镜像仓库
    sed -i 's|https://registry-1.docker.io|https://registry.cn-hangzhou.aliyuncs.com|g' /etc/containerd/config.toml
    
    # 配置 containerd 使用 systemd cgroup 驱动
    cat > /etc/containerd/config.toml << EOF
version = 2
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.7"
    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true
    [plugins."io.containerd.grpc.v1.cri".registry]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
          endpoint = ["https://registry.cn-hangzhou.aliyuncs.com"]
EOF
    
    # 重启 containerd
    systemctl enable containerd >> $LOG_FILE 2>&1
    systemctl restart containerd >> $LOG_FILE 2>&1
    
    echo -e "${GREEN}✓ Containerd 安装和配置成功${NC}"
}

# 安装 Kubernetes 组件函数
install_kubernetes() {
    echo "安装 Kubernetes 组件..." | tee -a $LOG_FILE
    show_progress 15 "安装 kubeadm, kubelet 和 kubectl..."
    
    # 使用阿里云镜像添加 Kubernetes 仓库
    cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
    add_rollback_step "rm -f /etc/yum.repos.d/kubernetes.repo"
    
    # 对于 RHEL 8+ 系统，可能需要额外设置
    if [ "$USE_LEGACY_REPOS" = "false" ]; then
        # 添加 overlay 和 br_netfilter 模块
        cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
        # 确保模块已加载
        modprobe overlay
        modprobe br_netfilter
    fi
    
    # 安装 Kubernetes 组件
    # 注意：对于某些系统，可能需要禁用 repo_gpgcheck
    $PKG_MANAGER install -y kubelet-$K8S_VERSION kubeadm-$K8S_VERSION kubectl-$K8S_VERSION --disableexcludes=kubernetes >> $LOG_FILE 2>&1 || error_exit "安装 Kubernetes 组件失败"
    add_rollback_step "$PKG_MANAGER remove -y kubelet kubeadm kubectl"
    
    # 启用 kubelet
    systemctl enable kubelet >> $LOG_FILE 2>&1
    
    # 配置 kubelet 使用 systemd cgroup 驱动
    mkdir -p /etc/systemd/system/kubelet.service.d/
    cat > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf << EOF
# 注意: 此文件由安装程序自动创建
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
# 这是 "kubeadm init" 和 "kubeadm join" 运行时使用的文件
# 这里添加了 cgroup-driver=systemd
Environment="KUBELET_EXTRA_ARGS=--cgroup-driver=systemd"
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_KUBECONFIG_ARGS \$KUBELET_CONFIG_ARGS \$KUBELET_KUBEADM_ARGS \$KUBELET_EXTRA_ARGS
EOF
    systemctl daemon-reload
    
    # 在 kubeadm 配置中设置版本
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
    
    echo -e "${GREEN}✓ Kubernetes 组件安装成功${NC}"
}

# 初始化 Kubernetes master 函数
initialize_master() {
    echo "初始化 Kubernetes master..." | tee -a $LOG_FILE
    show_progress 20 "初始化 Kubernetes master 节点..."
    
    # 从阿里云镜像拉取所需镜像
    echo "拉取 Kubernetes 镜像..." >> $LOG_FILE
    kubeadm config images pull --config=/tmp/kubeadm-config.yaml >> $LOG_FILE 2>&1 || error_exit "拉取 Kubernetes 镜像失败"
    
    # 初始化 master 节点，增加超时时间和详细日志
    echo "运行 kubeadm init..." >> $LOG_FILE
    kubeadm init --config=/tmp/kubeadm-config.yaml --upload-certs --v=5 --ignore-preflight-errors=all >> $LOG_FILE 2>&1 || error_exit "初始化 Kubernetes master 失败"
    add_rollback_step "kubeadm reset -f"
    
    # 为当前用户配置 kubectl
    mkdir -p $HOME/.kube
    cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
    add_rollback_step "rm -rf $HOME/.kube"
    
    # 提取加入命令
    JOIN_COMMAND=$(kubeadm token create --print-join-command)
    
    echo -e "${GREEN}✓ Kubernetes master 初始化成功${NC}"
}

# 安装网络插件(Calico 或 Flannel)函数
install_network_plugin() {
    echo "安装网络插件($CNI_PLUGIN)..." | tee -a $LOG_FILE
    show_progress 15 "安装 $CNI_PLUGIN 网络插件..."
    
    if [ "$CNI_PLUGIN" = "calico" ]; then
        # 安装 Calico
        echo "安装 Calico CNI..." >> $LOG_FILE
        wget -q https://docs.projectcalico.org/manifests/calico.yaml -O /tmp/calico.yaml
        
        # 如果需要，替换 CIDR
        sed -i "s|192.168.0.0/16|$NETWORK_CIDR|g" /tmp/calico.yaml
        
        # 应用 calico 清单
        kubectl apply -f /tmp/calico.yaml >> $LOG_FILE 2>&1 || error_exit "应用 Calico 清单失败"
        add_rollback_step "kubectl delete -f /tmp/calico.yaml --ignore-not-found=true"
    elif [ "$CNI_PLUGIN" = "flannel" ]; then
        # 安装 Flannel
        echo "安装 Flannel CNI..." >> $LOG_FILE
        wget -q https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml -O /tmp/kube-flannel.yml
        
        # 如果需要，替换 CIDR
        sed -i "s|10.244.0.0/16|$NETWORK_CIDR|g" /tmp/kube-flannel.yml
        
        # 应用 flannel 清单
        kubectl apply -f /tmp/kube-flannel.yml >> $LOG_FILE 2>&1 || error_exit "应用 Flannel 清单失败"
        add_rollback_step "kubectl delete -f /tmp/kube-flannel.yml --ignore-not-found=true"
    else
        error_exit "不支持的网络插件: $CNI_PLUGIN"
    fi
    
    echo -e "${GREEN}✓ 网络插件 $CNI_PLUGIN 安装成功${NC}"
}

# 验证安装函数
verify_installation() {
    echo "验证 Kubernetes 安装..." | tee -a $LOG_FILE
    show_progress 10 "验证 Kubernetes 安装..."
    
    # 等待所有 pod 运行
    echo "等待 pod 就绪..." >> $LOG_FILE
    sleep 30
    
    # 检查节点状态
    kubectl get nodes >> $LOG_FILE 2>&1
    NODE_STATUS=$(kubectl get nodes | grep 'master\|control-plane' | awk '{print $2}')
    if [ "$NODE_STATUS" != "Ready" ]; then
        error_exit "Master 节点未处于 Ready 状态。查看日志获取更多详细信息。"
    fi
    
    # 检查 pod 状态
    PENDING_PODS=$(kubectl get pods --all-namespaces | grep Pending | wc -l)
    if [ "$PENDING_PODS" -gt 0 ]; then
        echo "警告: 有 $PENDING_PODS 个 pod 处于 Pending 状态。" | tee -a $LOG_FILE
    fi
    
    FAILED_PODS=$(kubectl get pods --all-namespaces | grep Failed | wc -l)
    if [ "$FAILED_PODS" -gt 0 ]; then
        echo "警告: 有 $FAILED_PODS 个 pod 处于 Failed 状态。" | tee -a $LOG_FILE
    fi
    
    echo -e "${GREEN}✓ Kubernetes 安装验证成功${NC}"
}

# 函数：检测可用的网络接口和IP段
detect_network_interfaces() {
    echo "检测网络接口和IP段..." | tee -a $LOG_FILE
    show_progress 3 "检测网络接口和IP段..."
    
    # 获取所有非回环网络接口的IP地址和子网掩码
    INTERFACES=()
    IP_RANGES=()
    
    # 使用ip命令获取网络接口信息
    while read -r line; do
        if [[ $line =~ ^[0-9]+:\ ([^:]+):.*$ ]]; then
            IFACE="${BASH_REMATCH[1]}"
            if [[ "$IFACE" != "lo" ]]; then
                IP_INFO=$(ip -o -4 addr show dev "$IFACE" | awk '{print $4}')
                if [[ -n "$IP_INFO" ]]; then
                    INTERFACES+=("$IFACE")
                    IP_RANGES+=("$IP_INFO")
                fi
            fi
        fi
    done < <(ip -o link show)
    
    echo "检测到以下网络接口和IP段:" >> $LOG_FILE
    for i in "${!INTERFACES[@]}"; do
        echo "  ${INTERFACES[$i]}: ${IP_RANGES[$i]}" >> $LOG_FILE
    done
    
    echo -e "${GREEN}✓ 网络接口和IP段检测完成${NC}"
}

# 修改提示用户输入默认值的函数
prompt_for_config() {
    echo -e "${BLUE}Kubernetes 安装配置${NC}"
    echo "=================================================="
    
    # 检测网络接口和IP段
    detect_network_interfaces
    
    # 显示可用的网络接口和IP段
    echo -e "${YELLOW}检测到以下网络接口和IP段:${NC}"
    for i in "${!INTERFACES[@]}"; do
        echo "  $((i+1)). ${INTERFACES[$i]}: ${IP_RANGES[$i]}"
    done
    
    # 默认使用第一个网络接口的IP段
    DEFAULT_IP_RANGE="192.168.1.0/24"
    if [ ${#IP_RANGES[@]} -gt 0 ]; then
        # 从第一个IP范围中提取网段
        IP_PART=$(echo "${IP_RANGES[0]}" | cut -d'/' -f1 | cut -d'.' -f1-3)
        DEFAULT_IP_RANGE="${IP_PART}.0/24"
    fi
    
    # 提示选择网络接口
    echo -e "${YELLOW}选择要使用的网络接口 (输入编号) [默认: 1]:${NC}"
    read -r iface_choice
    
    # 如果用户输入了有效的选择，则使用该接口的IP段
    if [[ -n "$iface_choice" && "$iface_choice" -le "${#INTERFACES[@]}" && "$iface_choice" -gt 0 ]]; then
        SELECTED_IFACE="${INTERFACES[$((iface_choice-1))]}"
        IP_PART=$(echo "${IP_RANGES[$((iface_choice-1))]}" | cut -d'/' -f1 | cut -d'.' -f1-3)
        DEFAULT_IP_RANGE="${IP_PART}.0/24"
    fi
    
    # 提示输入网络 CIDR
    echo -e "${YELLOW}输入 Pod 网络 CIDR (留空使用默认值: $DEFAULT_IP_RANGE):${NC}"
    read -r user_cidr
    if [ -n "$user_cidr" ]; then
        NETWORK_CIDR=$user_cidr
    else
        NETWORK_CIDR=$DEFAULT_IP_RANGE
    fi
    
    # 提示选择 CNI 插件
    echo -e "${YELLOW}选择网络插件 (1 表示 Calico, 2 表示 Flannel) [默认: Calico]:${NC}"
    read -r user_cni
    if [ "$user_cni" = "2" ]; then
        CNI_PLUGIN="flannel"
    fi
    
    # 提示输入 Kubernetes 版本
    echo -e "${YELLOW}输入 Kubernetes 版本 (留空使用默认值: $K8S_VERSION):${NC}"
    read -r user_version
    if [ -n "$user_version" ]; then
        K8S_VERSION=$user_version
    fi
    
    echo "=================================================="
    echo -e "${BLUE}安装将使用以下设置:${NC}"
    echo "网络 CIDR: $NETWORK_CIDR"
    echo "网络插件: $CNI_PLUGIN"
    echo "Kubernetes 版本: $K8S_VERSION"
    echo "=================================================="
    
    echo -e "${YELLOW}按 Enter 继续或 Ctrl+C 取消...${NC}"
    read -r
}

# 检查硬件要求函数
check_hardware_requirements() {
    echo "检查硬件要求..." | tee -a $LOG_FILE
    show_progress 3 "检查硬件要求..."
    
    # 检查CPU核心数 - Kubernetes至少需要2个核心才能正常运行
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -lt 2 ]; then
        error_exit "CPU核心数不足。Kubernetes至少需要2个CPU核心，当前只有 $CPU_CORES 个。"
    fi
    
    # 检查内存 - Kubernetes至少需要2GB内存(使用1700MB作为阈值，以适应不同的内存报告方式)
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_MEM" -lt 1700 ]; then
        error_exit "内存不足。Kubernetes至少需要2GB内存，当前只有 ${TOTAL_MEM}MB。"
    fi
    
    # 检查磁盘空间 - Kubernetes至少需要20GB可用空间用于存储镜像、容器和日志
    # sed命令用于移除df输出中的'G'后缀，以获取数值
    DISK_SPACE=$(df -h / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "${DISK_SPACE%.*}" -lt 20 ]; then
        error_exit "磁盘空间不足。Kubernetes至少需要20GB可用空间，当前只有 ${DISK_SPACE}GB。"
    fi
    
    echo -e "${GREEN}✓ 硬件要求满足${NC}"
}

# 检查系统兼容性
check_system_compatibility() {
    echo "检查系统兼容性..." | tee -a $LOG_FILE
    show_progress 5 "检查系统兼容性..."
    
    # 检查 CPU 架构
    ARCH=$(uname -m)
    if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "amd64" ]; then
        echo -e "${YELLOW}警告: 检测到非 x86_64 架构: $ARCH${NC}" | tee -a $LOG_FILE
        echo -e "${YELLOW}Kubernetes 可能在此架构上不稳定${NC}" | tee -a $LOG_FILE
    fi
    
    # 检查内核版本
    KERNEL_VERSION=$(uname -r | cut -d'-' -f1)
    KERNEL_MAJOR=$(echo $KERNEL_VERSION | cut -d'.' -f1)
    KERNEL_MINOR=$(echo $KERNEL_VERSION | cut -d'.' -f2)
    
    if [ "$KERNEL_MAJOR" -lt 4 ] || ([ "$KERNEL_MAJOR" -eq 4 ] && [ "$KERNEL_MINOR" -lt 4 ]); then
        echo -e "${YELLOW}警告: 内核版本 $KERNEL_VERSION 低于推荐的 4.4${NC}" | tee -a $LOG_FILE
        echo -e "${YELLOW}某些 Kubernetes 功能可能不可用${NC}" | tee -a $LOG_FILE
    fi
    
    # 检查 cgroups
    if [ ! -d "/sys/fs/cgroup/systemd" ]; then
        echo -e "${YELLOW}警告: systemd cgroup 不可用${NC}" | tee -a $LOG_FILE
        echo -e "${YELLOW}这可能导致 kubelet 启动问题${NC}" | tee -a $LOG_FILE
    fi
    
    echo -e "${GREEN}✓ 系统兼容性检查完成${NC}"
}

# 主函数
main() {
    prompt_for_config
    
    echo -e "${BLUE}开始安装 Kubernetes master...${NC}"
    
    # 运行安装步骤
    detect_system
    check_hardware_requirements
    check_system_compatibility
    configure_mirrors
    install_prerequisites
    configure_system
    install_container_runtime
    install_kubernetes
    initialize_master
    install_network_plugin
    verify_installation
    
    # 打印摘要
    echo -e "\n${GREEN}Kubernetes master 安装成功完成!${NC}"
    echo -e "\n${YELLOW}=========== 节点加入命令 ===========${NC}"
    echo -e "${GREEN}$JOIN_COMMAND${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "\n保存此命令，用于将工作节点添加到集群。"
    echo -e "更多详细信息请查看日志文件: $LOG_FILE\n"
}

# 检查脚本是否以 root 用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}此脚本必须以 root 用户运行${NC}" >&2
    exit 1
fi

# 运行主函数
main 