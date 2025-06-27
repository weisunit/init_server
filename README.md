# 服务器初始化脚本

这是一个用于CentOS和Ubuntu服务器初始化的Shell脚本，可以自动完成系统配置、软件安装、安全加固等任务。
脚本集成了LinuxMirrors https://github.com/SuperManito/LinuxMirrors，特此鸣谢！

## 功能特点

- 自动检测并更换国内镜像源
- 更新系统软件包
- 安装自定义软件包（可在配置文件中自定义）
- 配置时区为Asia/Shanghai并启用NTP时间同步
- 关闭防火墙和SELinux
- 创建新用户并配置SSH密钥认证
- 配置新用户的sudo权限
- SSH安全加固（禁用root登录、禁用密码登录、更改默认端口）
- 修改主机名
- 可选安装Docker
- 完整的日志记录和错误处理

## 使用方法

1. 修改配置文件

在运行脚本前，请先修改 `server_config.conf` 文件中的配置项：

```bash
# 设置新用户名
NEW_USER="your_username"

# 设置SSH公钥
SSH_PUBLIC_KEY="your_public_key"

# 设置主机名
NEW_HOSTNAME="your_hostname"

# 配置NTP服务器（可选）
NTP_SERVERS="your_ntp_servers"

# 自定义软件包列表（空格分隔）
CUSTOM_PACKAGES="vim curl wget lrzsz net-tools"

# 是否安装Docker
INSTALL_DOCKER="true"
```

2. 运行脚本

```bash
chmod +x init_server.sh
./init_server.sh
```

## 日志查看

脚本执行过程中的所有操作都会记录在 `/var/log/init_server.log` 文件中，可以通过以下命令查看：

```bash
cat /var/log/init_server.log
```

## 注意事项

1. 脚本需要root权限运行
2. 执行前请确保已正确配置SSH公钥
3. 更改SSH端口后，后续连接需要指定端口2222
4. 脚本执行后将禁用密码登录，请确保SSH密钥配置正确
5. 新建用户将被授予无密码sudo权限，可以通过`sudo`命令执行管理任务，包括`sudo su root`切换到root环境，无需输入密码

## 兼容性

- 支持CentOS 7/8/9
- 支持Ubuntu 18.04/20.04/22.04

## 错误处理

如果脚本执行过程中出现错误：

1. 检查 `/var/log/init_server.log` 中的错误信息
2. 确保服务器能够访问外网
3. 验证配置文件中的参数是否正确

## 安全提示

1. 脚本执行后会禁用root用户SSH登录
2. 禁用密码认证，仅允许密钥认证
3. SSH默认端口会更改为2222
4. 请妥善保管SSH私钥
