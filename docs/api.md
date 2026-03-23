# GPU Off-Load API 文档

## 1. 概述

本文档描述GPU Off-Load项目提供的编程接口，包括用户空间GPU压缩引擎API和内核模块接口。

## 2. GPU压缩引擎API

### 2.1 头文件

```c
#include <gpu_compress.h>
```

### 2.2 初始化和清理

#### gpu_compress_init

```c
int gpu_compress_init(void);
```

**描述**: 初始化GPU压缩引擎

**返回值**:
- `0`: 成功
- 负数: 失败（错误码）

**示例**:
```c
if (gpu_compress_init() != 0) {
    fprintf(stderr, "GPU压缩引擎初始化失败\n");
    return -1;
}
```

#### gpu_compress_cleanup

```c
void gpu_compress_cleanup(void);
```

**描述**: 清理GPU压缩引擎资源

**示例**:
```c
gpu_compress_cleanup();
```

### 2.3 设备管理

#### gpu_is_available

```c
bool gpu_is_available(void);
```

**描述**: 检查GPU是否可用

**返回值**: `true` 可用，`false` 不可用

#### gpu_get_device_count

```c
int gpu_get_device_count(void);
```

**描述**: 获取GPU设备数量

**返回值**: 设备数量，负数表示错误

#### gpu_get_device_info

```c
int gpu_get_device_info(int device_id, gpu_device_info_t *info);
```

**描述**: 获取GPU设备信息

**参数**:
- `device_id`: 设备ID（从0开始）
- `info`: 设备信息结构体指针

**返回值**: `0` 成功，负数失败

**示例**:
```c
gpu_device_info_t info;
if (gpu_get_device_info(0, &info) == 0) {
    printf("GPU: %s, 显存: %lu MB\n", 
           info.name, info.total_memory / (1024 * 1024));
}
```

#### gpu_set_device

```c
int gpu_set_device(int device_id);
```

**描述**: 设置当前使用的GPU设备

**参数**: `device_id` 设备ID

**返回值**: `0` 成功，负数失败

### 2.4 上下文管理

#### gpu_compress_create_ctx

```c
gpu_compress_ctx_t *gpu_compress_create_ctx(const compress_options_t *options);
```

**描述**: 创建压缩上下文

**参数**: `options` 压缩选项，NULL使用默认值

**返回值**: 上下文指针，NULL表示失败

**示例**:
```c
compress_options_t opts;
gpu_compress_get_default_options(&opts);
opts.algo = COMPRESS_ALGO_ZSTD;
opts.chunk_size = 64 * 1024;

gpu_compress_ctx_t *ctx = gpu_compress_create_ctx(&opts);
if (!ctx) {
    fprintf(stderr, "创建上下文失败\n");
    return -1;
}
```

#### gpu_compress_destroy_ctx

```c
void gpu_compress_destroy_ctx(gpu_compress_ctx_t *ctx);
```

**描述**: 销毁压缩上下文

**参数**: `ctx` 压缩上下文

#### gpu_compress_get_default_options

```c
void gpu_compress_get_default_options(compress_options_t *options);
```

**描述**: 获取默认压缩选项

**参数**: `options` 压缩选项结构体指针

### 2.5 压缩操作

#### gpu_compress

```c
int gpu_compress(gpu_compress_ctx_t *ctx,
                 const void *input, size_t input_size,
                 void *output, size_t *output_size);
```

**描述**: 同步压缩数据

**参数**:
- `ctx`: 压缩上下文
- `input`: 输入数据
- `input_size`: 输入数据大小
- `output`: 输出缓冲区
- `output_size`: 输入时为输出缓冲区大小，输出时为实际压缩大小

**返回值**: `0` 成功，负数失败

**示例**:
```c
char input[] = "Hello, World! This is a test string for compression.";
char output[1024];
size_t output_size = sizeof(output);

int ret = gpu_compress(ctx, input, strlen(input), output, &output_size);
if (ret == 0) {
    printf("压缩成功: %zu -> %zu 字节\n", strlen(input), output_size);
}
```

#### gpu_decompress

```c
int gpu_decompress(gpu_compress_ctx_t *ctx,
                   const void *input, size_t input_size,
                   void *output, size_t *output_size);
```

**描述**: 同步解压数据

**参数**:
- `ctx`: 压缩上下文
- `input`: 压缩数据
- `input_size`: 压缩数据大小
- `output`: 输出缓冲区
- `output_size`: 输入时为输出缓冲区大小，输出时为实际解压大小

**返回值**: `0` 成功，负数失败

#### gpu_compress_max_size

```c
size_t gpu_compress_max_size(gpu_compress_ctx_t *ctx, size_t input_size);
```

**描述**: 获取压缩后数据的最大可能大小

**参数**:
- `ctx`: 压缩上下文
- `input_size`: 输入数据大小

**返回值**: 最大压缩后大小

### 2.6 异步操作

#### gpu_compress_async

```c
int gpu_compress_async(gpu_compress_ctx_t *ctx,
                       const void *input, size_t input_size,
                       void *output, size_t *output_size,
                       gpu_async_handle_t *handle);
```

**描述**: 异步压缩数据

**参数**:
- `ctx`: 压缩上下文
- `input`: 输入数据
- `input_size`: 输入数据大小
- `output`: 输出缓冲区
- `output_size`: 输出大小指针
- `handle`: 异步操作句柄

**返回值**: `0` 成功，负数失败

#### gpu_async_wait

```c
int gpu_async_wait(gpu_async_handle_t *handle, int timeout_ms);
```

**描述**: 等待异步操作完成

**参数**:
- `handle`: 异步操作句柄
- `timeout_ms`: 超时时间（毫秒），-1表示无限等待

**返回值**: `0` 成功，负数失败或超时

### 2.7 批量操作

#### gpu_compress_batch

```c
int gpu_compress_batch(gpu_compress_ctx_t *ctx,
                       void **inputs, size_t *input_sizes,
                       void **outputs, size_t *output_sizes,
                       int count);
```

**描述**: 批量压缩多个数据块

**参数**:
- `ctx`: 压缩上下文
- `inputs`: 输入数据指针数组
- `input_sizes`: 输入大小数组
- `outputs`: 输出缓冲区指针数组
- `output_sizes`: 输出大小数组
- `count`: 数据块数量

**返回值**: 成功压缩的块数，负数表示错误

### 2.8 统计和调试

#### gpu_compress_get_stats

```c
int gpu_compress_get_stats(gpu_compress_ctx_t *ctx, compress_stats_t *stats);
```

**描述**: 获取压缩统计信息

**参数**:
- `ctx`: 压缩上下文
- `stats`: 统计信息结构体指针

**返回值**: `0` 成功，负数失败

#### gpu_compress_algo_name

```c
const char *gpu_compress_algo_name(compress_algo_t algo);
```

**描述**: 获取算法名称字符串

**参数**: `algo` 算法类型

**返回值**: 算法名称字符串

#### gpu_compress_strerror

```c
const char *gpu_compress_strerror(int error_code);
```

**描述**: 获取错误描述

**参数**: `error_code` 错误码

**返回值**: 错误描述字符串

## 3. 数据结构

### 3.1 compress_options_t

```c
typedef struct {
    compress_algo_t algo;       /* 压缩算法 */
    compress_mode_t mode;       /* 压缩模式 */
    compress_level_t level;     /* 压缩级别 */
    size_t chunk_size;          /* 分块大小（字节） */
    bool use_huffman;           /* 是否使用Huffman编码 */
    bool verify_checksum;       /* 是否校验校验和 */
} compress_options_t;
```

### 3.2 compress_stats_t

```c
typedef struct {
    uint64_t total_bytes_in;    /* 输入总字节数 */
    uint64_t total_bytes_out;   /* 输出总字节数 */
    uint64_t compress_count;    /* 压缩次数 */
    uint64_t decompress_count;  /* 解压次数 */
    double compress_time_ms;    /* 压缩总时间（毫秒） */
    double decompress_time_ms;  /* 解压总时间（毫秒） */
    double avg_compress_ratio;  /* 平均压缩比 */
    double throughput_mbps;     /* 吞吐量（MB/s） */
} compress_stats_t;
```

### 3.3 gpu_device_info_t

```c
typedef struct {
    int device_id;              /* 设备ID */
    char name[256];             /* 设备名称 */
    size_t total_memory;        /* 总显存（字节） */
    size_t free_memory;         /* 可用显存（字节） */
    int compute_capability_major; /* 计算能力主版本 */
    int compute_capability_minor; /* 计算能力次版本 */
    int max_threads_per_block;  /* 每块最大线程数 */
    int multiprocessor_count;   /* SM数量 */
} gpu_device_info_t;
```

### 3.4 枚举类型

```c
/* 压缩算法 */
typedef enum {
    COMPRESS_ALGO_LZ4 = 0,      /* LZ4 - 快速压缩 */
    COMPRESS_ALGO_ZSTD = 1,     /* ZSTD - 高压缩比 */
    COMPRESS_ALGO_DEFLATE = 2,  /* DEFLATE - 通用压缩 */
    COMPRESS_ALGO_SNAPPY = 3,   /* Snappy - 快速压缩 */
    COMPRESS_ALGO_GDEFLATE = 4, /* GPU优化的DEFLATE */
    COMPRESS_ALGO_CASCADED = 5, /* Cascaded压缩 */
    COMPRESS_ALGO_BITCOMP = 6,  /* Bitcomp压缩 */
} compress_algo_t;

/* 压缩模式 */
typedef enum {
    COMPRESS_MODE_SYNC = 0,     /* 同步模式 */
    COMPRESS_MODE_ASYNC = 1,    /* 异步模式 */
} compress_mode_t;

/* 压缩级别 */
typedef enum {
    COMPRESS_LEVEL_FAST = 1,    /* 快速压缩，低压缩比 */
    COMPRESS_LEVEL_BALANCED = 5, /* 平衡模式 */
    COMPRESS_LEVEL_HIGH = 9,    /* 高压缩比，慢速度 */
} compress_level_t;
```

## 4. 错误码

| 错误码 | 名称 | 描述 |
|--------|------|------|
| 0 | GPU_SUCCESS | 成功 |
| -1 | GPU_ERROR_INVALID_PARAM | 无效参数 |
| -2 | GPU_ERROR_NO_DEVICE | 没有可用的GPU设备 |
| -3 | GPU_ERROR_OUT_OF_MEMORY | 内存不足 |
| -4 | GPU_ERROR_CUDA | CUDA错误 |
| -5 | GPU_ERROR_NVCOMP | nvCOMP错误 |
| -6 | GPU_ERROR_COMPRESS | 压缩失败 |
| -7 | GPU_ERROR_DECOMPRESS | 解压失败 |
| -8 | GPU_ERROR_NOT_INITIALIZED | 未初始化 |
| -9 | GPU_ERROR_TIMEOUT | 操作超时 |

## 5. 内核模块接口

### 5.1 dmsetup命令

#### 创建压缩设备

```bash
dmsetup create <名称> --table "0 <大小> compress <设备> <分块大小> <算法>"
```

**参数**:
- `名称`: 压缩设备名称
- `大小`: 设备大小（扇区数）
- `设备`: 底层块设备路径
- `分块大小`: 分块大小（字节）
- `算法`: 压缩算法（lz4/zstd/deflate）

#### 查看设备状态

```bash
dmsetup status <名称>
```

#### 获取统计信息

```bash
dmsetup message <名称> 0 stats
```

#### 重置统计

```bash
dmsetup message <名称> 0 reset_stats
```

#### 删除设备

```bash
dmsetup remove <名称>
```

### 5.2 /sys接口

压缩设备在`/sys/block/dm-<N>/dm/`下提供以下属性：

| 属性 | 描述 |
|------|------|
| `read_bytes` | 读取的总字节数 |
| `write_bytes` | 写入的总字节数 |
| `compressed_bytes` | 压缩后的总字节数 |
| `compression_ratio` | 压缩比 |
| `gpu_enabled` | GPU是否启用 |

## 6. 完整示例

### 6.1 基本压缩示例

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <gpu_compress.h>

int main() {
    // 初始化
    if (gpu_compress_init() != 0) {
        fprintf(stderr, "初始化失败\n");
        return 1;
    }
    
    // 创建上下文
    compress_options_t opts;
    gpu_compress_get_default_options(&opts);
    opts.algo = COMPRESS_ALGO_LZ4;
    
    gpu_compress_ctx_t *ctx = gpu_compress_create_ctx(&opts);
    if (!ctx) {
        fprintf(stderr, "创建上下文失败\n");
        gpu_compress_cleanup();
        return 1;
    }
    
    // 准备数据
    const char *input = "Hello, World! This is a test string.";
    size_t input_size = strlen(input);
    
    // 分配输出缓冲区
    size_t max_output = gpu_compress_max_size(ctx, input_size);
    void *compressed = malloc(max_output);
    void *decompressed = malloc(input_size);
    
    // 压缩
    size_t comp_size = max_output;
    if (gpu_compress(ctx, input, input_size, compressed, &comp_size) != 0) {
        fprintf(stderr, "压缩失败\n");
        goto cleanup;
    }
    
    printf("压缩: %zu -> %zu 字节 (%.1f%%)\n", 
           input_size, comp_size, 
           100.0 * comp_size / input_size);
    
    // 解压
    size_t decomp_size = input_size;
    if (gpu_decompress(ctx, compressed, comp_size, decompressed, &decomp_size) != 0) {
        fprintf(stderr, "解压失败\n");
        goto cleanup;
    }
    
    // 验证
    if (memcmp(input, decompressed, input_size) == 0) {
        printf("验证成功: 数据一致\n");
    } else {
        printf("验证失败: 数据不一致\n");
    }
    
    // 获取统计
    compress_stats_t stats;
    gpu_compress_get_stats(ctx, &stats);
    printf("压缩比: %.2f\n", stats.avg_compress_ratio);
    
cleanup:
    free(compressed);
    free(decompressed);
    gpu_compress_destroy_ctx(ctx);
    gpu_compress_cleanup();
    
    return 0;
}
```

### 6.2 批量压缩示例

```c
#include <stdio.h>
#include <stdlib.h>
#include <gpu_compress.h>

#define NUM_CHUNKS 10
#define CHUNK_SIZE (64 * 1024)

int main() {
    gpu_compress_init();
    
    gpu_compress_ctx_t *ctx = gpu_compress_create_ctx(NULL);
    
    // 准备数据
    void *inputs[NUM_CHUNKS];
    void *outputs[NUM_CHUNKS];
    size_t input_sizes[NUM_CHUNKS];
    size_t output_sizes[NUM_CHUNKS];
    
    for (int i = 0; i < NUM_CHUNKS; i++) {
        inputs[i] = malloc(CHUNK_SIZE);
        outputs[i] = malloc(CHUNK_SIZE * 2);
        input_sizes[i] = CHUNK_SIZE;
        output_sizes[i] = CHUNK_SIZE * 2;
        
        // 填充测试数据
        memset(inputs[i], 'A' + (i % 26), CHUNK_SIZE);
    }
    
    // 批量压缩
    int ret = gpu_compress_batch(ctx, inputs, input_sizes, 
                                  outputs, output_sizes, NUM_CHUNKS);
    printf("成功压缩 %d 个块\n", ret);
    
    // 清理
    for (int i = 0; i < NUM_CHUNKS; i++) {
        free(inputs[i]);
        free(outputs[i]);
    }
    
    gpu_compress_destroy_ctx(ctx);
    gpu_compress_cleanup();
    
    return 0;
}
```

## 7. 性能建议

1. **使用批量操作**: 批量处理多个数据块可以更好地利用GPU并行性
2. **选择合适的分块大小**: 64KB-256KB通常是最佳选择
3. **重用上下文**: 避免频繁创建和销毁上下文
4. **使用异步操作**: 在高吞吐场景下使用异步API
5. **预分配缓冲区**: 减少内存分配开销