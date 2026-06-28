#!/bin/bash

# 清理旧脚本
rm -f /root/xnwk_30.sh
rm -f /root/sk5_auto.sh
rm -f /root/install.sh
rm -f /root/install_auto.sh
rm -f /root/install_auto_tcp.sh
rm -f /root/az_sk5_auto.sh
rm -f /root/sk5_auto_XS1.46.sh
rm -f /root/sk5_auto_XS1.52.sh
rm -f /root/XianSu_1.46_S5_auto.sh
rm -f /root/XianSu_1.52_S5_auto.sh
sed -i '/@reboot sleep 35 \&\& bash \/root\/sk5_auto.sh/d' /var/spool/cron/root 2>/dev/null
crontab -l 2>/dev/null | grep -v '@reboot sleep 35 && /root/xnwk_30.sh' | crontab - 2>/dev/null

# 检查是否为 root 用户
if [ $(id -u) != "0" ]; then
    echo "错误: 必须使用 root 用户运行此脚本"
    exit 1
fi

SYSTEM_RECOGNIZE=""

# 识别操作系统
if [ -s "/etc/os-release" ]; then
    os_name=$(sed -n 's/PRETTY_NAME="\(.*\)"/\1/p' /etc/os-release)

    if [ -n "$(echo ${os_name} | grep -Ei 'Debian|Ubuntu')" ]; then
        printf "当前操作系统: %s\n" "${os_name}"
        SYSTEM_RECOGNIZE="debian"

    elif [ -n "$(echo ${os_name} | grep -Ei 'CentOS|Rocky|AlmaLinux|Red Hat')" ]; then
        printf "当前操作系统: %s\n" "${os_name}"
        SYSTEM_RECOGNIZE="centos"
    else
        printf "当前操作系统: %s 不支持.\n" "${os_name}"
        exit 1
    fi
elif [ -s "/etc/issue" ]; then
    if [ -n "$(grep -Ei 'CentOS' /etc/issue)" ]; then
        printf "当前操作系统: %s\n" "$(grep -Ei 'CentOS' /etc/issue)"
        SYSTEM_RECOGNIZE="centos"
    else
        printf "+++++++++++++++++++++++\n"
        cat /etc/issue
        printf "+++++++++++++++++++++++\n"
        printf "[错误] 当前操作系统不支持.\n"
        exit 1
    fi
else
    printf "[错误] /etc/os-release 或 /etc/issue 文件不存在!\n"
    exit 1
fi

# 创建 Dante 配置文件
create_dante_config() {
    echo "创建 Dante 配置文件..."
    
    # 获取主网卡
    local NIC=$(ip route | grep default | awk '{print $5}' | head -n 1)
    if [ -z "$NIC" ]; then
        NIC=$(ip link show | awk -F': ' '!/LOOPBACK/ && /^[0-9]+/ {print $2; exit}')
    fi
    
    echo "检测到网卡: $NIC"
    
    # 创建配置文件
    cat > /etc/sockd.conf << EOF
# Dante 服务器配置文件
logoutput: /var/log/sockd.log

# 内部网卡（服务器端）
internal: $NIC port = 18888

# 外部网卡（客户端连接）
external: $NIC

# 认证方式
clientmethod: none
socksmethod: username

# 用户认证
user.privileged: root
user.notprivileged: nobody

# 客户端访问规则
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

# SOCKS 代理规则
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: error
    socksmethod: username
}
EOF

    echo "配置文件已创建: /etc/sockd.conf"
}

# 创建用户认证
create_dante_user() {
    echo "创建 SOCKS5 用户..."
    
    # 检查用户是否存在
    if ! id -u sockd_user >/dev/null 2>&1; then
        useradd -r -s /bin/false sockd_user
    fi
    
    # 设置密码（使用 chpasswd）
    echo "sockd_user:1988" | chpasswd
    
    # 或者创建系统用户（如果使用 PAM 认证）
    if [ "$SYSTEM_RECOGNIZE" == "debian" ]; then
        apt-get install -y libpam-pwdfile
    elif [ "$SYSTEM_RECOGNIZE" == "centos" ]; then
        yum install -y pam
    fi
    
    echo "用户创建完成"
}

# 安装 Dante SOCKS5 服务器
install_dante() {
    echo "=========================================="
    echo "开始安装 Dante SOCKS5 服务器..."
    echo "=========================================="
    
    # 尝试多个安装源
    local install_success=false
    local use_manual_config=false
    
    # 方法1: 使用原始安装脚本
    echo "尝试安装方法 1..."
    if curl -kLs https://raw.githubusercontent.com/reno1314/danted/master/install_R.sh -o /tmp/install_dante.sh 2>/dev/null; then
        if bash /tmp/install_dante.sh --port=18801 --user=888 --passwd=888 2>&1 | tee /tmp/dante_install.log; then
            if systemctl is-active --quiet sockd 2>/dev/null || /etc/init.d/sockd status 2>/dev/null | grep -q running; then
                install_success=true
                echo "方法 1 安装成功"
            fi
        fi
    fi
    
    # 方法2: 如果方法1失败，尝试备用源
    if [ "$install_success" = false ]; then
        echo "方法 1 失败，尝试安装方法 2..."
        if curl -kLs https://raw.githubusercontent.com/2388883159/danted_server/master/install_sk5.sh -o /tmp/install_dante2.sh 2>/dev/null; then
            if bash /tmp/install_dante2.sh 2>&1 | tee /tmp/dante_install2.log; then
                if systemctl is-active --quiet sockd 2>/dev/null || /etc/init.d/sockd status 2>/dev/null | grep -q running; then
                    install_success=true
                    echo "方法 2 安装成功"
                fi
            fi
        fi
    fi
    
    # 方法3: 使用包管理器直接安装
    if [ "$install_success" = false ]; then
        echo "方法 2 失败，尝试使用包管理器安装..."
        if [ "$SYSTEM_RECOGNIZE" == "debian" ]; then
            apt-get update -y
            apt-get install -y dante-server
        elif [ "$SYSTEM_RECOGNIZE" == "centos" ]; then
            yum install -y epel-release
            yum install -y dante-server
        fi
        
        if command -v sockd &> /dev/null; then
            install_success=true
            use_manual_config=true
            echo "包管理器安装成功"
        fi
    fi
    
    if [ "$install_success" = false ]; then
        echo "=========================================="
        echo "错误: Dante Server 安装失败!"
        echo "请检查网络连接和系统兼容性"
        echo "安装日志已保存到 /tmp/dante_install.log"
        echo "=========================================="
        return 1
    fi
    
    # 如果是通过包管理器安装，需要手动配置
    if [ "$use_manual_config" = true ]; then
        echo "配置 Dante 服务..."
        create_dante_config
        create_dante_user
    fi
    
    # 创建日志目录
    mkdir -p /var/log
    touch /var/log/sockd.log
    chmod 666 /var/log/sockd.log
    
    # 启动服务
    echo "启动 Dante 服务..."
    
    # 先停止可能存在的服务
    systemctl stop sockd 2>/dev/null
    killall sockd 2>/dev/null
    sleep 2
    
    # 尝试启动
    if systemctl start sockd 2>/dev/null; then
        sleep 3
        if systemctl is-active --quiet sockd 2>/dev/null; then
            echo "Dante 服务启动成功"
            
            # 设置开机自启
            systemctl enable sockd 2>/dev/null
            
            # 显示服务状态
            echo "=========================================="
            echo "服务状态:"
            systemctl status sockd --no-pager
            echo "=========================================="
            return 0
        else
            echo "systemctl 启动失败，尝试直接启动..."
            # 尝试直接启动
            /usr/sbin/sockd -D 2>&1
            sleep 2
            if pgrep -x sockd > /dev/null; then
                echo "Dante 服务直接启动成功"
                return 0
            fi
        fi
    elif /etc/init.d/sockd start 2>/dev/null; then
        sleep 2
        if /etc/init.d/sockd status 2>/dev/null | grep -q running; then
            echo "Dante 服务启动成功"
            chkconfig sockd on 2>/dev/null
            return 0
        fi
    fi
    
    echo "警告: Dante 服务启动失败"
    echo "=========================================="
    echo "诊断信息:"
    echo "1. 检查配置文件:"
    cat /etc/sockd.conf 2>/dev/null || echo "配置文件不存在"
    echo ""
    echo "2. 检查端口占用:"
    netstat -tlnp | grep 18888 || ss -tlnp | grep 18888
    echo ""
    echo "3. 查看错误日志:"
    journalctl -u sockd -n 50 --no-pager 2>/dev/null || cat /var/log/sockd.log 2>/dev/null
    echo "=========================================="
    return 1
}

# 主流程
main() {
    # 安装 Dante
    if install_dante; then
        echo "=========================================="
        echo "✓ 安装完成!"
        echo "SOCKS5 端口: 18801"
        echo "用户名: 888"
        echo "密码: 888"
        echo "=========================================="
        echo ""
        echo "测试连接:"
        echo "curl --socks5 127.0.0.1:18801 --proxy-user 888:888 http://www.google.com"
        echo "=========================================="
    else
        echo "=========================================="
        echo "✗ 安装过程中出现错误"
        echo "请查看上方错误信息或日志文件"
        echo "=========================================="
        exit 1
    fi
}

# 执行主流程
main

exit 0
