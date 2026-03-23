/**
 * @file gpu_compress.h
 * @brief GPU压缩引擎头文件
 * 
 * 提供基于NVIDIA GPU的压缩/解压功能接口
 * 使用nvCOMP库实现高性能压缩
 */

#ifndef GPU_COMPRESS_H
#define GPU_COMPRESS_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 压缩算法类型 */
typedef enum {
    COMPRESS_ALGO_LZ4 = 0,      /* LZ4 - 快速压缩 */
    COMPRESS_ALGO_ZSTD = 1,     /* ZSTD - 高压缩比 */
    COMPRESS_ALGO_DEFLATE = 2,  /* DEFLATE - 通用压缩 */
    COMPRESS_ALGO_SNAPPY = 3,  /* Snappy - 快速压缩 */
    COMPRESS_ALGO_GDEFLATE = 4, /* GPU优化的DEFLATE */
    COMPRESS_ALGO_CASCADED = 5, /* Cascaded压缩 */
    COMPRESS_ALGO_BITCOMP = 6,  /* Bitcomp压缩 */
    COMPRESS_ALGO_DEFAULT = COMPRESS_ALGO_LZ4
} compress_algo_t;

/* 压缩模式 */
typedef enum {
    COMPRESS_MODE_SYNC = 0,     /* 同步模式 */
    COMPRESS_MODE_ASYNC = 1,    /* 异步模式 */
    COMPRESS_MODE_DEFAULT = COMPRESS_MODE_SYNC
} compress_mode_t;

/* 压缩级别 */
typedef enum {
    COMPRESS_LEVEL_FAST = 1,    /* 快速压缩，低压缩比 */
    COMPRESS_LEVEL_BALANCED = 5, /* 平衡模式 */
    COMPRESS_LEVEL_HIGH = 9,    /* 高压缩比，慢速度 */
    COMPRESS_LEVEL_DEFAULT = COMPRESS_LEVEL_BALANCED
} compress_level_t;

/* 压缩选项 */
typedef struct {
    compress_algo_t algo;       /* 压缩算法 */
    compress_mode_t mode;       /* 压缩模式 */
    compress_level_t level;     /* 压缩级别 */
    size_t chunk_size;          /* 分块大小（字节） */
    bool use_huffman;           /* 是否使用Huffman编码 */
    bool verify_checksum;       /* 是否校验校验和 */
} compress_options_t;

/* 压缩统计信息 */
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

/* GPU设备信息 */
typedef struct {
    int device_id;             /* 设备ID */
    char name[256];             /* 设备名称 */
    size_t total_memory;        /* 总显存（字节） */
    size_t free_memory;        /* 可用显存（字节） */
    int compute_capability_major; /* 计算能力主版本 */
    int compute_capability_minor; /* 计算能力次版本 */
    int max_threads_per_block;  /* 每块最大线程数 */
    int multiprocessor_count;   /* SM数量 */
} gpu_device_info_t;

/* 压缩上下文（不透明指针） */
typedef struct gpu_compress_ctx gpu_compress_ctx_t;

/* 异步操作句柄 */
typedef struct gpu_async_handle gpu_async_handle_t;

/* 回调函数类型 */
typedef void (*compress_callback_t)(void *user_data, int status, 
                                     size_t compressed_size);

/* ============ 初始化和清理函数 ============ */

/**
 * @brief 初始化GPU压缩引擎
 * @return 0成功，负数失败
 */
int gpu_compress_init(void);

/**
 * @brief 清理GPU压缩引擎
 */
void gpu_compress_cleanup(void);

/**
 * @brief 检查GPU是否可用
 * @return true可用，false不可用
 */
bool gpu_is_available(void);

/**
 * @brief 获取GPU设备数量
 * @return 设备数量，负数表示错误
 */
int gpu_get_device_count(void);

/**
 * @brief 获取GPU设备信息
 * @param device_id 设备ID
 * @param info 设备信息结构体指针
 * @return 0成功，负数失败
 */
int gpu_get_device_info(int device_id, gpu_device_info_t *info);

/**
 * @brief 设置当前使用的GPU设备
 * @param device_id 设备ID
 * @return 0成功，负数失败
 */
int gpu_set_device(int device_id);

/* ============ 上下文管理函数 ============ */

/**
 * @brief 创建压缩上下文
 * @param options 压缩选项
 * @return 压缩上下文指针，NULL表示失败
 */
gpu_compress_ctx_t *gpu_compress_create_ctx(const compress_options_t *options);

/**
 * @brief 销毁压缩上下文
 * @param ctx 压缩上下文
 */
void gpu_compress_destroy_ctx(gpu_compress_ctx_t *ctx);

/**
 * @brief 重置压缩上下文
 * @param ctx 压缩上下文
 * @return 0成功，负数失败
 */
int gpu_compress_reset_ctx(gpu_compress_ctx_t *ctx);

/**
 * @brief 获取默认压缩选项
 * @param options 压缩选项结构体指针
 */
void gpu_compress_get_default_options(compress_options_t *options);

/* ============ 压缩函数 ============ */

/**
 * @brief 压缩数据（同步）
 * @param ctx 压缩上下文
 * @param input 输入数据
 * @param input_size 输入数据大小
 * @param output 输出缓冲区
 * @param output_size 输入时为输出缓冲区大小，输出时为实际压缩大小
 * @return 0成功，负数失败
 */
int gpu_compress(gpu_compress_ctx_t *ctx,
                 const void *input, size_t input_size,
                 void *output, size_t *output_size);

/**
 * @brief 压缩数据（异步）
 * @param ctx 压缩上下文
 * @param input 输入数据
 * @param input_size 输入数据大小
 * @param output 输出缓冲区
 * @param output_size 输入时为输出缓冲区大小，输出时为实际压缩大小
 * @param handle 异步操作句柄
 * @return 0成功，负数失败
 */
int gpu_compress_async(gpu_compress_ctx_t *ctx,
                        const void *input, size_t input_size,
                        void *output, size_t *output_size,
                        gpu_async_handle_t *handle);

/**
 * @brief 获取压缩后数据的最大大小
 * @param ctx 压缩上下文
 * @param input_size 输入数据大小
 * @return 最大压缩后大小
 */
size_t gpu_compress_max_size(gpu_compress_ctx_t *ctx, size_t input_size);

/* ============ 解压函数 ============ */

/**
 * @brief 解压数据（同步）
 * @param ctx 压缩上下文
 * @param input 压缩数据
 * @param input_size 压缩数据大小
 * @param output 输出缓冲区
 * @param output_size 输入时为输出缓冲区大小，输出时为实际解压大小
 * @return 0成功，负数失败
 */
int gpu_decompress(gpu_compress_ctx_t *ctx,
                   const void *input, size_t input_size,
                   void *output, size_t *output_size);

/**
 * @brief 解压数据（异步）
 * @param ctx 压缩上下文
 * @param input 压缩数据
 * @param input_size 压缩数据大小
 * @param output 输出缓冲区
 * @param output_size 输入时为输出缓冲区大小，输出时为实际解压大小
 * @param handle 异步操作句柄
 * @return 0成功，负数失败
 */
int gpu_decompress_async(gpu_compress_ctx_t *ctx,
                          const void *input, size_t input_size,
                          void *output, size_t *output_size,
                          gpu_async_handle_t *handle);

/**
 * @brief 获取解压后数据的大小
 * @param ctx 压缩上下文
 * @param input 压缩数据
 * @param input_size 压缩数据大小
 * @param output_size 输出解压后大小
 * @return 0成功，负数失败
 */
int gpu_decompress_get_size(gpu_compress_ctx_t *ctx,
                             const void *input, size_t input_size,
                             size_t *output_size);

/* ============ 异步操作函数 ============ */

/**
 * @brief 等待异步操作完成
 * @param handle 异步操作句柄
 * @param timeout_ms 超时时间（毫秒），-1表示无限等待
 * @return 0成功，负数失败
 */
int gpu_async_wait(gpu_async_handle_t *handle, int timeout_ms);

/**
 * @brief 检查异步操作是否完成
 * @param handle 异步操作句柄
 * @return true完成，false未完成
 */
bool gpu_async_is_done(gpu_async_handle_t *handle);

/**
 * @brief 释放异步操作句柄
 * @param handle 异步操作句柄
 */
void gpu_async_free_handle(gpu_async_handle_t *handle);

/* ============ 统计和调试函数 ============ */

/**
 * @brief 获取压缩统计信息
 * @param ctx 压缩上下文
 * @param stats 统计信息结构体指针
 * @return 0成功，负数失败
 */
int gpu_compress_get_stats(gpu_compress_ctx_t *ctx, compress_stats_t *stats);

/**
 * @brief 重置压缩统计信息
 * @param ctx 压缩上下文
 * @return 0成功，负数失败
 */
int gpu_compress_reset_stats(gpu_compress_ctx_t *ctx);

/**
 * @brief 获取算法名称
 * @param algo 算法类型
 * @return 算法名称字符串
 */
const char *gpu_compress_algo_name(compress_algo_t algo);

/**
 * @brief 获取错误描述
 * @param error_code 错误码
 * @return 错误描述字符串
 */
const char *gpu_compress_strerror(int error_code);

/* ============ 批量操作函数 ============ */

/**
 * @brief 批量压缩数据
 * @param ctx 压缩上下文
 * @param inputs 输入数据指针数组
 * @param input_sizes 输入数据大小数组
 * @param outputs 输出缓冲区指针数组
 * @param output_sizes 输出大小数组
 * @param count 数据块数量
 * @return 成功压缩的块数，负数表示错误
 */
int gpu_compress_batch(gpu_compress_ctx_t *ctx,
                       void **inputs, size_t *input_sizes,
                       void **outputs, size_t *output_sizes,
                       int count);

/**
 * @brief 批量解压数据
 * @param ctx 压缩上下文
 * @param inputs 压缩数据指针数组
 * @param input_sizes 压缩数据大小数组
 * @param outputs 输出缓冲区指针数组
 * @param output_sizes 输出大小数组
 * @param count 数据块数量
 * @return 成功解压的块数，负数表示错误
 */
int gpu_decompress_batch(gpu_compress_ctx_t *ctx,
                         void **inputs, size_t *input_sizes,
                         void **outputs, size_t *output_sizes,
                         int count);

/* ============ 内存管理函数 ============ */

/**
 * @brief 分配GPU内存
 * @param size 内存大小
 * @return GPU内存指针，NULL表示失败
 */
void *gpu_malloc(size_t size);

/**
 * @brief 释放GPU内存
 * @param ptr GPU内存指针
 */
void gpu_free(void *ptr);

/**
 * @brief 将数据复制到GPU
 * @param dst GPU目标地址
 * @param src 主机源地址
 * @param size 数据大小
 * @return 0成功，负数失败
 */
int gpu_memcpy_to_device(void *dst, const void *src, size_t size);

/**
 * @brief 将数据从GPU复制到主机
 * @param dst 主机目标地址
 * @param src GPU源地址
 * @param size 数据大小
 * @return 0成功，负数失败
 */
int gpu_memcpy_to_host(void *dst, const void *src, size_t size);

#ifdef __cplusplus
}
#endif

#endif /* GPU_COMPRESS_H */