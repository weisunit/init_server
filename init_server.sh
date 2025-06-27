#!/bin/bash

# 日志文件路径
LOG_FILE="/var/log/init_server.log"

# 日志函数
log() {
    local level=$1
    shift
    local message=$@
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# 错误处理函数
handle_error() {
    local exit_code=$?
    local error_message=$1
    if [ $exit_code -ne 0 ]; then
        log "ERROR" "$error_message (Exit code: $exit_code)"
        exit $exit_code
    fi
}

# 检测系统类型
get_os_type() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
    elif [ -f /etc/redhat-release ]; then
        OS="CentOS"
    else
        log "ERROR" "Unsupported operating system"
        exit 1
    fi
    log "INFO" "Detected OS: $OS"
}

# 加载配置文件
load_config() {
    if [ -f "./server_config.conf" ]; then
        source ./server_config.conf
        log "INFO" "Configuration loaded successfully"
    else
        log "ERROR" "Configuration file not found"
        exit 1
    fi
}

# 更换镜像源并更新系统
update_system() {
    log "INFO" "Updating system mirrors and packages"
    if [[ "$OS" == *"Ubuntu"* ]]; then
        bash <(curl -sSL https://linuxmirrors.cn/main.sh)
        handle_error "Failed to update mirrors"
        apt update && apt upgrade -y
        handle_error "Failed to update packages"
    elif [[ "$OS" == *"CentOS"* ]]; then
        bash <(curl -sSL https://linuxmirrors.cn/main.sh)
        handle_error "Failed to update mirrors"
        yum update -y
        handle_error "Failed to update packages"
    fi
}

# 安装常用软件包
install_packages() {
    log "INFO" "Installing custom packages: $CUSTOM_PACKAGES"
    if [[ "$OS" == *"Ubuntu"* ]]; then
        apt install -y $CUSTOM_PACKAGES
    elif [[ "$OS" == *"CentOS"* ]]; then
        yum install -y $CUSTOM_PACKAGES
    fi
    handle_error "Failed to install packages"
}

# 配置时区和时间同步
config_timezone() {
    log "INFO" "Configuring timezone and time sync"
    timedatectl set-timezone Asia/Shanghai
    handle_error "Failed to set timezone"

    if [[ "$OS" == *"Ubuntu"* ]]; then
        apt install -y chrony openssh-server
        CHRONY_SERVICE="chrony"
        SSH_SERVICE="ssh"
    elif [[ "$OS" == *"CentOS"* ]]; then
        yum install -y chrony openssh-server
        CHRONY_SERVICE="chronyd"
        SSH_SERVICE="sshd"
    fi
    handle_error "Failed to install required packages"

    # 确保chrony配置目录存在
    if [ ! -d "/etc/chrony" ]; then
        mkdir -p /etc/chrony
    fi

    # 创建chrony配置文件
    if [[ "$OS" == *"Ubuntu"* ]]; then
        CHRONY_CONF="/etc/chrony/chrony.conf"
    else
        CHRONY_CONF="/etc/chrony.conf"
    fi

    # 备份配置文件（如果存在）
    if [ -f "$CHRONY_CONF" ]; then
        cp "$CHRONY_CONF" "${CHRONY_CONF}.bak"
    fi

    # 写入新的NTP配置
    echo "$NTP_SERVERS" > "$CHRONY_CONF"
    handle_error "Failed to configure NTP servers"

    # 启动服务
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable $CHRONY_SERVICE
        systemctl restart $CHRONY_SERVICE
        handle_error "Failed to start chrony service"
    else
        service $CHRONY_SERVICE start
        chkconfig $CHRONY_SERVICE on
        handle_error "Failed to start chrony service"
    fi
}

# 关闭防火墙和SELinux
disable_security() {
    log "INFO" "Disabling firewall and SELinux"
    if [[ "$OS" == *"Ubuntu"* ]]; then
        ufw disable
    elif [[ "$OS" == *"CentOS"* ]]; then
        systemctl disable firewalld
        systemctl stop firewalld
        setenforce 0
        sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
    fi
    handle_error "Failed to disable security features"
}

# 创建用户和配置SSH
config_user_ssh() {
    log "INFO" "Creating user and configuring SSH"
    # 检查用户是否存在
    if ! id "$NEW_USER" >/dev/null 2>&1; then
        useradd -m -s /bin/bash "$NEW_USER"
        handle_error "Failed to create user"
    else
        log "INFO" "User $NEW_USER already exists, skipping user creation"
    fi

    # 配置sudo权限（无需密码）
    if [ -f "/etc/sudoers.d/$NEW_USER" ]; then
        rm -f "/etc/sudoers.d/$NEW_USER"
    fi
    echo "$NEW_USER ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$NEW_USER"
    chmod 440 "/etc/sudoers.d/$NEW_USER"
    handle_error "Failed to configure sudo permission"

    # 确保用户主目录存在
    USER_HOME=$(eval echo ~$NEW_USER)
    if [ ! -d "$USER_HOME" ]; then
        mkdir -p "$USER_HOME"
        chown $NEW_USER:$NEW_USER "$USER_HOME"
    fi

    # 配置SSH密钥
    SSH_DIR="$USER_HOME/.ssh"
    mkdir -p "$SSH_DIR"
    echo "$SSH_PUBLIC_KEY" > "$SSH_DIR/authorized_keys"
    chmod 700 "$SSH_DIR"
    chmod 600 "$SSH_DIR/authorized_keys"
    chown -R $NEW_USER:$NEW_USER "$SSH_DIR"
    handle_error "Failed to configure SSH key"

    # 修改SSH配置
    if [ -f "/etc/ssh/sshd_config" ]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
        # 更新SSH配置
        sed -i 's/^#\?Port .*/Port 2222/' /etc/ssh/sshd_config
        sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
        sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
        
        # 重启SSH服务
        if command -v systemctl >/dev/null 2>&1; then
            systemctl enable $SSH_SERVICE
            systemctl restart $SSH_SERVICE
        else
            service $SSH_SERVICE restart
            chkconfig $SSH_SERVICE on
        fi
        handle_error "Failed to configure SSH"
    else
        log "ERROR" "SSH configuration file not found"
        exit 1
    fi
}

# 修改主机名
change_hostname() {
    log "INFO" "Changing hostname"
    hostnamectl set-hostname "$NEW_HOSTNAME"
    handle_error "Failed to change hostname"
}

# 安装Docker
install_docker() {
    if [ "$INSTALL_DOCKER" = "true" ]; then
        log "INFO" "Installing Docker"
        bash <(curl -sSL https://linuxmirrors.cn/docker.sh)
        handle_error "Failed to install Docker"
    fi
}

# 显示任务完成状态
show_completion_status() {
    echo ""
    echo "========================================"
    echo "         服务器初始化完成报告"
    echo "========================================"
    echo "✓ 系统类型检测: $OS"
    echo "✓ 配置文件加载: 成功"
    echo "✓ 镜像源更新: 完成"
    echo "✓ 系统软件包更新: 完成"
    echo "✓ 常用软件安装: $CUSTOM_PACKAGES"
    echo "✓ 时区配置: Asia/Shanghai"
    echo "✓ NTP时间同步: 已启用"
    echo "✓ 防火墙: 已关闭"
    if [[ "$OS" == *"CentOS"* ]]; then
        echo "✓ SELinux: 已禁用"
    fi
    echo "✓ 用户创建: $NEW_USER"
    echo "✓ Sudo权限: 已配置（无需密码，可直接执行sudo su root）"
    echo "✓ SSH密钥认证: 已配置"
    echo "✓ SSH安全加固: 端口2222, 禁用root登录, 禁用密码登录"
    echo "✓ 主机名: $NEW_HOSTNAME"
    if [ "$INSTALL_DOCKER" = "true" ]; then
        echo "✓ Docker: 已安装"
    else
        echo "- Docker: 跳过安装"
    fi
    echo "========================================"
    echo "初始化任务全部完成！"
    echo ""
    echo "重要提醒:"
    echo "1. SSH端口已更改为2222"
    echo "2. 请使用新用户 '$NEW_USER' 和SSH密钥登录"
    echo "3. Root用户SSH登录已禁用"
    echo "4. 密码登录已禁用"
    echo "5. 可使用 'sudo' 命令执行管理任务，无需输入密码"
    echo "6. 可直接使用 'sudo su root' 切换到root环境"
    echo "========================================"
}

# 交互式确认函数
confirm_action() {
    local message=$1
    echo -n "$message (y/N): "
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 主函数
main() {
    echo "========================================"
    echo "         服务器初始化脚本"
    echo "========================================"
    echo "此脚本将执行以下操作:"
    echo "1. 更换镜像源并更新系统"
    echo "2. 安装常用软件包"
    echo "3. 配置时区和时间同步"
    echo "4. 关闭防火墙和SELinux"
    echo "5. 创建用户和配置SSH"
    echo "6. 修改主机名"
    echo "7. 可选安装Docker"
    echo "========================================"
    echo ""
    
    if ! confirm_action "是否继续执行初始化"; then
        echo "初始化已取消"
        exit 0
    fi
    
    log "INFO" "Starting server initialization"
    get_os_type
    load_config
    
    echo "正在更新系统..."
    update_system
    
    echo "正在安装软件包..."
    install_packages
    
    echo "正在配置时区和时间同步..."
    config_timezone
    
    echo "正在关闭防火墙和SELinux..."
    disable_security
    
    echo "正在配置用户和SSH..."
    config_user_ssh
    
    echo "正在修改主机名..."
    change_hostname
    
    if [ "$INSTALL_DOCKER" = "true" ]; then
        echo "正在安装Docker..."
        install_docker
    fi
    
    log "INFO" "Server initialization completed successfully"
    show_completion_status
}

main