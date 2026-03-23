# GPU Off-Load: 基于 GPU 的服务资源卸载技术

## 项目简介

本项目是2026年全国大学生计算机系统能力大赛-操作系统设计赛的参赛作品，旨在通过 GPU offload 将存储系统中的压缩/解压等计算密集型任务卸载到GPU，减少主CPU资源消耗，提升整体系统性能。

## 核心特性

- **Block层透明压缩**: 通过 Device Mapper 在块设备层实现透明压缩，支持上层各种文件系统（xfs、ext4等）
- **GPU加速**: 利用 NVIDIA GPU 和 nvCOMP 库加速压缩/解压操作
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
├── plans/                  # 计划文档
│   └── project-plan.md
├── docs/                   # 项目文档
│   ├── design.md          # 设计文档
│   ├── environment.md      # 环境搭建
│   ├── api.md             # API文档
│   ├── test-report.md     # 测试报告
│   ├── performance.md     # 性能报告
│   └── deployment.md      # 部署指南
├── src/                    # 源代码
│   ├── kernel/            # 内核模块
│   │   └── dm-compress/   # dm压缩模块
│   ├── user/              # 用户空间工具
│   │   ├── gpu-compress/  # GPU压缩引擎
│   │   └── tools/         # 辅助工具
│   └── lib/               # 共享库
├── tests/                  # 测试脚本
│   ├── fio/               # fio测试配置
│   ├── vdbench/           # vdbench测试配置
│   └── scripts/           # 测试脚本
├── scripts/                # 构建和部署脚本
└── Makefile               # 顶层构建文件
```

## 快速开始

### 环境要求

- 操作系统: Ubuntu 22.04 / openEuler
- GPU: NVIDIA GPU (支持CUDA)
- CUDA Toolkit: 12.x
- Linux内核: 5.15+

### 安装步骤

```bash
# 1. 克隆仓库
git clone <repository-url>
cd GPU-Off-Load

# 2. 运行环境搭建脚本
./scripts/setup-env.sh

# 3. 编译项目
make all

# 4. 安装内核模块
sudo make install

# 5. 验证安装
./tests/scripts/verify-install.sh
```

## 使用方法

### 创建压缩块设备

```bash
# 创建压缩块设备
sudo dmsetup create compressed_dev --table "0 `blockdev --getsize /dev/nvme0n1` compress /dev/nvme0n1"

# 查看设备状态
sudo dmsetup status compressed_dev
```

### 性能测试

```bash
# 运行fio测试
./tests/scripts/run-fio-test.sh

# 查看性能报告
cat docs/performance.md
```

## 开发文档

详细文档请参阅 [docs/](docs/) 目录：

- [系统设计文档](docs/design.md)
- [环境搭建指南](docs/environment.md)
- [API文档](docs/api.md)
- [性能测试报告](docs/performance.md)

## 许可证

本项目采用 MIT 许可证。

## 团队

2026年全国大学生计算机系统能力大赛参赛团队。

## 参考资料

- [Linux Device Mapper](https://www.kernel.org/doc/Documentation/admin-guide/device-mapper/)
- [NVIDIA nvCOMP Library](https://github.com/NVIDIA/CUDALibrarySamples/tree/master/nvCOMP)
- [ZFS Hardware Acceleration](https://openzfs.org/wiki/ZFS_Hardware_Acceleration_with_QAT)
- [GRAID Technology](https://graidtech.com/products/supremeraid-he)