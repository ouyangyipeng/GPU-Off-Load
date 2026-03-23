# GPU Off-Load 系统设计文档

## 1. 概述

### 1.1 项目背景

在高性能存储服务器场景中，随着NVMe SSD性能的快速提升，CPU处理I/O的开销越来越大。本项目旨在通过GPU offload技术，将存储系统中的压缩/解压等计算密集型任务卸载到GPU执行，从而降低CPU资源消耗，提升整体系统性能。

### 1.2 设计目标

1. **透明压缩**: 在块设备层实现透明压缩，对上层文件系统无感知
2. **GPU加速**: 利用NVIDIA GPU和nvCOMP库加速压缩/解压操作
3. **高性能**: 相比纯CPU实现，显著降低CPU利用率
4. **高可靠**: 保证数据完整性和系统稳定性
5. **易部署**: 提供完整的部署文档和工具

### 1.3 系统架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                           用户空间                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │   应用程序    │  │  GPU压缩引擎  │  │   管理工具    │              │
│  │              │  │  (libgpucomp)│  │ (dm-comp-tool)│              │
│  └──────┬───────┘  └──────┬───────┘  └──────────────┘              │
│         │                 │                                         │
│         │          ┌──────┴──────┐                                  │
│         │          │   nvCOMP    │                                  │
│         │          │   CUDA库    │                                  │
│         │          └──────┬──────┘                                  │
│         │                 │                                         │
└─────────┼─────────────────┼─────────────────────────────────────────┘
          │                 │
          ▼                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                           内核空间                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │   文件系统    │  │    BIO层     │  │ dm-compress  │              │
│  │  (xfs/ext4)  │──▶│              │──▶│   目标模块   │              │
│  └──────────────┘  └──────────────┘  └──────┬───────┘              │
│                                             │                       │
│                                  ┌──────────┴──────────┐            │
│                                  │    块设备驱动        │            │
│                                  │    (NVMe/SSD)       │            │
│                                  └─────────────────────┘            │
└─────────────────────────────────────────────────────────────────────┘
```

## 2. 模块设计

### 2.1 GPU压缩引擎 (libgpucompress)

#### 2.1.1 功能描述

GPU压缩引擎是用户空间共享库，封装了nvCOMP库的压缩/解压功能，提供统一的API接口。

#### 2.1.2 核心接口

```c
/* 初始化和清理 */
int gpu_compress_init(void);
void gpu_compress_cleanup(void);

/* 上下文管理 */
gpu_compress_ctx_t *gpu_compress_create_ctx(const compress_options_t *options);
void gpu_compress_destroy_ctx(gpu_compress_ctx_t *ctx);

/* 压缩/解压 */
int gpu_compress(gpu_compress_ctx_t *ctx, const void *input, size_t input_size,
                 void *output, size_t *output_size);
int gpu_decompress(gpu_compress_ctx_t *ctx, const void *input, size_t input_size,
                   void *output, size_t *output_size);

/* 异步操作 */
int gpu_compress_async(gpu_compress_ctx_t *ctx, ...);
int gpu_decompress_async(gpu_compress_ctx_t *ctx, ...);
```

#### 2.1.3 支持的压缩算法

| 算法 | 特点 | 压缩比 | 速度 |
|------|------|--------|------|
| LZ4 | 快速压缩 | 中等 | 极快 |
| ZSTD | 高压缩比 | 高 | 快 |
| DEFLATE | 通用压缩 | 高 | 中等 |
| Snappy | 快速压缩 | 低 | 极快 |
| GDeflate | GPU优化 | 高 | 快 |
| Cascaded | GPU优化 | 高 | 快 |
| Bitcomp | GPU优化 | 中等 | 快 |

### 2.2 Device Mapper压缩模块 (dm-compress)

#### 2.2.1 功能描述

dm-compress是Linux内核模块，实现Device Mapper的compress目标类型，在块设备层提供透明压缩功能。

#### 2.2.2 核心数据结构

```c
/* 压缩设备结构 */
struct compress_c {
    struct dm_dev *dev;          /* 底层设备 */
    uint32_t chunk_size;         /* 分块大小 */
    enum compress_algo algo;     /* 压缩算法 */
    
    /* 统计信息 */
    atomic64_t read_bytes;
    atomic64_t write_bytes;
    atomic64_t compressed_bytes;
    
    /* 元数据 */
    struct chunk_meta *meta;
    uint64_t total_chunks;
    
    /* GPU相关 */
    void *gpu_ctx;
    bool gpu_available;
};

/* 块元数据 */
struct chunk_meta {
    uint64_t logical_block;      /* 逻辑块号 */
    uint64_t physical_block;     /* 物理块号 */
    uint32_t orig_size;          /* 原始大小 */
    uint32_t comp_size;          /* 压缩后大小 */
    uint8_t algo;                /* 压缩算法 */
    uint8_t checksum[16];        /* 校验和 */
};
```

#### 2.2.3 I/O处理流程

**写入流程:**

```
1. 接收写请求
2. 计算目标块号
3. 读取原始数据（如果需要）
4. 调用GPU压缩引擎压缩数据
5. 更新块元数据
6. 提交压缩后的数据到底层设备
7. 完成请求
```

**读取流程:**

```
1. 接收读请求
2. 查找块元数据
3. 从底层设备读取压缩数据
4. 调用GPU压缩引擎解压数据
5. 返回解压后的数据
6. 完成请求
```

### 2.3 用户空间-内核通信

#### 2.3.1 通信机制

使用字符设备和ioctl实现用户空间与内核空间的通信：

```c
/* ioctl命令 */
#define DM_COMPRESS_IOCTL_BASE      'C'
#define DM_COMPRESS_COMPRESS        _IOWR(DM_COMPRESS_IOCTL_BASE, 1, struct compress_req)
#define DM_COMPRESS_DECOMPRESS      _IOWR(DM_COMPRESS_IOCTL_BASE, 2, struct compress_req)
#define DM_COMPRESS_GET_STATS       _IOR(DM_COMPRESS_IOCTL_BASE, 3, struct compress_stats)

/* 请求结构 */
struct compress_req {
    void *input;           /* 输入缓冲区 */
    size_t input_size;     /* 输入大小 */
    void *output;          /* 输出缓冲区 */
    size_t output_size;    /* 输出大小 */
    int algo;              /* 压缩算法 */
    int flags;             /* 标志 */
};
```

#### 2.3.2 DMA缓冲区管理

使用DMA-BUF实现零拷贝数据传输：

```c
/* DMA缓冲区分配 */
void *dm_compress_alloc_dma(size_t size);
void dm_compress_free_dma(void *buf);

/* DMA同步 */
void dm_compress_sync_to_device(void *buf, size_t size);
void dm_compress_sync_to_cpu(void *buf, size_t size);
```

## 3. 性能优化

### 3.1 GPU优化策略

1. **批处理**: 将多个小块合并为大批次处理
2. **异步执行**: 使用CUDA流实现异步压缩
3. **内存池**: 预分配GPU内存减少分配开销
4. **流水线**: 压缩和数据传输并行执行

### 3.2 内核优化策略

1. **BIO合并**: 合并相邻的BIO请求
2. **预读**: 预测性读取压缩数据
3. **缓存**: 缓存热点数据
4. **延迟写入**: 批量写入减少I/O次数

### 3.3 内存优化

1. **分块压缩**: 大数据分块处理
2. **内存复用**: 重用缓冲区减少分配
3. **NUMA感知**: 在正确的NUMA节点分配内存

## 4. 可靠性设计

### 4.1 数据完整性

1. **校验和**: 每个压缩块存储校验和
2. **原子写入**: 确保写入操作的原子性
3. **错误恢复**: 检测并恢复损坏的数据

### 4.2 故障处理

1. **GPU故障**: 自动回退到CPU压缩
2. **内存不足**: 优雅降级处理
3. **I/O错误**: 重试和错误报告

### 4.3 稳定性保障

1. **压力测试**: 长时间高负载测试
2. **边界测试**: 极端情况测试
3. **故障注入**: 模拟故障场景

## 5. 测试设计

### 5.1 功能测试

| 测试项 | 描述 |
|--------|------|
| 基本压缩 | 验证压缩功能正确性 |
| 基本解压 | 验证解压功能正确性 |
| 多算法测试 | 测试所有支持的压缩算法 |
| 边界测试 | 测试边界条件 |
| 错误处理 | 测试错误处理逻辑 |

### 5.2 性能测试

| 测试项 | 工具 | 指标 |
|--------|------|------|
| 顺序读写 | fio | 吞吐量、延迟 |
| 随机读写 | fio | IOPS、延迟 |
| 混合负载 | fio | 综合性能 |
| CPU利用率 | perf | CPU使用率 |
| GPU利用率 | nvidia-smi | GPU使用率 |

### 5.3 压力测试

| 测试项 | 描述 |
|--------|------|
| 长时间运行 | 72小时连续运行 |
| 高并发 | 多线程并发访问 |
| 大数据量 | TB级数据处理 |
| 内存压力 | 内存受限场景 |

## 6. 部署设计

### 6.1 安装流程

```
1. 安装依赖（CUDA、nvCOMP）
2. 编译用户空间库
3. 编译内核模块
4. 加载内核模块
5. 创建压缩设备
6. 创建文件系统
7. 挂载使用
```

### 6.2 配置选项

```bash
# 创建压缩设备
dmsetup create compress_dev --table \
    "0 `blockdev --getsize /dev/nvme0n1` compress /dev/nvme0n1 65536 lz4"

# 参数说明:
# - /dev/nvme0n1: 底层设备
# - 65536: 分块大小（字节）
# - lz4: 压缩算法
```

### 6.3 监控和调试

```bash
# 查看设备状态
dmsetup status compress_dev

# 查看统计信息
dmsetup message compress_dev 0 stats

# 重置统计
dmsetup message compress_dev 0 reset_stats
```

## 7. 扩展性设计

### 7.1 支持更多压缩算法

通过插件机制支持新的压缩算法：

```c
struct compress_algorithm {
    const char *name;
    int (*compress)(const void *src, size_t src_len, void *dst, size_t *dst_len);
    int (*decompress)(const void *src, size_t src_len, void *dst, size_t *dst_len);
    size_t (*bound)(size_t src_len);
};
```

### 7.2 支持其他GPU厂商

通过抽象层支持不同GPU厂商：

```c
struct gpu_backend {
    const char *name;
    int (*init)(void);
    void (*cleanup)(void);
    int (*compress)(...);
    int (*decompress)(...);
};
```

## 8. 安全考虑

### 8.1 数据安全

1. **加密支持**: 可选的数据加密
2. **访问控制**: 设备访问权限控制
3. **审计日志**: 操作日志记录

### 8.2 系统安全

1. **输入验证**: 验证所有用户输入
2. **缓冲区检查**: 防止缓冲区溢出
3. **权限控制**: 最小权限原则

## 9. 版本规划

### v1.0 (当前)

- 基本压缩/解压功能
- LZ4/ZSTD算法支持
- CPU压缩实现

### v1.1

- GPU压缩支持
- 异步操作支持
- 性能优化

### v2.0

- 多GPU支持
- 更多压缩算法
- 加密支持