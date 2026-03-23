# GPU Off-Load 环境搭建指南

## 1. 系统要求

### 1.1 硬件要求

| 组件 | 最低要求 | 推荐配置 |
|------|----------|----------|
| CPU | 4核心 | 8核心以上 |
| 内存 | 8GB | 32GB以上 |
| GPU | NVIDIA RTX 3060 | NVIDIA RTX 4060/5060 |
| GPU显存 | 8GB | 12GB以上 |
| 存储 | 100GB SSD | NVMe SSD |

### 1.2 软件要求

| 软件 | 版本要求 |
|------|----------|
| 操作系统 | Ubuntu 22.04 / openEuler 22.03 |
| Linux内核 | 5.15+ |
| NVIDIA驱动 | 535+ |
| CUDA Toolkit | 12.0+ |
| nvCOMP | 3.0+ |

## 2. 安装步骤

### 2.1 安装NVIDIA驱动

#### Ubuntu 22.04

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装NVIDIA驱动
sudo apt install -y nvidia-driver-535

# 重启系统
sudo reboot
```

#### 验证安装

```bash
# 检查驱动版本
nvidia-smi

# 预期输出
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 535.154.05             Driver Version: 535.154.05   CUDA Version: 12.2     |
|-----------------------------------------+----------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|                                         |                      |               MIG M. |
|=========================================+======================+======================|
|   0  NVIDIA GeForce RTX 3060        Off | 00000000:01:00.0  On |                  N/A |
| N/A   45C    P8              12W / N/A  |    512MiB /  8192MiB |      4%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
```

### 2.2 安装CUDA Toolkit

#### 方法一：使用apt安装（推荐）

```bash
# 添加CUDA仓库
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin
sudo mv cuda-ubuntu2204.pin /etc/apt/preferences.d/cuda-repository-pin-600

# 添加GPG密钥
sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub

# 添加仓库
sudo add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/ /"

# 更新并安装
sudo apt update
sudo apt install -y cuda-toolkit-12-4

# 设置环境变量
echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc
```

#### 方法二：使用runfile安装

```bash
# 下载CUDA runfile
wget https://developer.download.nvidia.com/compute/cuda/12.4.0/local_installers/cuda_12.4.0_550.54.14_linux.run

# 安装（仅安装toolkit，不安装驱动）
sudo sh cuda_12.4.0_550.54.14_linux.run --toolkit --silent

# 设置环境变量
echo 'export PATH=/usr/local/cuda-12.4/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.4/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc
```

#### 验证安装

```bash
# 检查CUDA版本
nvcc --version

# 预期输出
nvcc: NVIDIA (R) Cuda compiler driver
Copyright (c) 2005-2024 NVIDIA Corporation
Built on Tue_Feb_27_16:28:36_PST_2024
Cuda compilation tools, release 12.4, V12.4.99
Build cuda_12.4.r12.4/compiler.33961263_0
```

### 2.3 安装nvCOMP

#### 方法一：使用apt安装

```bash
# 添加NVIDIA仓库（如果尚未添加）
sudo apt-get install -y ca-certificates

# 安装nvCOMP开发包
sudo apt-get install -y libnvcomp-dev
```

#### 方法二：手动安装

```bash
# 下载nvCOMP
cd /tmp
wget https://developer.download.nvidia.com/compute/nvcomp/3.0.6/local_installers/nvcomp_3.0.6_x86_64_12.x.tgz

# 解压
tar -xzf nvcomp_3.0.6_x86_64_12.x.tgz

# 安装头文件
sudo cp -r nvcomp/include/* /usr/local/cuda/include/

# 安装库文件
sudo cp -r nvcomp/lib/* /usr/local/cuda/lib64/

# 更新库缓存
sudo ldconfig
```

#### 验证安装

```bash
# 检查头文件
ls /usr/local/cuda/include/nvcomp/

# 预期输出
aligned_storage.h  bitcomp.hpp    cascaded.hpp    deflate.hpp    lz4.hpp
...
```

### 2.4 安装内核开发环境

```bash
# 安装内核头文件
sudo apt install -y linux-headers-$(uname -r)

# 安装构建工具
sudo apt install -y build-essential kmod

# 验证
ls /lib/modules/$(uname -r)/build
```

### 2.5 安装测试工具

```bash
# 安装fio
sudo apt install -y fio

# 安装系统监控工具
sudo apt install -y sysstat htop iotop

# 安装性能分析工具
sudo apt install -y linux-tools-common linux-tools-$(uname -r) perf-tools-unstable

# 验证
fio --version
```

## 3. 编译项目

### 3.1 获取源码

```bash
# 克隆仓库
git clone <repository-url>
cd GPU-Off-Load
```

### 3.2 编译用户空间库

```bash
# 编译GPU压缩库
cd src/user/gpu-compress
make

# 安装
sudo make install
```

### 3.3 编译内核模块

```bash
# 编译dm-compress模块
cd src/kernel/dm-compress
make

# 安装
sudo make install
```

### 3.4 一键编译

```bash
# 在项目根目录
make all

# 安装
sudo make install
```

## 4. 验证安装

### 4.1 检查内核模块

```bash
# 加载模块
sudo modprobe dm_compress

# 检查模块
lsmod | grep dm_compress

# 检查DM目标
dmsetup targets | grep compress
```

### 4.2 检查用户空间库

```bash
# 检查库文件
ldconfig -p | grep gpucompress

# 运行测试
./src/user/gpu-compress/test_gpu_compress
```

### 4.3 创建测试设备

```bash
# 创建压缩设备
sudo dmsetup create test_compress --table \
    "0 `blockdev --getsize /dev/nvme0n1` compress /dev/nvme0n1 65536 lz4"

# 检查设备
ls -la /dev/mapper/test_compress

# 查看状态
sudo dmsetup status test_compress
```

## 5. 常见问题

### 5.1 NVIDIA驱动安装失败

**问题**: 驱动安装后nvidia-smi无法运行

**解决方案**:
```bash
# 检查内核模块
lsmod | grep nvidia

# 如果没有加载，手动加载
sudo modprobe nvidia

# 检查BIOS中的Secure Boot设置
# Secure Boot可能导致驱动签名问题
```

### 5.2 CUDA编译错误

**问题**: nvcc找不到nvCOMP头文件

**解决方案**:
```bash
# 检查CUDA路径
echo $CUDA_PATH
echo $LD_LIBRARY_PATH

# 手动设置
export CUDA_PATH=/usr/local/cuda
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# 检查nvCOMP头文件
ls $CUDA_PATH/include/nvcomp/
```

### 5.3 内核模块编译失败

**问题**: 找不到内核头文件

**解决方案**:
```bash
# 安装正确的内核头文件
sudo apt install -y linux-headers-$(uname -r)

# 如果使用自定义内核，指定KDIR
make KDIR=/path/to/kernel/source
```

### 5.4 dmsetup创建设备失败

**问题**: dmsetup报告"Invalid argument"

**解决方案**:
```bash
# 检查模块是否加载
lsmod | grep dm_compress

# 检查内核日志
dmesg | tail -20

# 检查设备路径
ls -la /dev/nvme0n1
```

## 6. 环境变量配置

### 6.1 添加到~/.bashrc

```bash
# CUDA环境变量
export CUDA_PATH=/usr/local/cuda
export PATH=$CUDA_PATH/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_PATH/lib64:$LD_LIBRARY_PATH

# 项目环境变量
export GPU_OFFLOAD_ROOT=/path/to/GPU-Off-Load
export LD_LIBRARY_PATH=$GPU_OFFLOAD_ROOT/src/lib:$LD_LIBRARY_PATH
```

### 6.2 添加到/etc/environment

```bash
CUDA_PATH="/usr/local/cuda"
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/cuda/bin"
LD_LIBRARY_PATH="/usr/local/cuda/lib64"
```

## 7. 卸载

### 7.1 卸载内核模块

```bash
# 移除模块
sudo rmmod dm_compress

# 删除模块文件
sudo rm -f /lib/modules/$(uname -r)/extra/dm_compress.ko
sudo depmod -a
```

### 7.2 卸载用户空间库

```bash
sudo rm -f /usr/local/lib/libgpucompress.so*
sudo rm -f /usr/local/include/gpu_compress.h
sudo ldconfig
```

### 7.3 卸载CUDA（可选）

```bash
# 使用CUDA卸载工具
sudo /usr/local/cuda-12.4/bin/cuda-uninstaller

# 或手动删除
sudo rm -rf /usr/local/cuda-12.4
```

## 8. 附录

### 8.1 依赖包列表

```
# Ubuntu 22.04
nvidia-driver-535
cuda-toolkit-12-4
libnvcomp-dev
linux-headers-$(uname -r)
build-essential
kmod
fio
sysstat
htop
iotop
perf-tools-unstable
```

### 8.2 参考链接

- [NVIDIA CUDA下载](https://developer.nvidia.com/cuda-downloads)
- [nvCOMP文档](https://docs.nvidia.com/cuda/nvcomp/index.html)
- [Linux Device Mapper](https://www.kernel.org/doc/Documentation/admin-guide/device-mapper/)
- [Ubuntu NVIDIA驱动安装](https://ubuntu.com/server/docs/nvidia-drivers-installation)