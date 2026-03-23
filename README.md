# GPU Off-Load: 基于 GPU 的服务资源卸载技术

## 项目简介

本项目是2026年全国大学生计算机系统能力大赛-操作系统设计赛的参赛作品，旨在通过 GPU offload 将存储系统中的压缩/解压等计算密集型任务卸载到GPU，减少主CPU资源消耗，提升整体系统性能。

## 核心特性

- **Block层透明压缩**: 通过 Device Mapper 在块设备层实现透明压缩，支持上层各种文件系统（xfs、ext4等）
- **GPU加速**: 利用 NVIDIA GPU 和 nvCOMP 库加速压缩/解压操作
- **CPU压缩支持**: 支持使用内核crypto API进行CPU压缩（备用方案）
- **多算法支持**: 支持 LZ4、ZSTD、DEFLATE 等多种压缩算法
- **低CPU开销**: 将计算密集型任务卸载到GPU，显著降低CPU利用率

## 系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                      用户空间                                │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    │
│  │   应用程序   │    │  GPU压缩引擎 │    │   管理工具   │    │
│  └──────┬──────┘    └──────┬──────┘    └─────────────┘    │
│         │                  │                               │
│         │           ┌──────┴──────┐                       │
│         │           │   nvCOMP    │                       │
│         │           │   CUDA库    │                       │
│         │           └──────┬──────┘                       │
└─────────┼──────────────────┼──────────────────────────────┘
          │                  │
          ▼                  ▼
┌─────────────────────────────────────────────────────────────┐
│                      内核空间                                │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    │
│  │   文件系统   │───▶│   BIO层     │───▶│ dm-compress │    │
│  │  (xfs/ext4) │    │             │    │   目标模块  │    │
│  └─────────────┘    └─────────────┘    └──────┬──────┘    │
│                                               │            │
│                                    ┌──────────┴─────────┐  │
│                                    │   块设备驱动        │  │
│                                    │   (NVMe/SSD)       │  │
│                                    └────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## 目录结构

```
GPU-Off-Load/
├── README.md               # 项目说明
├── PROGRESS.md             # 进度记录
├── 赛题.txt                # 赛题文档
├── docs/                   # 项目文档
│   ├── design.md          # 设计文档
│   ├── environment.md      # 环境搭建
│   ├── api.md             # API文档
│   ├── test-report.md     # 测试报告
│   └── deployment.md      # 部署指南
├── src/                    # 源代码
│   ├── kernel/            # 内核模块
│   │   └── dm-compress/   # dm压缩模块
│   └── user/              # 用户空间工具
│       ├── gpu-compress/  # GPU压缩引擎
│       └── tools/         # 辅助工具
├── tests/                  # 测试脚本
│   ├── fio/               # fio测试配置
│   └── scripts/           # 测试脚本
├── scripts/                # 构建和部署脚本
└── Makefile               # 顶层构建文件
```

## 快速开始

### 环境要求

- 操作系统: Ubuntu 22.04 / openEuler
- GPU: NVIDIA GPU (支持CUDA) - 可选
- CUDA Toolkit: 12.x - 可选（GPU加速需要）
- Linux内核: 5.15+
- 架构: x86_64 / aarch64 (鲲鹏920已验证)

### 安装步骤

```bash
# 1. 克隆仓库
git clone https://github.com/ouyangyipeng/GPU-Off-Load.git
cd GPU-Off-Load

# 2. 安装依赖
sudo apt install -y build-essential linux-headers-$(uname -r) fio

# 3. 编译内核模块
cd src/kernel/dm-compress
make

# 4. 加载内核模块
sudo insmod dm_compress.ko

# 5. 验证模块加载
dmsetup targets | grep compress
```

### 创建压缩设备

```bash
# 创建压缩设备
sudo dmsetup create compress_dev --table \
    "0 `blockdev --getsize /dev/nvme0n1` compress /dev/nvme0n1 65536 lz4"

# 创建文件系统
sudo mkfs.ext4 /dev/mapper/compress_dev

# 挂载
sudo mount /dev/mapper/compress_dev /mnt/compress
```

## 测试结果

### 测试环境

| 项目 | 配置 |
|------|------|
| CPU | 华为鲲鹏920 (192核) |
| 内存 | 1.5TB |
| 存储 | 3x 7TB NVMe SSD |
| 内核 | 5.15.0-91-generic |
| GPU | 无（测试CPU压缩模式） |

### 性能数据

| 测试场景 | 带宽 | IOPS | 延迟 |
|----------|------|------|------|
| 顺序写（透传模式）| 616 MiB/s | 9,859 | 3.2ms |
| 随机读（4K）| 201 MiB/s | 51,500 | 433µs |
| 随机写（4K）| 86.3 MiB/s | 22,100 | 436µs |

详细测试报告请查看 [docs/test-report.md](docs/test-report.md)

## 文档

- [项目介绍](docs/introduction.md) - 赛题背景和项目概述
- [设计文档](docs/design.md) - 系统架构设计
- [环境搭建](docs/environment.md) - 开发环境配置
- [部署指南](docs/deployment.md) - 部署和使用说明
- [测试报告](docs/test-report.md) - 性能测试结果

## 开发状态

- [x] 内核模块框架
- [x] Device Mapper compress目标
- [x] CPU压缩支持（crypto API）
- [x] 功能测试通过
- [x] 性能基准测试
- [ ] GPU压缩实现
- [ ] GPU vs CPU性能对比

## 许可证

本项目采用 GPL 许可证（内核模块）和 MIT 许可证（用户空间工具）。

## 贡献

欢迎提交 Issue 和 Pull Request！

## 联系方式

- 项目地址: https://github.com/ouyangyipeng/GPU-Off-Load
- 赛题维护: 四川省华存智谷科技有限责任公司