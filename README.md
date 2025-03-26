# 常用安装脚本集合 (Common Installation Scripts)

这个仓库收集了各种系统、工具和应用的安装脚本，旨在简化部署过程并提供一致的安装体验。

## 目前包含的脚本

### Kubernetes 集群管理脚本 `/k8s/`

提供完整的 Kubernetes 集群生命周期管理：

- **k8s-master-install.sh** - 安装配置 Kubernetes Master 节点
- **k8s-node-join.sh** - 配置并将节点加入到现有集群
- **k8s-reset.sh** - 完全移除 Kubernetes 及相关组件

#### 主要特性

- 自动识别 Linux 发行版（支持 CentOS、RHEL、AlmaLinux 等）
- 智能选择包管理工具（优先使用 dnf，否则使用 yum）
- 使用中国国内镜像源加速下载（阿里云镜像）
- 网络配置：支持自定义 Kubernetes 网络范围
- 多种网络插件选择（Calico、Flannel）
- 安装进度可视化：每个关键步骤都有进度条显示
- 异常处理：提供错误日志和可能的解决方案
- 异常回滚：任何步骤失败时，自动恢复到初始状态
- 详细日志记录：便于问题排查

## 使用方法

请查看各脚本目录下的 README 文件，获取详细的使用说明和配置选项。

## 贡献

欢迎提交 issues 和 pull requests 来改进这些脚本或添加新的安装脚本。

## 许可

本项目采用 MIT 许可证。