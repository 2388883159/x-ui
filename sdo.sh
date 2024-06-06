#!/bin/bash

IP_ADDRESSES=($(hostname -I))

uninstall_xray() {
    echo "卸载 Xray..."

    # 停止并禁用所有 Xray 服务
    for ip in "${IP_ADDRESSES[@]}"; do
        systemctl stop xrayL_${ip}.service
        systemctl disable xrayL_${ip}.service
        rm /etc/systemd/system/xrayL_${ip}.service
    done

    # 重新加载 systemd 配置
    systemctl daemon-reload

    # 删除 Xray 可执行文件和配置目录
    rm -rf /usr/local/bin/xrayL
    rm -rf /etc/xrayL

    echo "Xray 已卸载."
}

uninstall_xray
