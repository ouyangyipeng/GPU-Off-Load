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
- **架构**: x86_64
- **操作系统**: Ubuntu 22.04
- **GPU**: NVIDIA GPU (支持CUDA)
- **编程框架**: CUDA SDK 12.x

## 目标平台（比赛）
- **架构**: aarch64 (华为鲲鹏920)
- **GPU**: RTX3060/4060/5060
- **操作系统**: openEuler 或 Ubuntu

## 当前状态
- [x] 阅读赛题文档
- [x] 制定项目计划
- [x] 环境搭建脚本
- [x] 代码开发
- [x] 文档编写
- [ ] 测试验证（需要在目标环境执行）

## 重要参考资料
- Linux内核: fs/btrfs, Documentation/admin-guide/device-mapper, drivers/md
- ZFS硬件加速: https://openzfs.org/wiki/ZFS_Hardware_Acceleration_with_QAT
- nvCOMP库: https://github.com/NVIDIA/CUDALibrarySamples/tree/master/nvCOMP
- GRAID: https://graidtech.com/products/supremeraid-he

---
*每次工作前请先阅读此文档了解项目状态*

## 进度日志

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
1. 在目标环境（鲲鹏920 + NVIDIA GPU）上编译测试
2. 运行性能基准测试
3. 收集性能数据并填写测试报告
4. 根据测试结果进行优化
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
- `docs/test-report.md` - 测试报告模板

### 构建
- `Makefile` - 顶层构建文件
- `src/user/gpu-compress/Makefile` - GPU库构建
- `src/kernel/dm-compress/Makefile` - 内核模块构建
- `src/user/tools/Makefile` - 工具构建