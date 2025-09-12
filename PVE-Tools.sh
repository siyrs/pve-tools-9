#!/bin/bash

# PVE 9.0 配置工具脚本
# 支持换源、删除订阅弹窗、硬盘管理等功能
# 适用于 Proxmox VE 9.0 (基于 Debian 13)
# Auther:siyrs 二次修改使用请不要删除此段注释

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]${NC} $1" | tee -a /var/log/pve-tools.log
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] [WARN]${NC} $1" | tee -a /var/log/pve-tools.log
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $1" | tee -a /var/log/pve-tools.log >&2
}

log_step() {
    echo -e "${CYAN}[$(date +'%Y-%m-%d %H:%M:%S')] [STEP]${NC} $1" | tee -a /var/log/pve-tools.log
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS]${NC} $1" | tee -a /var/log/pve-tools.log
}

log_tips(){
    echo -e "${MAGENTA}[$(date +'%Y-%m-%d %H:%M:%S')] [TIPS]${NC} $1" | tee -a /var/log/pve-tools.log
}

# 进度指示函数
show_progress() {
    local message="$1"
    echo -ne "${CYAN}[....]${NC} $message\033[0K\r"
}

update_progress() {
    local message="$1"
    echo -ne "${GREEN}[ OK ]${NC} $message\033[0K\r"
    echo
}

# 显示横幅
show_banner() {
    clear
    echo -e "${BLUE}"
    cat << 'EOF'
██████╗ ██╗   ██╗███████╗    ████████╗ ██████╗  ██████╗ ██╗     ███████╗     █████╗
██╔══██╗██║   ██║██╔════╝    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██╔════╝    ██╔══██╗
██████╔╝██║   ██║█████╗         ██║   ██║   ██║██║   ██║██║     ███████╗    ╚██████║
██╔═══╝ ╚██╗ ██╔╝██╔══╝         ██║   ██║   ██║██║   ██║██║     ╚════██║     ╚═══██║
██║      ╚████╔╝ ███████╗       ██║   ╚██████╔╝╚██████╔╝███████╗███████║     █████╔╝
╚═╝       ╚═══╝  ╚══════╝       ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚══════╝     ╚════╝
EOF
    echo -e "${NC}"
    echo -e "${YELLOW}                    PVE 9.0 一键配置神器${NC}"
    echo -e "${GREEN}                      让 PVE 配置变得简单快乐${NC}"
    echo -e "${CYAN}                        作者: siyrs${NC}"
    echo
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "哎呀！需要超级管理员权限才能运行哦"
        echo -e "${YELLOW}请使用以下命令重新运行：${NC}"
        echo -e "${CYAN}sudo $0${NC}"
        exit 1
    fi
}

# 检查调试模式
check_debug_mode() {
    for arg in "$@"; do
        if [[ "$arg" == "--debug" ]]; then
            log_warn "警告：您正在使用调试模式！"
            log_warn "此模式将跳过 PVE 系统版本检测"
            log_warn "仅在开发和测试环境中使用"
            log_warn "在非 PVE (Debian 系) 系统上使用可能导致系统损坏"
            echo -e "${YELLOW}您确定要继续吗？输入 'yes' 确认，其他任意键退出: ${NC}"
            read -r confirm
            if [[ "$confirm" != "yes" ]]; then
                log_info "已取消操作，退出脚本"
                exit 0
            fi
            DEBUG_MODE=true
            log_success "已启用调试模式"
            return
        fi
    done
    DEBUG_MODE=false
}

# 检查是否安装依赖软件包
check_packages() {
    # 程序依赖的软件包: `sudo` `curl`
    local packages=("sudo" "curl")
    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            log_error "哎呀！需要安装 $pkg 软件包才能运行哦"
            log_tips "请使用以下命令安装：apt install -y $pkg"
            exit 1
        fi
    done
 }




# 检查 PVE 版本
check_pve_version() {
    # 如果在调试模式下，跳过 PVE 版本检测
    if [[ "$DEBUG_MODE" == "true" ]]; then
        log_warn "调试模式：跳过 PVE 版本检测"
        log_tips "请注意：您正在非 PVE 系统上运行此脚本，某些功能可能无法正常工作"
        return
    fi

    if ! command -v pveversion &> /dev/null; then
        log_error "咦？这里好像不是 PVE 环境呢"
        log_warn "请在 Proxmox VE 系统上运行此脚本"
        exit 1
    fi

    local pve_version=$(pveversion | head -n1 | cut -d'/' -f2 | cut -d'-' -f1)
    log_info "太好了！检测到 PVE 版本: ${GREEN}$pve_version${NC}"
}

# 备份文件
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp "$file" "${file}.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "贴心备份完成: ${CYAN}$file${NC}"
    fi
}

# 换源功能
change_sources() {
    log_step "开始为您的 PVE 换上飞速源"

    # 1. 更换 Debian 软件源 (DEB822 格式)
    log_info "正在配置 Debian 清华源..."
    backup_file "/etc/apt/sources.list.d/debian.sources"

    cat > /etc/apt/sources.list.d/debian.sources << 'EOF'
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/debian
Suites: trixie trixie-updates trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
# Types: deb-src
# URIs: https://mirrors.tuna.tsinghua.edu.cn/debian
# Suites: trixie trixie-updates trixie-backports
# Components: main contrib non-free non-free-firmware
# Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# 以下安全更新软件源包含了官方源与镜像站配置，如有需要可自行修改注释切换
Types: deb
URIs: https://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# Types: deb-src
# URIs: https://security.debian.org/debian-security
# Suites: trixie-security
# Components: main contrib non-free non-free-firmware
# Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

    # 2. 注释企业源
    log_info "正在关闭企业源（我们用免费版就够啦）..."
    if [[ -f "/etc/apt/sources.list.d/pve-enterprise.sources" ]]; then
        backup_file "/etc/apt/sources.list.d/pve-enterprise.sources"
        sed -i 's/^Types:/#Types:/g' /etc/apt/sources.list.d/pve-enterprise.sources
        sed -i 's/^URIs:/#URIs:/g' /etc/apt/sources.list.d/pve-enterprise.sources
        sed -i 's/^Suites:/#Suites:/g' /etc/apt/sources.list.d/pve-enterprise.sources
        sed -i 's/^Components:/#Components:/g' /etc/apt/sources.list.d/pve-enterprise.sources
        sed -i 's/^Signed-By:/#Signed-By:/g' /etc/apt/sources.list.d/pve-enterprise.sources
    fi

    # 3. 更换 Ceph 源
    log_info "正在配置 Ceph 清华源..."
    if [[ -f "/etc/apt/sources.list.d/ceph.sources" ]]; then
        backup_file "/etc/apt/sources.list.d/ceph.sources"
        cat > /etc/apt/sources.list.d/ceph.sources << 'EOF'
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/ceph-squid
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    fi

    # 4. 添加无订阅源
    log_info "正在添加免费版专用源..."
    cat > /etc/apt/sources.list.d/pve-no-subscription.sources << 'EOF'
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

    # 5. 更换 CT 模板源
    log_info "正在加速 CT 模板下载..."
    if [[ -f "/usr/share/perl5/PVE/APLInfo.pm" ]]; then
        backup_file "/usr/share/perl5/PVE/APLInfo.pm"
        sed -i 's|http://download.proxmox.com|https://mirrors.tuna.tsinghua.edu.cn/proxmox|g' /usr/share/perl5/PVE/APLInfo.pm
    fi

    log_success "太棒了！所有源都换成飞速版本啦"
}

# 删除订阅弹窗
remove_subscription_popup() {
    log_step "正在消除那个烦人的订阅弹窗"

    local js_file="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    if [[ -f "$js_file" ]]; then
        backup_file "$js_file"
        sed -Ezi.bak "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" "$js_file"
        systemctl restart pveproxy.service
        log_success "完美！再也不会有烦人的弹窗啦"
    else
        log_warn "咦？没找到弹窗文件，可能已经被处理过了"
    fi
}

# 合并 local 与 local-lvm
merge_local_storage() {
    log_step "准备合并存储空间，让小硬盘发挥最大价值"
    log_warn "重要提醒：此操作会删除 local-lvm，请确保重要数据已备份！"

    echo -e "${YELLOW}您确定要继续吗？这个操作不可逆哦${NC}"
    read -p "输入 'yes' 确认继续，其他任意键取消: " -r
    if [[ ! $REPLY == "yes" ]]; then
        log_info "明智的选择！操作已取消"
        return
    fi

    # 检查 local-lvm 是否存在
    if ! lvdisplay /dev/pve/data &> /dev/null; then
        log_warn "没有找到 local-lvm 分区，可能已经合并过了"
        return
    fi

    log_info "正在删除 local-lvm 分区..."
    lvremove -f /dev/pve/data

    log_info "正在扩容 local 分区..."
    lvextend -l +100%FREE /dev/pve/root

    log_info "正在扩展文件系统..."
    resize2fs /dev/pve/root

    log_success "存储合并完成！现在空间更充裕了"
    log_warn "温馨提示：请在 Web UI 中删除 local-lvm 存储配置，并编辑 local 存储勾选所有内容类型"
}

# 删除 Swap 分配给主分区
remove_swap() {
    log_step "准备释放 Swap 空间给系统使用"
    log_warn "注意：删除 Swap 后请确保内存充足！"

    echo -e "${YELLOW}您确定要删除 Swap 分区吗？${NC}"
    read -p "输入 'yes' 确认继续，其他任意键取消: " -r
    if [[ ! $REPLY == "yes" ]]; then
        log_info "好的，操作已取消"
        return
    fi

    # 检查 swap 是否存在
    if ! lvdisplay /dev/pve/swap &> /dev/null; then
        log_warn "没有找到 swap 分区，可能已经删除过了"
        return
    fi

    log_info "正在关闭 Swap..."
    swapoff /dev/mapper/pve-swap

    log_info "正在修改启动配置..."
    backup_file "/etc/fstab"
    sed -i 's|^/dev/pve/swap|# /dev/pve/swap|g' /etc/fstab

    log_info "正在删除 swap 分区..."
    lvremove -f /dev/pve/swap

    log_info "正在扩展系统分区..."
    lvextend -l +100%FREE /dev/mapper/pve-root

    log_info "正在扩展文件系统..."
    resize2fs /dev/mapper/pve-root

    log_success "Swap 删除完成！系统空间更宽裕了"
}

# 更新系统
update_system() {
    log_step "开始更新系统，让 PVE 保持最新状态"

    echo -e "${CYAN}正在更新软件包列表...${NC}"
    apt update

    echo -e "${CYAN}正在升级系统软件包...${NC}"
    apt upgrade -y

    echo -e "${CYAN}正在清理不需要的软件包...${NC}"
    apt autoremove -y

    log_success "系统更新完成！您的 PVE 现在是最新版本"
}

# 暂停函数
pause() {
    read -n 1 -p "按任意键继续... " input
    if [[ -n ${input} ]]; then
        echo -e "\b
"
    fi
}

#--------------开启硬件直通----------------
# 开启硬件直通
enable_pass() {
    echo
    log_step "开启硬件直通..."
    if [ `dmesg | grep -e DMAR -e IOMMU|wc -l` = 0 ];then
        log_error "您的硬件不支持直通！不如检查一下主板的BIOS设置？"
        pause
        return
    fi
    if [ `cat /proc/cpuinfo|grep Intel|wc -l` = 0 ];then
        iommu="amd_iommu=on"
    else
        iommu="intel_iommu=on"
    fi
    if [ `grep $iommu /etc/default/grub|wc -l` = 0 ];then
        backup_file "/etc/default/grub"
        sed -i 's|quiet|quiet '$iommu'|' /etc/default/grub
        update-grub
        if [ `grep "vfio" /etc/modules|wc -l` = 0 ];then
            cat <<-EOF >> /etc/modules
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
kvmgt
EOF
        fi

        if [ ! -f "/etc/modprobe.d/blacklist.conf" ];then
            echo "blacklist snd_hda_intel" >> /etc/modprobe.d/blacklist.conf
            echo "blacklist snd_hda_codec_hdmi" >> /etc/modprobe.d/blacklist.conf
            echo "blacklist i915" >> /etc/modprobe.d/blacklist.conf
        fi

        if [ ! -f "/etc/modprobe.d/vfio.conf" ];then
            echo "options vfio-pci ids=8086:3185" >> /etc/modprobe.d/vfio.conf
        fi

        log_success "开启设置后需要重启系统，请准备就绪后重启宿主机"
        log_tips "重启后才可以应用对内核引导的修改哦！命令是 reboot"
    else
        log_warn "您已经配置过!"
    fi
}

# 关闭硬件直通
disable_pass() {
    echo
    log_step "关闭硬件直通..."
    if [ `dmesg | grep -e DMAR -e IOMMU|wc -l` = 0 ];then
        log_error "您的硬件不支持直通！"
        log_tips "不如检查一下主板的BIOS设置？"
        pause
        return
    fi
    if [ `cat /proc/cpuinfo|grep Intel|wc -l` = 0 ];then
        iommu="amd_iommu=on"
    else
        iommu="intel_iommu=on"
    fi
    if [ `grep $iommu /etc/default/grub|wc -l` = 0 ];then
        log_warn "您还没有配置过该项"
    else
        backup_file "/etc/default/grub"
        {
            sed -i 's/ '$iommu'//g' /etc/default/grub
            sed -i '/vfio/d' /etc/modules
            rm -rf /etc/modprobe.d/blacklist.conf
            rm -rf /etc/modprobe.d/vfio.conf
            sleep 1
        }
        log_success "关闭设置后需要重启系统，请准备就绪后重启宿主机。"
        log_tips "重启后才可以应用对内核引导的修改哦！命令是 reboot"
        sleep 1
        update-grub
    fi
}

# 硬件直通菜单
hw_passth() {
    while :; do
        clear
        show_banner
        cat<<-EOF
${YELLOW}              配置硬件直通${NC}
┌──────────────────────────────────────────┐
    1. 开启硬件直通
    2. 关闭硬件直通
├──────────────────────────────────────────┤
    0. 返回
└──────────────────────────────────────────┘
EOF
        echo -ne " 请选择: [ ]\b\b"
        read -t 60 hwmenuid
        hwmenuid=${hwmenuid:-0}
        case "${hwmenuid}" in
            1)
                enable_pass
                pause
                ;;
            2)
                disable_pass
                pause
                ;;
            0)
                break
                ;;
            *)
                log_error "无效选项!"
                pause
                ;;
        esac
    done
}
#--------------开启硬件直通----------------

#--------------设置CPU电源模式----------------
# 设置CPU电源模式
cpupower() {
    governors=`cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors`
    while :; do
        clear
        show_banner
        cat <<-EOF
--------------------------------------------
             设置CPU电源模式
┌──────────────────────────────────────────┐

    1. 设置CPU模式 conservative  保守模式   [变身老年机]
    2. 设置CPU模式 ondemand       按需模式  [默认]
    3. 设置CPU模式 powersave      节能模式  [省电小能手]
    4. 设置CPU模式 performance   性能模式   [性能释放]
    5. 设置CPU模式 schedutil      负载模式  [交给负载自动配置]

    6. 恢复系统默认电源设置

├──────────────────────────────────────────┤
    0. 返回
└──────────────────────────────────────────┘
EOF
        echo
        echo "部分CPU仅支持 performance 和 powersave 模式，只能选择这两项，其他模式无效不要选！"
        echo
        echo "你的CPU支持 ${governors} 模式"
        echo
        echo -ne " 请选择: [ ]\b\b"
        read -t 60 cpupowerid
        cpupowerid=${cpupowerid:-2}
        case "${cpupowerid}" in
            1)
                GOVERNOR="conservative"
                ;;
            2)
                GOVERNOR="ondemand"
                ;;
            3)
                GOVERNOR="powersave"
                ;;
            4)
                GOVERNOR="performance"
                ;;
            5)
                GOVERNOR="schedutil"
                ;;
            6)
                cpupower_del
                pause
                break
                ;;
            0)
                break
                ;;
            *)
                log_error "你的输入无效 ,请重新输入 ! 你在干什么？"
                pause
                ;;
        esac
        if [[ ${GOVERNOR} != "" ]]; then
            if [[ -n `echo "${governors}" | grep -o "${GOVERNOR}"` ]]; then
                echo "您选择的CPU模式：${GOVERNOR}"
                echo
                cpupower_add
                pause
            else
                log_error "您的CPU不支持该模式！"
                log_tips "现在暂时不会对你的系统造成影响，但是下次开机时，CPU模式会恢复为默认模式。"
                pause
            fi
        fi
    done
}

# 修改CPU模式
cpupower_add() {
    echo "${GOVERNOR}" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
    echo "查看当前CPU模式"
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

    echo "正在添加开机任务"
    NEW_CRONTAB_COMMAND="sleep 10 && echo "${GOVERNOR}" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null #CPU Power Mode"
    EXISTING_CRONTAB=$(crontab -l 2>/dev/null)
    if [[ -n "$EXISTING_CRONTAB" ]]; then
        TEMP_CRONTAB_FILE=$(mktemp)
        echo "$EXISTING_CRONTAB" | grep -v "@reboot sleep 10 && echo*" > "$TEMP_CRONTAB_FILE"
        crontab "$TEMP_CRONTAB_FILE"
        rm "$TEMP_CRONTAB_FILE"
    fi
    log_success "CPU模式已修改完成"
    # 修改完成
    (crontab -l 2>/dev/null; echo "@reboot $NEW_CRONTAB_COMMAND") | crontab -
    echo -e "
检查计划任务设置 (使用 'crontab -l' 命令来检查)"
}

# 恢复系统默认电源设置
cpupower_del() {
    # 恢复性模式
    echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
    # 删除计划任务
    EXISTING_CRONTAB=$(crontab -l 2>/dev/null)
    if [[ -n "$EXISTING_CRONTAB" ]]; then
        TEMP_CRONTAB_FILE=$(mktemp)
        echo "$EXISTING_CRONTAB" | grep -v "@reboot sleep 10 && echo*" > "$TEMP_CRONTAB_FILE"
        crontab "$TEMP_CRONTAB_FILE"
        rm "$TEMP_CRONTAB_FILE"
    fi

    log_success "已恢复系统默认电源设置！还是默认的好用吧"
}
#--------------设置CPU电源模式----------------

#--------------CPU、主板、硬盘温度显示----------------
# 安装工具
cpu_add() {
    nodes="/usr/share/perl5/PVE/API2/Nodes.pm"
    pvemanagerlib="/usr/share/pve-manager/js/pvemanagerlib.js"
    proxmoxlib="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"

    pvever=$(pveversion | awk -F"/" '{print $2}')
    echo pve版本$pvever

    # 判断是否已经执行过修改
    [ ! -e $nodes.$pvever.bak ] || { log_warn "已经执行过修改，请勿重复执行"; pause; return;}

    # 先刷新下源
    log_step "更新软件包列表..."
    apt-get update

    log_step "开始安装所需工具..."
    # 输入需要安装的软件包
    packages=(lm-sensors nvme-cli sysstat linux-cpupower apcupsd)

    # 查询软件包，判断是否安装
    for package in "${packages[@]}"; do
        if ! dpkg -s "$package" &> /dev/null; then
            echo "$package 未安装，开始安装软件包"
            apt-get install "${packages[@]}" -y
            modprobe msr
            install=ok
            break
        fi
    done

    # 设置执行权限
    if dpkg -s "linux-cpupower" &> /dev/null; then
        chmod +s /usr/sbin/linux-cpupower || echo "Failed to set permissions for /usr/sbin/linux-cpupower"
    fi

    chmod +s /usr/sbin/nvme
    chmod +s /usr/sbin/hddtemp
    chmod +s /usr/sbin/smartctl
    chmod +s /usr/sbin/turbostat || echo "Failed to set permissions for /usr/sbin/turbostat"
    modprobe msr && echo msr > /etc/modules-load.d/turbostat-msr.conf

    # 软件包安装完成
    if [ "$install" == "ok" ]; then
        log_info "软件包安装完成，检测硬件信息"
        sensors-detect --auto > /tmp/sensors
        drivers=`sed -n '/Chip drivers/,/\\#----cut here/p' /tmp/sensors|sed '/Chip /d'|sed '/cut/d'`
        if [ `echo $drivers|wc -w` = 0 ];then
            log_error "没有找到任何驱动，似乎你的系统不支持或驱动安装失败。"
            log_tips "请检查你的硬件是否支持，或者尝试手动安装驱动。"
            log_tips "手动安装驱动方法：去制造商官网找驱动，然后手动安装。不会装驱动建议去问问AI"
            log_tips "猜你再找: https://claude.ai"
            pause
            return
        else
            for i in $drivers
            do
                modprobe $i
                if [ `grep $i /etc/modules|wc -l` = 0 ];then
                    echo $i >> /etc/modules
                fi
            done
            sensors
            sleep 3
            log_success "驱动信息配置成功。"
        fi
        /etc/init.d/kmod start
        rm /tmp/sensors

        # 启动APC UPS
        systemctl enable apcupsd
        systemctl start apcupsd

        # 驱动信息配置完成
    fi

    log_step "备份源文件"
    # 删除旧版本备份文件
    rm -f  $nodes.*.bak
    rm -f  $pvemanagerlib.*.bak
    rm -f  $proxmoxlib.*.bak
    # 备份当前版本文件
    [ ! -e $nodes.$pvever.bak ] && cp $nodes $nodes.$pvever.bak
    [ ! -e $pvemanagerlib.$pvever.bak ] && cp $pvemanagerlib $pvemanagerlib.$pvever.bak
    [ ! -e $proxmoxlib.$pvever.bak ] && cp $proxmoxlib $proxmoxlib.$pvever.bak

    # 生成系统变量
    tmpf=tmpfile.temp
    touch $tmpf
    cat > $tmpf << 'EOF'
    $res->{thermalstate} = `sensors`;
    $res->{cpusensors} = `cat /proc/cpuinfo | grep MHz && lscpu | grep MHz`;

    # ---------- begin nvme 多盘安全采集 ----------
    my $nvme_status = "";

    # 列出所有 nvme 设备
    my @nvmes = glob("/dev/nvme[0-9]n1");

    foreach my $dev (@nvmes) {
        # 安全检查，只允许 /dev/nvmeXn1
        if ($dev =~ m{^(/dev/nvme\d+n1)$}) {
            $dev = $1;  # 解除 taint

            # SMART 信息
            my $nvme_info = qx(smartctl -a $dev);
            $nvme_info =~ s/\r//g; # 去掉 CR
            $nvme_info = join("\n", grep {
                /Model Number|Capacity|Temperature:|Available Spare|Percentage Used|Data Units Read|Data Units Written|Power Cycles|Power On Hours|Unsafe Shutdowns|Integrity Errors/
            } split(/\n/, $nvme_info));

            # IO 信息（单个设备）
            my $nvme_io = qx(iostat -d -x -k 1 1 $dev);
            $nvme_io =~ s/\r//g;
            $nvme_io = join("\n", grep { /^nvme/ } split(/\n/, $nvme_io));

            # 拼接结果
            $nvme_status .= "DEVICE: $dev\n" . $nvme_info . "\n" . $nvme_io . "\n---\n";
        }
    }

    $res->{nvme_status} = $nvme_status;
    # ---------- end nvme 多盘安全采集 ----------


    # 获取硬盘信息
    my $hdd_data = "";
    my @hdds = `smartctl --scan`;

    foreach my $line (@hdds) {
        if ($line =~ m#^(/dev/sd\w+) -d (\w+)#) {
            my $dev = $1;
            my $dtype = $2;
            $hdd_data .= ">>> $dev\n";   # 加设备分隔符
            my $info = `smartctl -a $dev 2>/dev/null | grep -E "Device Model|Vendor|User Capacity|Power_On_Hours|Temperature|Airflow_Temperature"`;
            $hdd_data .= "$info\n";
        }
    }

    $res->{hdd_temperatures} = $hdd_data;

    $res->{ups_status} = `apcaccess status`;

    my $powermode = `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor && turbostat -S -q -s PkgWatt -i 0.1 -n 1 -c package | grep -v PkgWatt`;
    $res->{cpupower} = $powermode;

EOF

    ###################  修改node.pm   ##########################
    log_info "开始大活"
    log_info "修改node.pm："
    log_info "找到关键字 PVE::pvecfg::version_text 的行号并跳到下一行"
    # 显示匹配的行
    ln=$(expr $(sed -n -e '/PVE::pvecfg::version_text/=' $nodes) + 1)
    log_info "匹配的行号： $ln"

    log_info "修改结果："
    sed -i "${ln}r $tmpf" $nodes
    # 显示修改结果
    sed -n '/PVE::pvecfg::version_text/,+18p' $nodes
    rm $tmpf

    ###################  修改pvemanagerlib.js   ##########################
    tmpf=tmpfile.temp
    touch $tmpf
    cat > $tmpf << 'EOF'

    {
        itemId: 'CPUW',
        colspan: 2,
        printBar: false,
        title: gettext('CPU功耗'),
        textField: 'cpupower',
        renderer: function(value) {
            const w0 = value.split('\n')[0].split(' ')[0];
            const w1 = value.split('\n')[1].split(' ')[0];
            return `CPU电源模式: <strong>${w0}</strong> | CPU功耗: <strong>${w1} W</strong>`;
        }
    },

    {
        itemId: 'MHz',
        colspan: 2,
        printBar: false,
        title: gettext('CPU频率'),
        textField: 'cpusensors',
        renderer: function(value) {
            const f0 = value.match(/cpu MHz.*?([\d]+)/)[1];
            const f1 = value.match(/CPU min MHz.*?([\d]+)/)[1];
            const f2 = value.match(/CPU max MHz.*?([\d]+)/)[1];
            return `CPU实时: <strong>${f0} MHz</strong> | 最小: ${f1} MHz | 最大: ${f2} MHz`;
        }
    },

    {
        itemId: 'thermal',
        colspan: 2,
        printBar: false,
        title: gettext('CPU温度'),
        textField: 'thermalstate',
        renderer: function(value) {
            const coreTemps = [];
            let coreMatch;
            const coreRegex = /(Core\s*\d+|Core\d+|Tdie|Tctl|Physical id\s*\d+).*?\+\s*([\d\.]+)/gi;

            while ((coreMatch = coreRegex.exec(value)) !== null) {
                let label = coreMatch[1];
                let tempValue = coreMatch[2];

                if (label.match(/Tdie|Tctl/i)) {
                    coreTemps.push(`CPU温度: <strong>${tempValue}℃</strong>`);
                } else {
                    const coreNumberMatch = label.match(/\d+/);
                    const coreNum = coreNumberMatch ? parseInt(coreNumberMatch[0]) + 1 : 1;
                    coreTemps.push(`核心${coreNum}: <strong>${tempValue}℃</strong>`);
                }
            }

            // 核显温度
            let igpuTemp = '';
            const intelIgpuMatch = value.match(/(GFX|Graphics).*?\+\s*([\d\.]+)/i);
            const amdIgpuMatch = value.match(/(junction|edge).*?\+\s*([\d\.]+)/i);

            if (intelIgpuMatch) {
                igpuTemp = `核显: ${intelIgpuMatch[2]}℃`;
            } else if (amdIgpuMatch) {
                igpuTemp = `核显: ${amdIgpuMatch[2]}℃`;
            }

            if (coreTemps.length === 0) {
                const k10tempMatch = value.match(/k10temp-pci-\w+\n[^+]*\+\s*([\d\.]+)/);
                if (k10tempMatch) {
                    coreTemps.push(`CPU温度: <strong>${k10tempMatch[1]}℃</strong>`);
                }
            }

            const groupedTemps = [];
            for (let i = 0; i < coreTemps.length; i += 4) {
                groupedTemps.push(coreTemps.slice(i, i + 4).join(' | '));
            }

            const packageMatch = value.match(/(Package|SoC)\s*(id \d+)?.*?\+\s*([\d\.]+)/i);
            const packageTemp = packageMatch ? `CPU Package: <strong>${packageMatch[3]}℃</strong>` : '';

            const boardTempMatch = value.match(/(?:temp1|motherboard|sys).*?\+\s*([\d\.]+)/i);
            const boardTemp = boardTempMatch ? `主板: <strong>${boardTempMatch[1]}℃</strong>` : '';

            const combinedTemps = [igpuTemp, packageTemp, boardTemp].filter(Boolean).join(' | ');

            const result = [groupedTemps.join('<br>'), combinedTemps].filter(Boolean).join('<br>');

            return result || '未获取到温度信息';
        }
    },

    {
        itemId: 'HEXIN',
        colspan: 2,
        printBar: false,
        title: gettext('核心频率'),
        textField: 'cpusensors',
        renderer: function(value) {
            const freqMatches = value.matchAll(/^cpu MHz\s*:\s*([\d\.]+)/gm);
            const frequencies = [];

            for (const match of freqMatches) {
                const coreNum = frequencies.length + 1;
                frequencies.push(`核心${coreNum}: <strong>${parseInt(match[1])} MHz</strong>`);
            }

            if (frequencies.length === 0) {
                return '无法获取CPU频率信息';
            }

            const groupedFreqs = [];
            for (let i = 0; i < frequencies.length; i += 4) {
                const group = frequencies.slice(i, i + 4);
                groupedFreqs.push(group.join(' | '));
            }

            return groupedFreqs.join('<br>');
        }
    },

    /* 检测不到相关参数的可以注释掉---需要的注释本行即可
    // 风扇转速
    {
          itemId: 'RPM',
          colspan: 2,
          printBar: false,
          title: gettext('CPU风扇'),
          textField: 'thermalstate',
          renderer:function(value){
              const fan1 = value.match(/fan1:.*?\ ([\d.]+) R/)[1];
              const fan2 = value.match(/fan2:.*?\ ([\d.]+) R/)[1];
              if (fan1 === "0") {
                fan11 = "停转";
              } else {
                fan11 = fan1 + " RPM";
              }
              if (fan2 === "0") {
                fan22 = "停转";
              } else {
                fan22 = fan2 + " RPM";
              }
              return `CPU风扇: ${fan11} | 系统风扇: ${fan22}`
            }
    },
    检测不到相关参数的可以注释掉---需要的注释本行即可  */
    // NVME 硬盘（多盘解析版）
    {
        itemId: 'nvme-status',
        colspan: 2,
        printBar: false,
        title: gettext('NVME硬盘'),
        textField: 'nvme_status',
        renderer: function(value) {
            if (value.length > 0) {
                value = value.replace(/Â/g, '');
                let devices = value.split(/---/);
                let outputs = [];

                for (const dev of devices) {
                    if (dev.trim().length === 0) continue;

                    // 设备名
                    let devNameMatch = dev.match(/DEVICE:\s*(nvme\S+)/);
                    let devName = devNameMatch ? devNameMatch[1] : '未知NVMe';

                    // 型号
                    let modelMatch = dev.match(/Model Number:\s*(.+)/);
                    let model = modelMatch ? modelMatch[1].trim() : devName;

                    // 容量
                    let capMatch = dev.match(/Capacity.*\[(.+)\]/);
                    let capacity = capMatch ? capMatch[1].replace(/ |,/g, '') : "未知";

                    // 温度
                    let tempMatch = dev.match(/Temperature:\s*([\d]+)/);
                    let temperature = tempMatch ? tempMatch[1] : "未知";

                    // 寿命
                    let usedMatch = dev.match(/Percentage Used:\s*(\d+)/);
                    let life = usedMatch ? (100 - parseInt(usedMatch[1])) + "%" : "未知";

                    // 已读 / 已写
                    let readMatch = dev.match(/Data Units Read.*\[(.+)\]/);
                    let writtenMatch = dev.match(/Data Units Written.*\[(.+)\]/);
                    let readData = readMatch ? readMatch[1].trim() : "未知";
                    let writtenData = writtenMatch ? writtenMatch[1].trim() : "未知";

                    // 通电次数 / 小时 / 不安全断电
                    let cycleMatch = dev.match(/Power Cycles:\s*(\d+)/);
                    let cycles = cycleMatch ? cycleMatch[1] : "未知";
                    let hoursMatch = dev.match(/Power On Hours:\s*(\d+)/);
                    let hours = hoursMatch ? hoursMatch[1] : "未知";
                    let unsafeMatch = dev.match(/Unsafe Shutdowns:\s*(\d+)/);
                    let unsafes = unsafeMatch ? unsafeMatch[1] : "未知";

                    // I/O 状态 (iostat 输出)
                    let ioMatch = dev.match(/^nvme\S+\s+([\d\.\s]+)/m);
                    let ioText = "";
                    if (ioMatch) {
                        let ioArray = ioMatch[0].trim().split(/\s+/);
                        if (ioArray.length >= 22) {
                            let rMB = (parseFloat(ioArray[2]) / 1024).toFixed(2); // rkB/s
                            let wMB = (parseFloat(ioArray[3]) / 1024).toFixed(2); // wkB/s
                            let rAwait = ioArray[6] || "?";   // r_await
                            let wAwait = ioArray[7] || "?";   // w_await
                            let util = ioArray[ioArray.length - 1] || "?"; // %util
                            ioText = `I/O: 读-速度${rMB}MB/s, 延迟${rAwait}ms / 写-速度${wMB}MB/s, 延迟${wAwait}ms | 负载${util}%`;
                        }
                    }

                    // 拼接最终输出
                    outputs.push(
                        `<strong>${model}</strong> (${devName})<br>
                         容量: ${capacity} | 寿命: ${life} (已读${readData}, 已写${writtenData}) | 温度: <strong>${temperature}°C</strong><br>
                         ${ioText}<br>
                         通电: ${cycles}次, 不安全断电${unsafes}次, 累计${hours}小时`
                    );
                }

                return outputs.join('<br><br>');
            } else {
                return '提示: 未安装 NVME 或已直通 NVME 控制器！';
            }
        }
    },

    // 检测不到相关参数的可以注释掉---需要的注释本行即可  */
    // SATA硬盘温度
    {
        itemId: 'hdd-temperatures',
        colspan: 2,
        printBar: false,
        title: gettext('SATA硬盘'),
        textField: 'hdd_temperatures',
        cellWrap: true,
        renderer: function(value) {
            if (value.length > 0) {
                let outputs = [];

                // 每个硬盘块以 >>> 开头分隔
                let devices = value.split(/>>> /).filter(d => d.trim().length > 0);

                for (const devInfo of devices) {
                    // 硬盘路径（/dev/sdX）
                    let devPathMatch = devInfo.match(/^(\S+)/);
                    let devPath = devPathMatch ? devPathMatch[1] : "未知设备";

                    // 型号
                    let devModel = devInfo.match(/Device Model:\s*(.+)/);
                    if (!devModel) {
                        devModel = devInfo.match(/Vendor:\s*(.+)/);
                    }
                    let title = devModel ? devModel[1].trim() : devPath;

                    // 容量
                    let capacity = devInfo.match(/User Capacity:\s*(.+)/);
                    capacity = capacity ? capacity[1].match(/\[(.*?)\]/)[1].trim() : "未知容量";

                    // 通电小时
                    let hours = devInfo.match(/Power_On_Hours.*- *(\d+)/);
                    hours = hours ? hours[1] : "未知";

                    // 温度（多种可能）
                    let temp = devInfo.match(/Temperature_Celsius.*- *(\d+)/);
                    if (!temp) {
                        temp = devInfo.match(/Airflow_Temperature.*- *(\d+)/);
                    }
                    if (!temp) {
                        temp = devInfo.match(/Current Drive Temperature:\s*(\d+)/);
                    }
                    let tempVal;
                    if (temp && temp[1] !== "0") {
                        tempVal = temp[1] + "°C";
                    } else {
                        tempVal = "不支持温度监控";
                    }

                    // 输出
                    let line = `<strong>${title}</strong><br>容量: ${capacity} | 通电: ${hours}小时 | 温度: <strong>${tempVal}</strong>`;
                    outputs.push(line);
                }

                return `<div style="white-space: normal !important;overflow: visible !important;">${outputs.join('<br>')}</div>`;
            } else {
                return '提示: 未安装硬盘或已直通硬盘控制器';
            }
        }
    },

    // UPS 信息
    {
        itemId: 'ups-status',
        colspan: 2,
        printBar: false,
        title: gettext('UPS 信息'),
        textField: 'ups_status',
        cellWrap: true,
        renderer: function(value) {
            if (value.length > 0) {
                try {
                    const DATE    = value.match(/DATE\s*:\s*([\d\-]+ \d+:\d+:\d+)/)[1];
                    const STATUS  = value.match(/STATUS\s*:\s*([A-Z]+)/)[1];
                    const LINEV   = value.match(/OUTPUTV\s*:\s*([\d\.]+)/)[1];
                    const LOADPCT = value.match(/LOADPCT\s*:\s*([\d\.]+)/)[1];
                    const BCHARGE = value.match(/BCHARGE\s*:\s*([\d\.]+)/)[1];
                    const TIMELEFT= value.match(/TIMELEFT\s*:\s*([\d\.]+)/)[1];
                    const MODEL   = value.match(/MODEL\s*:\s*(.+)/)[1].trim();

                    return `型号：${MODEL} ,状态：${STATUS} ,更新时间：${DATE}<br>
                            电池电量：${BCHARGE} % 剩余供电时间：${TIMELEFT} 分钟<br>
                            输出电压：${LINEV} V , 负载：${LOADPCT} %`;
                } catch(e) {
                    return 'UPS 信息解析失败:' + value;
                }
            } else {
                return '提示: 未检测到 UPS 或 apcaccess 未运行';
            }
        }
    },
EOF

    log_info "找到关键字pveversion的行号"
    # 显示匹配的行
    ln=$(sed -n '/pveversion/,+10{/},/{=;q}}' $pvemanagerlib)
    log_info "匹配的行号pveversion： $ln"

    log_info "修改结果："
    sed -i "${ln}r $tmpf" $pvemanagerlib
    # 显示修改结果
    # sed -n '/pveversion/,+30p' $pvemanagerlib
    rm $tmpf

    log_info "修改页面高度"
    disk_count=$(lsblk -d -o NAME | grep -cE 'sd[a-z]|nvme[0-9]')
    # 高度变量，如果某些设备CPU核心过多，导致高度不够，修改65为合适的数字，如80、100等。
    height_increase=$((disk_count * 65))

    node_status_new_height=$((400 + height_increase))
    sed -i -r '/widget\.pveNodeStatus/,+5{/height/{s#[0-9]+#'$node_status_new_height'#}}' $pvemanagerlib
    cpu_status_new_height=$((300 + height_increase))
    sed -i -r '/widget\.pveCpuStatus/,+5{/height/{s#[0-9]+#'$cpu_status_new_height'#}}' $pvemanagerlib

    log_info "修改后的高度值："
    sed -n -e '/widget\.pveNodeStatus/,+5{/height/{p}}' \
           -e '/widget\.pveCpuStatus/,+5{/height/{p}}' $pvemanagerlib

    # 调整显示布局
    ln=$(expr $(sed -n -e '/widget.pveDcGuests/=' $pvemanagerlib) + 10)
    sed -i "${ln}a\ textAlign: 'right'," $pvemanagerlib
    ln=$(expr $(sed -n -e '/widget.pveNodeStatus/=' $pvemanagerlib) + 10)
    sed -i "${ln}a\ textAlign: 'right'," $pvemanagerlib

    ###################  修改proxmoxlib.js   ##########################

    log_info "修改去除订阅弹窗"
    sed -r -i '/\/nodes\/localhost\/subscription/,+10{/^\s+if \(res === null /{N;s#.+#\t\t  if(false){#}}' $proxmoxlib
    # 显示修改结果
    sed -n '/\/nodes\/localhost\/subscription/,+10p' $proxmoxlib

    systemctl restart pveproxy
    log_success "请刷新浏览器缓存shift+f5"
}

# 删除工具
cpu_del() {
    nodes="/usr/share/perl5/PVE/API2/Nodes.pm"
    pvemanagerlib="/usr/share/pve-manager/js/pvemanagerlib.js"
    proxmoxlib="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"

    pvever=$(pveversion | awk -F"/" '{print $2}')
    echo pve版本$pvever
    if [ -f "$nodes.$pvever.bak" ];then
        rm -f $nodes $pvemanagerlib $proxmoxlib
        mv $nodes.$pvever.bak $nodes
        mv $pvemanagerlib.$pvever.bak $pvemanagerlib
        mv $proxmoxlib.$pvever.bak $proxmoxlib

        log_success "已删除温度显示，请重新刷新浏览器缓存."
    else
        log_warn "你没有添加过温度显示，退出脚本."
    fi
}
#--------------CPU、主板、硬盘温度显示----------------

#---------PVE8/9添加ceph-squid源-----------
pve9_ceph() {
    sver=`cat /etc/debian_version |awk -F"." '{print $1}'`
    case "$sver" in
     13 )
         sver="trixie"
     ;;
     12 )
         sver="bookworm"
     ;;
    * )
        sver=""
     ;;
    esac
    if [ ! $sver ];then
        log_error "版本不支持！"
        pause
        return
    fi

    log_info "ceph-squid目前仅支持PVE8和9！"
    [[ ! -d /etc/apt/backup ]] && mkdir -p /etc/apt/backup
    [[ ! -d /etc/apt/sources.list.d ]] && mkdir -p /etc/apt/sources.list.d

    [[ -e /etc/apt/sources.list.d/ceph.sources ]] && mv /etc/apt/sources.list.d/ceph.sources /etc/apt/backup/ceph.sources.bak
    [[ -e /etc/apt/sources.list.d/ceph.list ]] && mv /etc/apt/sources.list.d/ceph.list /etc/apt/backup/ceph.list.bak

    [[ -e /usr/share/perl5/PVE/CLI/pveceph.pm ]] && cp -rf /usr/share/perl5/PVE/CLI/pveceph.pm /etc/apt/backup/pveceph.pm.bak
    sed -i 's|http://download.proxmox.com|https://mirrors.tuna.tsinghua.edu.cn/proxmox|g' /usr/share/perl5/PVE/CLI/pveceph.pm

    cat > /etc/apt/sources.list.d/ceph.list <<-EOF
deb https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/ceph-squid ${sver} no-subscription
EOF
    log_success "添加ceph-squid源完成!"
}
#---------PVE8/9添加ceph-squid源-----------

#---------PVE7/8添加ceph-quincy源-----------
pve8_ceph() {
    sver=`cat /etc/debian_version |awk -F"." '{print $1}'`
    case "$sver" in
     12 )
         sver="bookworm"
     ;;
     11 )
         sver="bullseye"
     ;;
    * )
        sver=""
     ;;
    esac
    if [ ! $sver ];then
        log_error "版本不支持！"
        pause
        return
    fi

    log_info "ceph-quincy目前仅支持PVE7和8！"
    [[ ! -d /etc/apt/backup ]] && mkdir -p /etc/apt/backup
    [[ ! -d /etc/apt/sources.list.d ]] && mkdir -p /etc/apt/sources.list.d

    [[ -e /etc/apt/sources.list.d/ceph.sources ]] && mv /etc/apt/sources.list.d/ceph.sources /etc/apt/backup/ceph.sources.bak
    [[ -e /etc/apt/sources.list.d/ceph.list ]] && mv /etc/apt/sources.list.d/ceph.list /etc/apt/backup/ceph.list.bak

    [[ -e /usr/share/perl5/PVE/CLI/pveceph.pm ]] && cp -rf /usr/share/perl5/PVE/CLI/pveceph.pm /etc/apt/backup/pveceph.pm.bak
    sed -i 's|http://download.proxmox.com|https://mirrors.tuna.tsinghua.edu.cn/proxmox|g' /usr/share/perl5/PVE/CLI/pveceph.pm

    cat > /etc/apt/sources.list.d/ceph.list <<-EOF
deb https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/ceph-quincy ${sver} main
EOF
    log_success "添加ceph-quincy源完成!"
}
#---------PVE7/8添加ceph-quincy源-----------
# 待办
#---------PVE7/8添加ceph-quincy源-----------
#---------PVE一键卸载ceph-----------
remove_ceph() {
    log_warn "会卸载ceph，并删除所有ceph相关文件！"

    systemctl stop ceph-mon.target && systemctl stop ceph-mgr.target && systemctl stop ceph-mds.target && systemctl stop ceph-osd.target
    rm -rf /etc/systemd/system/ceph*

    killall -9 ceph-mon ceph-mgr ceph-mds ceph-osd
    rm -rf /var/lib/ceph/mon/* && rm -rf /var/lib/ceph/mgr/* && rm -rf /var/lib/ceph/mds/* && rm -rf /var/lib/ceph/osd/*

    pveceph purge

    apt purge -y ceph-mon ceph-osd ceph-mgr ceph-mds
    apt purge -y ceph-base ceph-mgr-modules-core

    rm -rf /etc/ceph && rm -rf /etc/pve/ceph.conf  && rm -rf /etc/pve/priv/ceph.* && rm -rf /var/log/ceph && rm -rf /etc/pve/ceph && rm -rf /var/lib/ceph

    [[ -e /etc/apt/sources.list.d/ceph.sources ]] && mv /etc/apt/sources.list.d/ceph.sources /etc/apt/backup/ceph.sources.bak

    log_success "已成功卸载ceph."
}
#---------PVE一键卸载ceph-----------

# 显示系统信息
show_system_info() {
    log_step "为您展示系统运行状况"
    echo
    echo -e "${CYAN}系统信息概览${NC}"
    echo -e "${BLUE}----------------------------------------${NC}"
    echo -e "PVE 版本: ${GREEN}$(pveversion | head -n1)${NC}"
    echo -e "内核版本: ${GREEN}$(uname -r)${NC}"
    echo -e "系统负载: ${GREEN}$(uptime | awk -F'load average:' '{print $2}')${NC}"
    echo -e "内存使用: ${GREEN}$(free -h | grep Mem | awk '{print $3"/"$2}')${NC}"
    echo -e "磁盘使用:"
    df -h | grep -E '^/dev/' | awk '{print "  "$1" "$3"/"$2" ("$5")"}'
    echo -e "${BLUE}----------------------------------------${NC}"
}

# 主菜单
show_menu() {
    echo -e "${MAGENTA}请选择您需要的功能：${NC}"
    echo
    echo -e "${YELLOW}1.${NC} 更换软件源 ${GREEN}(强烈推荐，让下载飞起来)${NC}"
    echo -e "${YELLOW}2.${NC} 删除订阅弹窗 ${GREEN}(告别烦人提醒)${NC} | ${RED}（谨慎操作）并且只能在SSH环境下使用否则会被截断${NC}"
    echo -e "${YELLOW}3.${NC} 合并 local 与 local-lvm ${CYAN}(小硬盘救星)${NC}"
    echo -e "${YELLOW}4.${NC} 删除 Swap 分区 ${CYAN}(释放更多空间)${NC}"
    echo -e "${YELLOW}5.${NC} 更新系统 ${GREEN}(保持最新状态)${NC}"
    echo -e "${YELLOW}6.${NC} 显示系统信息 ${BLUE}(查看运行状况)${NC}"
    echo -e ""
    echo -e "${YELLOW}7.${NC} 一键配置 ${MAGENTA}(换源+删弹窗+更新，懒人必选，推荐在SSH下使用)${NC}"
    echo -e ""
    echo -e "${YELLOW}8.${NC} 硬件直通配置 ${BLUE}(PCI设备直通设置)${NC}"
    echo -e "${YELLOW}9.${NC} CPU电源模式 ${BLUE}(调整CPU性能模式)${NC}"
    echo -e "${YELLOW}10.${NC} 温度监控设置 ${BLUE}(CPU/硬盘温度显示)${NC}"
    echo -e "${YELLOW}11.${NC} 温度监控移除 ${BLUE}(移除温度监控功能)${NC}"
    echo -e "${YELLOW}12.${NC} 添加ceph-squid源 ${BLUE}(PVE8/9专用)${NC}"
    echo -e "${YELLOW}13.${NC} 添加ceph-quincy源 ${BLUE}(PVE7/8专用)${NC}"
    echo -e "${YELLOW}14.${NC} 卸载Ceph ${BLUE}(完全移除Ceph)${NC}"
    echo -e "${YELLOW}0.${NC} 退出脚本"
    echo
    echo -e "${CYAN}小贴士：新装系统推荐选择 7 进行一键配置${NC}"
    echo
    echo -n -e "${GREEN}请输入您的选择 [0-14]: ${NC}"
}

# 一键配置
quick_setup() {
    log_step "开始一键配置，坐和放宽，让我来搞定一切"
    echo
    change_sources
    echo
    remove_subscription_popup
    echo
    update_system
    echo
    log_success "一键配置全部完成！您的 PVE 已经完美优化"
    echo -e "${CYAN}现在您可以愉快地使用 PVE 了！${NC}"
}

# 主程序
main() {
    check_root
    check_debug_mode "$@"
    check_pve_version

    while true; do
        show_banner
        show_menu
        read -n 2 choice
        echo
        echo

        case $choice in
            1)
                change_sources
                ;;
            2)
                remove_subscription_popup
                ;;
            3)
                merge_local_storage
                ;;
            4)
                remove_swap
                ;;
            5)
                update_system
                ;;
            6)
                show_system_info
                ;;
            7)
                quick_setup
                ;;
            8)
                hw_passth
                ;;
            9)
                cpupower
                ;;
            10)
                cpu_add
                ;;
            11)
                cpu_del
                ;;
            12)
                pve9_ceph
                ;;
            13)
                pve8_ceph
                ;;
            14)
                remove_ceph
                ;;
            0)
                echo -e "${GREEN}感谢使用 PVE Tools！祝您使用愉快${NC}"
                echo -e "${CYAN}再见！${NC}"
                exit 0
                ;;
            *)
                log_error "哎呀，这个选项不存在呢"
                log_warn "请输入 0-14 之间的数字"
                ;;
        esac

        echo
        echo -e "${YELLOW}按回车键返回主菜单...${NC}"
        read -r
    done
}

# 运行主程序
main "$@"