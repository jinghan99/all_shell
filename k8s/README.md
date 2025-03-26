# Kubernetes 集群管理脚本

这个仓库包含了三个脚本，用于管理基于 RHEL/CentOS 系列 Linux 发行版的 Kubernetes 集群：

1. `k8s-master-install.sh` - 安装并配置 Kubernetes Master 节点
2. `k8s-node-join.sh` - 配置并将节点加入到 Kubernetes 集群
3. `k8s-reset.sh` - 完全移除 Kubernetes 及相关组件

## 主要特性

- 自动识别 Linux 发行版（CentOS、RHEL、AlmaLinux 等 yum 系列）
- 自动检测包管理工具：默认使用 yum，如果系统支持 dnf，则使用 dnf
- 使用中国国内镜像源加速下载（阿里云镜像）
- 网络配置：支持自定义 Kubernetes 网络范围
- 安装进度可视化：每个关键步骤都有进度条显示
- 异常处理：提供错误日志和可能的解决方案
- 异常回滚：任何步骤失败时，自动恢复到初始状态

## 使用方法

### 安装前准备

确保满足以下条件：

- RHEL/CentOS 7/8 或兼容的发行版
- 至少 2 CPU 核心
- 至少 2GB 内存
- 节点之间网络互通
- 所有脚本必须以 root 用户运行
- 禁用防火墙或确保必要端口开放（参考 Kubernetes 文档）

### 1. 安装 Master 节点

1. 下载脚本：
   ```bash
   curl -O https://raw.githubusercontent.com/your-repo/k8s-scripts/main/k8s-master-install.sh
   chmod +x k8s-master-install.sh
   ```

2. 运行脚本：
   ```bash
   ./k8s-master-install.sh
   ```

3. 根据提示选择配置：
   - Kubernetes 网络 CIDR (默认: 192.168.0.0/16)
   - 网络插件 (Calico 或 Flannel)
   - Kubernetes 版本

4. 等待安装完成。脚本将输出节点加入命令，请保存此命令以供后续添加工作节点。

### 2. 添加工作节点

1. 下载脚本：
   ```bash
   curl -O https://raw.githubusercontent.com/your-repo/k8s-scripts/main/k8s-node-join.sh
   chmod +x k8s-node-join.sh
   ```

2. 运行脚本：
   ```bash
   ./k8s-node-join.sh
   ```

3. 输入从 Master 节点获取的加入命令。
4. 选择 Kubernetes 版本（应与 Master 节点相同）。
5. 等待安装和加入过程完成。

### 3. 重置/卸载 Kubernetes

如果需要重置节点或完全卸载 Kubernetes：

1. 下载脚本：
   ```bash
   curl -O https://raw.githubusercontent.com/your-repo/k8s-scripts/main/k8s-reset.sh
   chmod +x k8s-reset.sh
   ```

2. 运行脚本：
   ```bash
   ./k8s-reset.sh
   ```

3. 确认卸载操作（输入 "yes"）。
4. 等待卸载过程完成。

## 日志文件

每个脚本执行后都会生成日志文件：

- Master 安装: `/tmp/k8s_master_install_<timestamp>.log`
- 节点加入: `/tmp/k8s_node_join_<timestamp>.log`
- 重置卸载: `/tmp/k8s_reset_<timestamp>.log`

## 注意事项

1. 这些脚本仅适用于 RHEL/CentOS 系列发行版。
2. 如果遇到网络问题，请检查防火墙和网络配置。
3. 建议在使用这些脚本前备份重要数据。
4. 重置脚本将完全删除 Kubernetes 相关的所有组件和数据。

## 疑难解答

如果遇到问题，请查看日志文件获取详细信息。常见问题包括：

1. **节点无法加入集群**：检查网络连接和防火墙设置。
2. **Pod 无法调度**：检查网络插件是否正确安装。
3. **安装过程中断**：脚本会自动回滚，可以重新运行脚本。

## 贡献

欢迎提交 issues 和 pull requests 来改进这些脚本。 