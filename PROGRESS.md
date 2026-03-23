# GPU Off-Load 项目进度记录

## 项目概述
- **赛题名称**: 基于 GPU 的服务资源卸载技术探索
- **赛题难度**: A（工程型）
- **比赛**: 2026年全国大学生计算机系统能力大赛-操作系统设计赛-OS功能挑战赛道

## 核心目标
通过 GPU offload 部分计算密集型的任务（主要是存储压缩/解压），减小主CPU的资源消耗。

## 技术路线
1. **Block层压缩**: 通过 dm (device mapper) 在 block 层作压缩 【优先实现】
   - 优点：上层支持各种文件系统
   
2. **文件系统层压缩**: 通过 btrfs、zfs 在文件系统层作压缩 【可选】
   - 优点：内容感知，可能支持更好的压缩效率

## 开发环境
- **架构**: aarch64 (华为鲲鹏920)
- **操作系统**: Ubuntu 22.04
- **内核**: 5.15.0-91-generic
- **CPU**: 192核鲲鹏920
- **内存**: 1.5TB
- **存储**: 3x 7TB NVMe SSD
- **GPU**: 无NVIDIA GPU（当前测试CPU压缩模式）

## 当前状态
- [x] 阅读赛题文档
- [x] 制定项目计划
- [x] 环境搭建脚本
- [x] 代码开发
- [x] 文档编写
- [x] 内核模块编译测试
- [x] 功能测试验证
- [x] 性能基准测试
- [ ] 实现CPU压缩功能
- [ ] GPU压缩测试（需要NVIDIA GPU环境）

## 重要参考资料
- Linux内核: fs/btrfs, Documentation/admin-guide/device-mapper, drivers/md
- ZFS硬件加速: https://openzfs.org/wiki/ZFS_Hardware_Acceleration_with_QAT
- nvCOMP库: https://github.com/NVIDIA/CUDALibrarySamples/tree/master/nvCOMP
- GRAID: https://graidtech.com/products/supremeraid-he

---

## 进度日志

### 2026-03-24
- 在鲲鹏920服务器上进行测试
- 修复内核模块编译错误:
  - crypto_comp_compress参数类型不匹配
  - REQ_OP_DISARD拼写错误
  - total_chunks计算错误
- 成功加载dm-compress内核模块
- 完成功能测试:
  - 模块加载/卸载正常
  - 压缩设备创建/删除正常
  - ext4文件系统兼容性测试通过
- 完成性能测试:
  - 基准测试（无压缩）: 446 MiB/s, 7142 IOPS
  - dm-compress透传模式: 616 MiB/s, 9859 IOPS
  - 随机读写测试: 读51.5k IOPS, 写22.1k IOPS
- 更新测试报告文档

### 2026-03-23
- 创建项目进度记录文档
- 开始分析赛题要求
- 制定详细项目计划
- 创建项目目录结构
- 创建环境搭建脚本 (scripts/setup-env.sh)
- 创建顶层Makefile
- 创建GPU压缩引擎头文件 (include/gpu_compress.h)
- 创建GPU压缩引擎实现 (src/user/gpu-compress/gpu_compress.cu)
- 创建dm-compress内核模块 (src/kernel/dm-compress/dm-compress.c)
- 创建fio测试配置 (tests/fio/compress-test.fio)
- 创建性能测试脚本 (tests/scripts/run-fio-test.sh)
- 创建设计文档 (docs/design.md)
- 创建环境搭建文档 (docs/environment.md)

## 下一步计划
1. 实现CPU压缩功能（当前模块仅透传I/O）
2. 在有NVIDIA GPU的机器上测试GPU压缩
3. 对比CPU vs GPU压缩的性能差异
4. 优化压缩算法和参数
5. 准备最终提交材料

## 项目文件清单

### 源代码
- `src/user/gpu-compress/gpu_compress.cu` - GPU压缩引擎实现
- `src/kernel/dm-compress/dm-compress.c` - Device Mapper压缩模块
- `src/user/tools/dm-compress-tool.c` - 管理工具

### 头文件
- `include/gpu_compress.h` - GPU压缩引擎API

### 脚本
- `scripts/setup-env.sh` - 环境搭建脚本
- `tests/scripts/run-fio-test.sh` - 性能测试脚本

### 配置
- `tests/fio/compress-test.fio` - fio测试配置

### 文档
- `docs/design.md` - 系统设计文档
- `docs/environment.md` - 环境搭建指南
- `docs/api.md` - API文档
- `docs/deployment.md` - 部署指南
- `docs/test-report.md` - 测试报告

### 构建
- `Makefile` - 顶层构建文件
- `src/user/gpu-compress/Makefile` - GPU库构建
- `src/kernel/dm-compress/Makefile` - 内核模块构建
- `src/user/tools/Makefile` - 工具构建

## 测试结果摘要

| 测试项 | 结果 |
|--------|------|
| 模块加载 | ✅ 通过 |
| 设备创建 | ✅ 通过 |
| 文件系统(ext4) | ✅ 通过 |
| 顺序写性能 | 616 MiB/s, 9859 IOPS |
| 随机读性能 | 201 MiB/s, 51.5k IOPS |
| 随机写性能 | 86.3 MiB/s, 22.1k IOPS |

---
*每次工作前请先阅读此文档了解项目状态*