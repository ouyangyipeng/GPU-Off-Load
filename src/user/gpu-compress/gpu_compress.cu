/**
 * @file gpu_compress.cu
 * @brief GPU压缩引擎实现
 * 
 * 基于NVIDIA nvCOMP库实现GPU加速的压缩/解压功能
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <cuda_runtime.h>
#include <nvcomp/lz4.hpp>
#include <nvcomp/zstd.hpp>
#include <nvcomp/deflate.hpp>
#include <nvcomp/snappy.hpp>
#include <nvcomp/cascaded.hpp>
#include <nvcomp/bitcomp.hpp>

#include "gpu_compress.h"

/* 错误码定义 */
#define GPU_SUCCESS                 0
#define GPU_ERROR_INVALID_PARAM    -1
#define GPU_ERROR_NO_DEVICE        -2
#define GPU_ERROR_OUT_OF_MEMORY    -3
#define GPU_ERROR_CUDA            -4
#define GPU_ERROR_NVCOMP          -5
#define GPU_ERROR_COMPRESS        -6
#define GPU_ERROR_DECOMPRESS      -7
#define GPU_ERROR_NOT_INITIALIZED -8
#define GPU_ERROR_TIMEOUT         -9

/* 默认配置 */
#define DEFAULT_CHUNK_SIZE (64 * 1024)  /* 64KB */
#define MAX_CHUNK_SIZE     (4 * 1024 * 1024)  /* 4MB */

/* 压缩上下文结构体 */
struct gpu_compress_ctx {
    compress_options_t options;     /* 压缩选项 */
    compress_stats_t stats;         /* 统计信息 */
    void *d_temp_buffer;            /* GPU临时缓冲区 */
    size_t temp_buffer_size;         /* 临时缓冲区大小 */
    cudaStream_t stream;             /* CUDA流 */
    bool initialized;                /* 是否已初始化 */
};

/* 全局状态 */
static bool g_initialized = false;
static int g_device_count = 0;
static int g_current_device = 0;

/* ============ 内部辅助函数 ============ */

/**
 * @brief 获取CUDA错误描述
 */
static const char *cuda_get_error_string(cudaError_t err) {
    return cudaGetErrorString(err);
}

/**
 * @brief 检查CUDA错误
 */
#define CUDA_CHECK(call) \
    do { \
        cudaError_t err = call; \
        if (err != cudaSuccess) { \
            fprintf(stderr, "CUDA错误 %s:%d: %s\n", \
                    __FILE__, __LINE__, cuda_get_error_string(err)); \
            return GPU_ERROR_CUDA; \
        } \
    } while (0)

/**
 * @brief 获取nvCOMP压缩算法类型
 */
static nvcompBatchedCascadedOpts_t get_cascaded_opts(compress_algo_t algo, 
                                                      compress_level_t level) {
    nvcompBatchedCascadedOpts_t opts;
    opts.type = nvcompBatchedCascaded;
    opts.num_RLEs = 0;
    opts.num_deltas = 0;
    opts.use_bp = (level >= COMPRESS_LEVEL_HIGH);
    return opts;
}

/**
 * @brief 计算压缩后最大大小
 */
static size_t calc_max_compressed_size(compress_algo_t algo, size_t input_size) {
    size_t overhead = 0;
    
    switch (algo) {
        case COMPRESS_ALGO_LZ4:
            overhead = input_size / 255 + 16;
            break;
        case COMPRESS_ALGO_ZSTD:
            overhead = input_size / 255 + 128;
            break;
        case COMPRESS_ALGO_DEFLATE:
        case COMPRESS_ALGO_GDEFLATE:
            overhead = input_size / 1000 + 12;
            break;
        case COMPRESS_ALGO_SNAPPY:
            overhead = input_size / 6 + 32;
            break;
        case COMPRESS_ALGO_CASCADED:
            overhead = input_size + 1024;
            break;
        case COMPRESS_ALGO_BITCOMP:
            overhead = input_size + 256;
            break;
        default:
            overhead = input_size / 100 + 64;
            break;
    }
    
    return input_size + overhead;
}

/* ============ 初始化和清理函数 ============ */

int gpu_compress_init(void) {
    if (g_initialized) {
        return GPU_SUCCESS;
    }
    
    /* 检查CUDA设备 */
    int device_count = 0;
    cudaError_t err = cudaGetDeviceCount(&device_count);
    
    if (err != cudaSuccess || device_count == 0) {
        fprintf(stderr, "未检测到CUDA设备\n");
        return GPU_ERROR_NO_DEVICE;
    }
    
    g_device_count = device_count;
    g_current_device = 0;
    g_initialized = true;
    
    /* 打印GPU信息 */
    cudaDeviceProp prop;
    for (int i = 0; i < device_count; i++) {
        cudaGetDeviceProperties(&prop, i);
        printf("GPU %d: %s (计算能力 %d.%d, 显存 %.2f GB)\n",
               i, prop.name, prop.major, prop.minor,
               (double)prop.totalGlobalMem / (1024 * 1024 * 1024));
    }
    
    return GPU_SUCCESS;
}

void gpu_compress_cleanup(void) {
    if (!g_initialized) {
        return;
    }
    
    cudaDeviceReset();
    g_initialized = false;
    g_device_count = 0;
    g_current_device = 0;
}

bool gpu_is_available(void) {
    int device_count = 0;
    cudaError_t err = cudaGetDeviceCount(&device_count);
    return (err == cudaSuccess && device_count > 0);
}

int gpu_get_device_count(void) {
    return g_device_count;
}

int gpu_get_device_info(int device_id, gpu_device_info_t *info) {
    if (!g_initialized) {
        return GPU_ERROR_NOT_INITIALIZED;
    }
    
    if (device_id < 0 || device_id >= g_device_count || !info) {
        return GPU_ERROR_INVALID_PARAM;
    }
    
    cudaDeviceProp prop;
    cudaError_t err = cudaGetDeviceProperties(&prop, device_id);
    if (err != cudaSuccess) {
        return GPU_ERROR_CUDA;
    }
    
    info->device_id = device_id;
    strncpy(info->name, prop.name, sizeof(info->name) - 1);
    info->name[sizeof(info->name) - 1] = '\0';
    info->total_memory = prop.totalGlobalMem;
    info->compute_capability_major = prop.major;
    info->compute_capability_minor = prop.minor;
    info->max_threads_per_block = prop.maxThreadsPerBlock;
    info->multiprocessor_count = prop.multiProcessorCount;
    
    /* 获取可用显存 */
    size_t free_mem, total_mem;
    cudaSetDevice(device_id);
    cudaMemGetInfo(&free_mem, &total_mem);
    info->free_memory = free_mem;
    
    return GPU_SUCCESS;
}

int gpu_set_device(int device_id) {
    if (!g_initialized) {
        return GPU_ERROR_NOT_INITIALIZED;
    }
    
    if (device_id < 0 || device_id >= g_device_count) {
        return GPU_ERROR_INVALID_PARAM;
    }
    
    cudaError_t err = cudaSetDevice(device_id);
    if (err != cudaSuccess) {
        return GPU_ERROR_CUDA;
    }
    
    g_current_device = device_id;
    return GPU_SUCCESS;
}

/* ============ 上下文管理函数 ============ */

gpu_compress_ctx_t *gpu_compress_create_ctx(const compress_options_t *options) {
    if (!g_initialized) {
        fprintf(stderr, "GPU压缩引擎未初始化\n");
        return NULL;
    }
    
    gpu_compress_ctx_t *ctx = (gpu_compress_ctx_t *)calloc(1, sizeof(gpu_compress_ctx_t));
    if (!ctx) {
        return NULL;
    }
    
    /* 设置选项 */
    if (options) {
        memcpy(&ctx->options, options, sizeof(compress_options_t));
    } else {
        gpu_compress_get_default_options(&ctx->options);
    }
    
    /* 验证分块大小 */
    if (ctx->options.chunk_size == 0) {
        ctx->options.chunk_size = DEFAULT_CHUNK_SIZE;
    }
    if (ctx->options.chunk_size > MAX_CHUNK_SIZE) {
        ctx->options.chunk_size = MAX_CHUNK_SIZE;
    }
    
    /* 创建CUDA流 */
    cudaError_t err = cudaStreamCreate(&ctx->stream);
    if (err != cudaSuccess) {
        fprintf(stderr, "创建CUDA流失败: %s\n", cuda_get_error_string(err));
        free(ctx);
        return NULL;
    }
    
    /* 分配临时缓冲区 */
    ctx->temp_buffer_size = ctx->options.chunk_size * 2;
    err = cudaMalloc(&ctx->d_temp_buffer, ctx->temp_buffer_size);
    if (err != cudaSuccess) {
        fprintf(stderr, "分配GPU临时缓冲区失败: %s\n", cuda_get_error_string(err));
        cudaStreamDestroy(ctx->stream);
        free(ctx);
        return NULL;
    }
    
    ctx->initialized = true;
    return ctx;
}

void gpu_compress_destroy_ctx(gpu_compress_ctx_t *ctx) {
    if (!ctx) {
        return;
    }
    
    if (ctx->d_temp_buffer) {
        cudaFree(ctx->d_temp_buffer);
    }
    
    if (ctx->stream) {
        cudaStreamDestroy(ctx->stream);
    }
    
    free(ctx);
}

int gpu_compress_reset_ctx(gpu_compress_ctx_t *ctx) {
    if (!ctx || !ctx->initialized) {
        return GPU_ERROR_INVALID_PARAM;
    }
    
    memset(&ctx->stats, 0, sizeof(compress_stats_t));
    return GPU_SUCCESS;
}

void gpu_compress_get_default_options(compress_options_t *options) {
    if (!options) {
        return;
    }
    
    memset(options, 0, sizeof(compress_options_t));
    options->algo = COMPRESS_ALGO_DEFAULT;
    options->mode = COMPRESS_MODE_DEFAULT;
    options->level = COMPRESS_LEVEL_DEFAULT;
    options->chunk_size = DEFAULT_CHUNK_SIZE;
    options->use_huffman = false;
    options->verify_checksum = true;
}

/* ============ 压缩函数 ============ */

int gpu_compress(gpu_compress_ctx_t *ctx,
                 const void *input, size_t input_size,
                 void *output, size_t *output_size) {
    if (!ctx || !ctx->initialized || !input || !output || !output_size) {
        return GPU_ERROR_INVALID_PARAM;
    }
    
    if (input_size == 0) {
        *output_size = 0;
        return GPU_SUCCESS;
    }
    
    cudaError_t cuda_err;
    nvcompStatus_t nvcomp_err;
    
    /* 分配GPU内存 */
    void *d_input = NULL;
    void *d_output = NULL;
    size_t max_output_size = calc_max_compressed_size(ctx->options.algo, input_size);
    
    cuda_err = cudaMalloc(&d_input, input_size);
    if (cuda_err != cudaSuccess) {
        return GPU_ERROR_OUT_OF_MEMORY;
    }
    
    cuda_err = cudaMalloc(&d_output, max_output_size);
    if (cuda_err != cudaSuccess) {
        cudaFree(d_input);
        return GPU_ERROR_OUT_OF_MEMORY;
    }
    
    /* 复制数据到GPU */
    cuda_err = cudaMemcpyAsync(d_input, input, input_size, 
                               cudaMemcpyHostToDevice, ctx->stream);
    if (cuda_err != cudaSuccess) {
        cudaFree(d_input);
        cudaFree(d_output);
        return GPU_ERROR_CUDA;
    }
    
    /* 根据算法选择压缩方式 */
    size_t compressed_size = 0;
    
    switch (ctx->options.algo) {
        case COMPRESS_ALGO_LZ4: {
            /* LZ4压缩 */
            nvcompBatchedLZ4Opts_t lz4_opts = {nvcompBatchedLZ4};
            size_t temp_size = 0;
            
            /* 获取临时缓冲区大小 */
            nvcomp_err = nvcompBatchedLZ4CompressGetTempSize(
                d_input, input_size, nvcompBatchedLZ4, &temp_size);
            
            if (nvcomp_err != nvcompSuccess) {
                cudaFree(d_input);
                cudaFree(d_output);
                return GPU_ERROR_NVCOMP;
            }
            
            /* 分配临时缓冲区 */
            void *d_temp = NULL;
            if (temp_size > 0) {
                cuda_err = cudaMalloc(&d_temp, temp_size);
                if (cuda_err != cudaSuccess) {
                    cudaFree(d_input);
                    cudaFree(d_output);
                    return GPU_ERROR_OUT_OF_MEMORY;
                }
            }
            
            /* 获取压缩后大小 */
            size_t comp_out_size = 0;
            nvcomp_err = nvcompBatchedLZ4CompressGetOutputSize(
                d_input, input_size, nvcompBatchedLZ4, d_temp, temp_size,
                &comp_out_size, d_output);
            
            if (nvcomp_err != nvcompSuccess) {
                if (d_temp) cudaFree(d_temp);
                cudaFree(d_input);
                cudaFree(d_output);
                return GPU_ERROR_NVCOMP;
            }
            
            /* 执行压缩 */
            nvcomp_err = nvcompBatchedLZ4CompressAsync(
                d_input, input_size, nvcompBatchedLZ4, d_temp, temp_size,
                d_output, &compressed_size, ctx->stream);
            
            if (d_temp) cudaFree(d_temp);
            break;
        }
        
        case COMPRESS_ALGO_ZSTD: {
            /* ZSTD压缩 */
            nvcompBatchedZSTDOpts_t zstd_opts = {nvcompBatchedZSTD};
            size_t temp_size = 0;
            
            nvcomp_err = nvcompBatchedZSTDCompressGetTempSize(
                d_input, input_size, zstd_opts, &temp_size);
            
            if (nvcomp_err != nvcompSuccess) {
                cudaFree(d_input);
                cudaFree(d_output);
                return GPU_ERROR_NVCOMP;
            }
            
            void *d_temp = NULL;
            if (temp_size > 0) {
                cuda_err = cudaMalloc(&d_temp, temp_size);
                if (cuda_err != cudaSuccess) {
                    cudaFree(d_input);
                    cudaFree(d_output);
                    return GPU_ERROR_OUT_OF_MEMORY;
                }
            }
            
            size_t comp_out_size = 0;
            nvcomp_err = nvcompBatchedZSTDCompressGetOutputSize(
                d_input, input_size, zstd_opts, d_temp, temp_size,
                &comp_out_size, d_output);
            
            if (nvcomp_err != nvcompSuccess) {
                if (d_temp) cudaFree(d_temp);
                cudaFree(d_input);
                cudaFree(d_output);
                return GPU_ERROR_NVCOMP;
            }
            
            nvcomp_err = nvcompBatchedZSTDCompressAsync(
                d_input, input_size, zstd_opts, d_temp, temp_size,
                d_output, &compressed_size, ctx->stream);
            
            if (d_temp) cudaFree(d_temp);
            break;
        }
        
        default:
            /* 默认使用LZ4 */
            cudaFree(d_input);
            cudaFree(d_output);
            return GPU_ERROR_INVALID_PARAM;
    }
    
    /* 同步流 */
    cuda_err = cudaStreamSynchronize(ctx->stream);
    if (cuda_err != cudaSuccess) {
        cudaFree(d_input);
        cudaFree(d_output);
        return GPU_ERROR_CUDA;
    }
    
    /* 检查压缩结果 */
    if (nvcomp_err != nvcompSuccess) {
        cudaFree(d_input);
        cudaFree(d_output);
        return GPU_ERROR_COMPRESS;
    }
    
    /* 复制结果回主机 */
    if (compressed_size > *output_size) {
        cudaFree(d_input);
        cudaFree(d_output);
        return GPU_ERROR_OUT_OF_MEMORY;
    }
    
    cuda_err = cudaMemcpyAsync(output, d_output, compressed_size,
                               cudaMemcpyDeviceToHost, ctx->stream);
    if (cuda_err != cudaSuccess) {
        cudaFree(d_input);
        cudaFree(d_output);
        return GPU_ERROR_CUDA;
    }
    
    cudaStreamSynchronize(ctx->stream);
    
    *output_size = compressed_size;
    
    /* 更新统计信息 */
    ctx->stats.total_bytes_in += input_size;
    ctx->stats.total_bytes_out += compressed_size;
    ctx->stats.compress_count++;
    if (ctx->stats.total_bytes_in > 0) {
        ctx->stats.avg_compress_ratio = 
            (double)ctx->stats.total_bytes_out / ctx->stats.total_bytes_in;
    }
    
    /* 清理 */
    cudaFree(d_input);
    cudaFree(d_output);
    
    return GPU_SUCCESS;
}

int gpu_compress_async(gpu_compress_ctx_t *ctx,
                       const void *input, size_t input_size,
                       void *output, size_t *output_size,
                       gpu_async_handle_t *handle) {
    /* TODO: 实现异步压缩 */
    (void)handle;
    return gpu_compress(ctx, input, input_size, output, output_size);
}

size_t gpu_compress_max_size(gpu_compress_ctx_t *ctx, size_t input_size) {
    if (!ctx) {
        return 0;
    }
    return calc_max_compressed_size(ctx->options.algo, input_size);
}

/* ============ 解压函数 ============ */

int gpu_decompress(gpu_compress_ctx_t *ctx,
                   const void *input, size_t input_size,
                   void *output, size_t *output_size) {
    if (!ctx || !ctx->initialized || !input || !output || !output_size) {
        return GPU_ERROR_INVALID_PARAM;
    }
    
    if (input_size == 0) {
        *output_size = 0;
        return GPU_SUCCESS;
    }
    
    cudaError_t cuda_err;
    nvcompStatus_t nvcomp_err;
    
    /* 分配GPU内存 */
    void *d_input = NULL;
    void *d_output = NULL;
    
    /* 假设解压后大小最多为压缩大小的10倍 */
    size_t max_decomp_size = input_size * 10;
    if (max_decomp_size > *output_size) {
        max_decomp_size = *output_size;
    }
    
    cuda_err = cudaMalloc(&d_input, input_size);
    if (cuda_err != cudaSuccess) {
        return GPU_ERROR_OUT_OF_MEMORY;
    }
    
    cuda_err = cudaMalloc(&d_output, max_decomp_size);
    if (cuda_err != cudaSuccess) {
        cudaFree(d_input);
        return GPU_ERROR_OUT_OF_MEMORY;
    }
    
    /* 复制数据到GPU */
    cuda_err = cudaMemcpyAsync(d_input, input, input_size,
                               cudaMemcpyHostToDevice, ctx->stream);
    if (cuda_err != cudaSuccess) {
        cudaFree(d_input);
        cudaFree(d_output);
        return GPU_ERROR_CUDA;
    }
    
    size_t decompressed_size = 0;
    
    switch (ctx->options.algo) {
        case COMPRESS_ALGO_LZ4: {
            /* LZ4解压 */
            size_t temp_size = 0;
            nvcomp_err = nvcompBatchedLZ4DecompressGetTempSize(
                d_input, input_size, nvcompBatchedLZ4, &temp_size);
            
            if (nvcomp_err != nvcompSuccess) {
                cudaFree(d_input);
                cudaFree(d_output);
                return GPU_ERROR_NVCOMP;
            }
            
            void *d_temp = NULL;
            if (temp_size > 0) {
                cuda_err = cudaMalloc(&d_temp, temp_size);
                if (cuda_err != cudaSuccess) {
                    cudaFree(d_input);
                    cudaFree(d_output);
                    return GPU_ERROR_OUT_OF_MEMORY;
                }
            }
            
            /* 获取解压后大小 */
            size_t decomp_out_size = 0;
            nvcomp_err = nvcompBatchedLZ4DecompressGetOutputSize(
                d_input, input_size, nvcompBatchedLZ4, d_temp, temp_size,
                &decomp_out_size, d_output, true);
            
            if (nvcomp_err != nvcompSuccess) {
                if (d_temp) cudaFree(d_temp);
                cudaFree(d_input);
                cudaFree(d_output);
                return GPU_ERROR_NVCOMP;
            }
            
            /* 执行解压 */
            nvcomp_err = nvcompBatchedLZ4DecompressAsync(
                d_input, input_size, nvcompBatchedLZ4, d_temp, temp_size,
                d_output, &decompressed_size, ctx->stream);
            
            if (d_temp) cudaFree(d_temp);
            break;
        }
        
        case COMPRESS_ALGO_ZSTD: {
            /* ZSTD解压 */
            size_t temp_size = 0;
            nvcomp_err = nvcompBatchedZSTDDecompressGetTempSize(
                d_input, input_size, &temp_size);
            
            if (nvcomp_err != nvcompSuccess) {
                cudaFree(d_input);
                cudaFree(d_output);
                return GPU_ERROR_NVCOMP;
            }
            
            void *d_temp = NULL;
            if (temp_size > 0) {
                cuda_err = cudaMalloc(&d_temp, temp_size);
                if (cuda_err != cudaSuccess) {
                    cudaFree(d_input);
                    cudaFree(d_output);
                    return GPU_ERROR_OUT_OF_MEMORY;
                }
            }
            
            size_t decomp_out_size = 0;
            nvcomp_err = nvcompBatchedZSTDDecompressGetOutputSize(
                d_input, input_size, d_temp, temp_size,
                &decomp_out_size, d_output);
            
            if (nvcomp_err != nvcompSuccess) {
                if (d_temp) cudaFree(d_temp);
                cudaFree(d_input);
                cudaFree(d_output);
                return GPU_ERROR_NVCOMP;
            }
            
            nvcomp_err = nvcompBatchedZSTDDecompressAsync(
                d_input, input_size, d_temp, temp_size,
                d_output, &decompressed_size, ctx->stream);
            
            if (d_temp) cudaFree(d_temp);
            break;
        }
        
        default:
            cudaFree(d_input);
            cudaFree(d_output);
            return GPU_ERROR_INVALID_PARAM;
    }
    
    /* 同步流 */
    cuda_err = cudaStreamSynchronize(ctx->stream);
    if (cuda_err != cudaSuccess) {
        cudaFree(d_input);
        cudaFree(d_output);
        return GPU_ERROR_CUDA;
    }
    
    /* 检查解压结果 */
    if (nvcomp_err != nvcompSuccess) {
        cudaFree(d_input);
        cudaFree(d_output);
        return GPU_ERROR_DECOMPRESS;
    }
    
    /* 复制结果回主机 */
    if (decompressed_size > *output_size) {
        cudaFree(d_input);
        cudaFree(d_output);
        return GPU_ERROR_OUT_OF_MEMORY;
    }
    
    cuda_err = cudaMemcpyAsync(output, d_output, decompressed_size,
                               cudaMemcpyDeviceToHost, ctx->stream);
    if (cuda_err != cudaSuccess) {
        cudaFree(d_input);
        cudaFree(d_output);
        return GPU_ERROR_CUDA;
    }
    
    cudaStreamSynchronize(ctx->stream);
    
    *output_size = decompressed_size;
    
    /* 更新统计信息 */
    ctx->stats.decompress_count++;
    
    /* 清理 */
    cudaFree(d_input);
    cudaFree(d_output);
    
    return GPU_SUCCESS;
}

int gpu_decompress_async(gpu_compress_ctx_t *ctx,
                         const void *input, size_t input_size,
                         void *output, size_t *output_size,
                         gpu_async_handle_t *handle) {
    /* TODO: 实现异步解压 */
    (void)handle;
    return gpu_decompress(ctx, input, input_size, output, output_size);
}

int gpu_decompress_get_size(gpu_compress_ctx_t *ctx,
                             const void *input, size_t input_size,
                             size_t *output_size) {
    if (!ctx || !input || !output_size) {
        return GPU_ERROR_INVALID_PARAM;
    }
    
    /* 从压缩数据头部读取原始大小 */
    /* nvCOMP在压缩数据中存储了原始大小 */
    /* 这里简化处理，假设解压后大小为压缩大小的10倍 */
    *output_size = input_size * 10;
    
    return GPU_SUCCESS;
}

/* ============ 统计和调试函数 ============ */

int gpu_compress_get_stats(gpu_compress_ctx_t *ctx, compress_stats_t *stats) {
    if (!ctx || !stats) {
        return GPU_ERROR_INVALID_PARAM;
    }
    
    memcpy(stats, &ctx->stats, sizeof(compress_stats_t));
    return GPU_SUCCESS;
}

int gpu_compress_reset_stats(gpu_compress_ctx_t *ctx) {
    if (!ctx) {
        return GPU_ERROR_INVALID_PARAM;
    }
    
    memset(&ctx->stats, 0, sizeof(compress_stats_t));
    return GPU_SUCCESS;
}

const char *gpu_compress_algo_name(compress_algo_t algo) {
    switch (algo) {
        case COMPRESS_ALGO_LZ4:      return "LZ4";
        case COMPRESS_ALGO_ZSTD:     return "ZSTD";
        case COMPRESS_ALGO_DEFLATE:  return "DEFLATE";
        case COMPRESS_ALGO_SNAPPY:   return "Snappy";
        case COMPRESS_ALGO_GDEFLATE: return "GDeflate";
        case COMPRESS_ALGO_CASCADED: return "Cascaded";
        case COMPRESS_ALGO_BITCOMP:  return "Bitcomp";
        default:                     return "Unknown";
    }
}

const char *gpu_compress_strerror(int error_code) {
    switch (error_code) {
        case GPU_SUCCESS:                 return "成功";
        case GPU_ERROR_INVALID_PARAM:     return "无效参数";
        case GPU_ERROR_NO_DEVICE:         return "没有可用的GPU设备";
        case GPU_ERROR_OUT_OF_MEMORY:     return "内存不足";
        case GPU_ERROR_CUDA:              return "CUDA错误";
        case GPU_ERROR_NVCOMP:            return "nvCOMP错误";
        case GPU_ERROR_COMPRESS:          return "压缩失败";
        case GPU_ERROR_DECOMPRESS:        return "解压失败";
        case GPU_ERROR_NOT_INITIALIZED:   return "未初始化";
        case GPU_ERROR_TIMEOUT:           return "操作超时";
        default:                          return "未知错误";
    }
}

/* ============ 内存管理函数 ============ */

void *gpu_malloc(size_t size) {
    void *ptr = NULL;
    cudaError_t err = cudaMalloc(&ptr, size);
    return (err == cudaSuccess) ? ptr : NULL;
}

void gpu_free(void *ptr) {
    if (ptr) {
        cudaFree(ptr);
    }
}

int gpu_memcpy_to_device(void *dst, const void *src, size_t size) {
    cudaError_t err = cudaMemcpy(dst, src, size, cudaMemcpyHostToDevice);
    return (err == cudaSuccess) ? GPU_SUCCESS : GPU_ERROR_CUDA;
}

int gpu_memcpy_to_host(void *dst, const void *src, size_t size) {
    cudaError_t err = cudaMemcpy(dst, src, size, cudaMemcpyDeviceToHost);
    return (err == cudaSuccess) ? GPU_SUCCESS : GPU_ERROR_CUDA;
}

/* ============ 批量操作函数 ============ */

int gpu_compress_batch(gpu_compress_ctx_t *ctx,
                       void **inputs, size_t *input_sizes,
                       void **outputs, size_t *output_sizes,
                       int count) {
    if (!ctx || !inputs || !input_sizes || !outputs || !output_sizes || count <= 0) {
        return GPU_ERROR_INVALID_PARAM;
    }
    
    int success_count = 0;
    for (int i = 0; i < count; i++) {
        int ret = gpu_compress(ctx, inputs[i], input_sizes[i], 
                               outputs[i], &output_sizes[i]);
        if (ret == GPU_SUCCESS) {
            success_count++;
        }
    }
    
    return success_count;
}

int gpu_decompress_batch(gpu_compress_ctx_t *ctx,
                         void **inputs, size_t *input_sizes,
                         void **outputs, size_t *output_sizes,
                         int count) {
    if (!ctx || !inputs || !input_sizes || !outputs || !output_sizes || count <= 0) {
        return GPU_ERROR_INVALID_PARAM;
    }
    
    int success_count = 0;
    for (int i = 0; i < count; i++) {
        int ret = gpu_decompress(ctx, inputs[i], input_sizes[i],
                                 outputs[i], &output_sizes[i]);
        if (ret == GPU_SUCCESS) {
            success_count++;
        }
    }
    
    return success_count;
}