#!/bin/bash

# 文本颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 横幅
echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║             Kubernetes 集群彻底重置工具                    ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# 确认重置
echo -e "${RED}警告: 此操作将完全删除 Kubernetes 集群及其所有数据!${NC}"
echo -e "${YELLOW}确定要继续吗? (输入 'yes' 确认)${NC}"
read -r confirm
if [[ "$confirm" != "yes" ]]; then
    echo -e "${GREEN}操作已取消${NC}"
    exit 0
fi

echo -e "${BLUE}开始彻底重置 Kubernetes 集群...${NC}"

# 1. 强制重置 kubeadm (即使之前没有初始化)
echo -e "${YELLOW}执行 kubeadm reset...${NC}"
kubeadm reset -f || true

# 2. 停止所有相关服务
echo -e "${YELLOW}停止所有相关服务...${NC}"
systemctl daemon-reload
systemctl stop kubelet || true
systemctl stop containerd || true
systemctl disable kubelet || true
systemctl disable containerd || true

# 3. 杀死所有 Kubernetes 相关进程
echo -e "${YELLOW}终止所有 Kubernetes 相关进程...${NC}"
for pid in $(ps -ef | grep -E 'kube|containerd|etcd' | grep -v grep | awk '{print $2}'); do
    kill -9 $pid 2>/dev/null || true
done

# 4. 清理网络配置
echo -e "${YELLOW}清理网络配置...${NC}"
iptables -F || true
iptables -t nat -F || true
iptables -t mangle -F || true
iptables -X || true
ip link delete cni0 2>/dev/null || true
ip link delete flannel.1 2>/dev/null || true
ip link delete calico 2>/dev/null || true
ip link delete tunl0 2>/dev/null || true
ip link delete vxlan.calico 2>/dev/null || true

# 5. 删除所有 Kubernetes 相关目录
echo -e "${YELLOW}删除 Kubernetes 相关目录...${NC}"
rm -rf /etc/kubernetes/
rm -rf /var/lib/kubelet/
rm -rf /var/lib/etcd/
rm -rf /var/lib/cni/
rm -rf /etc/cni/
rm -rf $HOME/.kube/
rm -rf /var/run/kubernetes/
rm -rf /var/lib/calico/
rm -rf /var/lib/weave/
rm -rf /var/lib/flannel/
rm -rf /run/flannel/
rm -rf /etc/containerd/
rm -rf /var/run/containerd/
rm -f /etc/sysctl.d/k8s.conf
rm -f /etc/modules-load.d/k8s.conf

# 6. 清理容器运行时
echo -e "${YELLOW}清理容器运行时...${NC}"
crictl rm --all 2>/dev/null || true
crictl rmi --all 2>/dev/null || true

# 7. 卸载 Kubernetes 和容器运行时包
echo -e "${YELLOW}卸载 Kubernetes 和容器运行时包...${NC}"
if command -v dnf &> /dev/null; then
    dnf remove -y kubelet kubeadm kubectl containerd.io 2>/dev/null || true
elif command -v yum &> /dev/null; then
    yum remove -y kubelet kubeadm kubectl containerd.io 2>/dev/null || true
fi

# 8. 删除仓库文件
echo -e "${YELLOW}删除仓库文件...${NC}"
rm -f /etc/yum.repos.d/kubernetes.repo
rm -f /etc/yum.repos.d/docker-ce.repo

# 9. 恢复 SELinux 和 swap 设置
echo -e "${YELLOW}恢复系统设置...${NC}"
# 恢复 SELinux 设置
if [ -f /etc/selinux/config.backup ]; then
    cp /etc/selinux/config.backup /etc/selinux/config
else
    # 如果没有备份，设置为默认值
    sed -i 's/^SELINUX=permissive$/SELINUX=enforcing/' /etc/selinux/config 2>/dev/null || true
fi

# 恢复 swap 设置
if [ -f /etc/fstab.backup ]; then
    cp /etc/fstab.backup /etc/fstab
else
    # 取消注释 swap 行
    sed -i '/swap/s/^#//' /etc/fstab 2>/dev/null || true
fi

# 10. 清理 Docker 相关内容（如果有）
echo -e "${YELLOW}清理 Docker 相关内容...${NC}"
systemctl stop docker 2>/dev/null || true
systemctl disable docker 2>/dev/null || true
if command -v dnf &> /dev/null; then
    dnf remove -y docker-ce docker-ce-cli 2>/dev/null || true
elif command -v yum &> /dev/null; then
    yum remove -y docker-ce docker-ce-cli 2>/dev/null || true
fi
rm -rf /var/lib/docker/ 2>/dev/null || true

# 11. 清理临时文件和日志
echo -e "${YELLOW}清理临时文件和日志...${NC}"
rm -f /tmp/kubeadm-config.yaml 2>/dev/null || true
rm -f /tmp/k8s_*.log 2>/dev/null || true

# 12. 验证清理结果
echo -e "${YELLOW}验证清理结果...${NC}"
KUBE_PROCESSES=$(ps -ef | grep -E 'kube|containerd|etcd' | grep -v grep | wc -l)
if [ "$KUBE_PROCESSES" -gt 0 ]; then
    echo -e "${YELLOW}警告: 仍有 $KUBE_PROCESSES 个 Kubernetes 相关进程在运行${NC}"
    ps -ef | grep -E 'kube|containerd|etcd' | grep -v grep
else
    echo -e "${GREEN}✓ 所有 Kubernetes 进程已终止${NC}"
fi

# 13. 重启系统
echo -e "${GREEN}Kubernetes 集群彻底重置完成!${NC}"
echo -e "${YELLOW}建议重启系统后再重新安装 Kubernetes。${NC}"
echo -e "${YELLOW}是否现在重启系统? (y/n)${NC}"
read -r restart_choice
if [[ "$restart_choice" == "y" || "$restart_choice" == "Y" ]]; then
    echo -e "${YELLOW}系统将在 5 秒后重启...${NC}"
    sleep 5
    reboot
else
    echo -e "${YELLOW}请在方便时手动重启系统，然后再重新安装 Kubernetes。${NC}"
    echo -e "${GREEN}重置完成。您可以使用以下命令重新安装 Kubernetes:${NC}"
    echo -e "${BLUE}    ./k8s/k8s-master-install.sh${NC}"
fi 