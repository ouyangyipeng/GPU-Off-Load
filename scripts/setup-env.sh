#!/bin/bash
#
# GPU Off-Load 环境搭建脚本
# 用于安装CUDA、nvCOMP、内核开发环境等依赖
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检测系统架构
detect_arch() {
    ARCH=$(uname -m)
    log_info "检测到系统架构: $ARCH"
    
    if [ "$ARCH" = "x86_64" ]; then
        CUDA_ARCH="x86_64"
        UBUNTU_ARCH="amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        CUDA_ARCH="arm64"
        UBUNTU_ARCH="arm64"
    else
        log_error "不支持的架构: $ARCH"
        exit 1
    fi
}

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        log_info "检测到操作系统: $PRETTY_NAME"
    else
        log_error "无法检测操作系统"
        exit 1
    fi
}

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_warn "请使用 sudo 运行此脚本"
        exec sudo "$0" "$@"
    fi
}

# 安装基础依赖
install_base_deps() {
    log_info "安装基础依赖..."
    
    apt-get update
    apt-get install -y \
        build-essential \
        cmake \
        git \
        wget \
        curl \
        pkg-config \
        libtool \
        autoconf \
        automake \
        libssl-dev \
        libcurl4-openssl-dev \
        libjson-c-dev \
        uuid-dev \
        libpci-dev \
        libnuma-dev
        
    log_success "基础依赖安装完成"
}

# 安装内核开发环境
install_kernel_dev() {
    log_info "安装内核开发环境..."
    
    KERNEL_VER=$(uname -r)
    
    apt-get install -y \
        linux-headers-$KERNEL_VER \
        linux-modules-extra-$KERNEL_VER \
        kmod \
        libelf-dev \
        libdw-dev
        
    log_success "内核开发环境安装完成 (内核版本: $KERNEL_VER)"
}

# 检查NVIDIA GPU
check_nvidia_gpu() {
    log_info "检查NVIDIA GPU..."
    
    if lspci | grep -i nvidia > /dev/null; then
        log_success "检测到NVIDIA GPU"
        lspci | grep -i nvidia
        return 0
    else
        log_warn "未检测到NVIDIA GPU，请确保GPU已正确安装"
        return 1
    fi
}

# 安装NVIDIA驱动
install_nvidia_driver() {
    log_info "安装NVIDIA驱动..."
    
    # 检查是否已安装
    if command -v nvidia-smi &> /dev/null; then
        log_success "NVIDIA驱动已安装"
        nvidia-smi
        return 0
    fi
    
    # 安装驱动
    apt-get install -y nvidia-driver-535
    
    log_warn "NVIDIA驱动安装完成，需要重启系统才能生效"
    log_warn "请运行: sudo reboot"
}

# 安装CUDA Toolkit
install_cuda() {
    log_info "安装CUDA Toolkit..."
    
    # 检查是否已安装
    if command -v nvcc &> /dev/null; then
        log_success "CUDA已安装"
        nvcc --version
        return 0
    fi
    
    # 添加CUDA仓库
    if [ "$OS" = "ubuntu" ]; then
        if [ "$VER" = "22.04" ]; then
            CUDA_REPO="ubuntu2204"
        elif [ "$VER" = "24.04" ]; then
            CUDA_REPO="ubuntu2404"
        else
            log_error "不支持的Ubuntu版本: $VER"
            exit 1
        fi
        
        wget https://developer.download.nvidia.com/compute/cuda/repos/${CUDA_REPO}/${CUDA_ARCH}/cuda-${CUDA_REPO}.pin
        mv cuda-${CUDA_REPO}.pin /etc/apt/preferences.d/cuda-repository-pin-600
        
        apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/${CUDA_REPO}/${CUDA_ARCH}/3bf863cc.pub
        
        add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/${CUDA_REPO}/${CUDA_ARCH}/ /"
        
        apt-get update
        apt-get install -y cuda-toolkit-12-4 cuda-drivers
        
    elif [ "$OS" = "openeuler" ]; then
        # openEuler的CUDA安装
        log_warn "openEuler系统请手动安装CUDA Toolkit"
        log_warn "参考: https://developer.nvidia.com/cuda-downloads"
        return 1
    fi
    
    # 设置环境变量
    echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
    export PATH=/usr/local/cuda/bin:$PATH
    export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
    
    log_success "CUDA安装完成"
}

# 安装nvCOMP
install_nvcomp() {
    log_info "安装nvCOMP..."
    
    NVCOMP_DIR="/opt/nvcomp"
    mkdir -p $NVCOMP_DIR
    
    # 下载nvCOMP示例代码
    if [ ! -d "$NVCOMP_DIR/CUDALibrarySamples" ]; then
        cd $NVCOMP_DIR
        git clone https://github.com/NVIDIA/CUDALibrarySamples.git
        cd CUDALibrarySamples/nvCOMP
    fi
    
    # 下载nvCOMP库
    # 注意: nvCOMP需要从NVIDIA官网下载或通过包管理器安装
    # 这里使用apt安装方式
    apt-get install -y libnvcomp-dev || {
        log_warn "libnvcomp-dev包不可用，请手动下载nvCOMP库"
        log_warn "下载地址: https://developer.nvidia.com/nvcomp-download"
    }
    
    log_success "nvCOMP安装完成"
}

# 安装测试工具
install_test_tools() {
    log_info "安装测试工具..."
    
    apt-get install -y \
        fio \
        sysstat \
        perf-tools-unstable \
        linux-tools-common \
        linux-tools-$(uname -r) \
        hdparm \
        nvme-cli
        
    log_success "测试工具安装完成"
}

# 安装开发工具
install_dev_tools() {
    log_info "安装开发工具..."
    
    apt-get install -y \
        vim \
        gdb \
        strace \
        ltrace \
        valgrind \
        clang-format \
        cppcheck \
        doxygen \
        graphviz
        
    log_success "开发工具安装完成"
}

# 创建项目目录结构
create_project_structure() {
    log_info "创建项目目录结构..."
    
    PROJECT_ROOT=$(dirname "$(dirname "$(realpath "$0")")")
    
    mkdir -p "$PROJECT_ROOT/src/kernel/dm-compress"
    mkdir -p "$PROJECT_ROOT/src/user/gpu-compress"
    mkdir -p "$PROJECT_ROOT/src/user/tools"
    mkdir -p "$PROJECT_ROOT/src/lib"
    mkdir -p "$PROJECT_ROOT/tests/fio"
    mkdir -p "$PROJECT_ROOT/tests/vdbench"
    mkdir -p "$PROJECT_ROOT/tests/scripts"
    mkdir -p "$PROJECT_ROOT/build"
    
    log_success "项目目录结构创建完成"
}

# 验证安装
verify_installation() {
    log_info "验证安装..."
    
    local errors=0
    
    # 检查GCC
    if command -v gcc &> /dev/null; then
        log_success "GCC: $(gcc --version | head -1)"
    else
        log_error "GCC未安装"
        errors=$((errors + 1))
    fi
    
    # 检查Make
    if command -v make &> /dev/null; then
        log_success "Make: $(make --version | head -1)"
    else
        log_error "Make未安装"
        errors=$((errors + 1))
    fi
    
    # 检查CUDA
    if command -v nvcc &> /dev/null; then
        log_success "CUDA: $(nvcc --version | tail -1)"
    else
        log_warn "CUDA nvcc未找到，请确保CUDA已安装并添加到PATH"
    fi
    
    # 检查NVIDIA驱动
    if command -v nvidia-smi &> /dev/null; then
        log_success "NVIDIA驱动已安装"
        nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
    else
        log_warn "NVIDIA驱动未安装或GPU不可用"
    fi
    
    # 检查内核头文件
    KERNEL_VER=$(uname -r)
    if [ -d "/lib/modules/$KERNEL_VER/build" ]; then
        log_success "内核头文件: $KERNEL_VER"
    else
        log_error "内核头文件未找到: $KERNEL_VER"
        errors=$((errors + 1))
    fi
    
    # 检查fio
    if command -v fio &> /dev/null; then
        log_success "fio: $(fio --version)"
    else
        log_error "fio未安装"
        errors=$((errors + 1))
    fi
    
    if [ $errors -eq 0 ]; then
        log_success "所有依赖验证通过！"
    else
        log_error "有 $errors 个依赖验证失败"
        return 1
    fi
}

# 打印使用帮助
print_help() {
    echo "GPU Off-Load 环境搭建脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --all           安装所有依赖（默认）"
    echo "  --base          仅安装基础依赖"
    echo "  --kernel        仅安装内核开发环境"
    echo "  --cuda          仅安装CUDA"
    echo "  --nvcomp        仅安装nvCOMP"
    echo "  --tools         仅安装测试工具"
    echo "  --verify        仅验证安装"
    echo "  --help          显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 --all        安装所有依赖"
    echo "  $0 --verify     验证安装"
}

# 主函数
main() {
    local action="${1:---all}"
    
    echo "========================================"
    echo "  GPU Off-Load 环境搭建脚本"
    echo "========================================"
    echo ""
    
    case "$action" in
        --all)
            detect_arch
            detect_os
            check_root
            install_base_deps
            install_kernel_dev
            check_nvidia_gpu || true
            install_nvidia_driver || true
            install_cuda || true
            install_nvcomp || true
            install_test_tools
            install_dev_tools
            create_project_structure
            verify_installation
            ;;
        --base)
            detect_arch
            detect_os
            check_root
            install_base_deps
            ;;
        --kernel)
            detect_arch
            check_root
            install_kernel_dev
            ;;
        --cuda)
            detect_arch
            detect_os
            check_root
            install_cuda
            ;;
        --nvcomp)
            check_root
            install_nvcomp
            ;;
        --tools)
            check_root
            install_test_tools
            install_dev_tools
            ;;
        --verify)
            verify_installation
            ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            log_error "未知选项: $action"
            print_help
            exit 1
            ;;
    esac
    
    echo ""
    log_success "环境搭建完成！"
}

# 执行主函数
main "$@"