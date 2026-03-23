/**
 * @file dm-compress.c
 * @brief Device Mapper压缩目标模块
 * 
 * 实现基于GPU加速的块设备透明压缩
 * 
 * Copyright (C) 2026 GPU Off-Load Project
 */

#include <linux/module.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/types.h>
#include <linux/blkdev.h>
#include <linux/bio.h>
#include <linux/vmalloc.h>
#include <linux/kthread.h>
#include <linux/workqueue.h>
#include <linux/crypto.h>
#include <linux/scatterlist.h>
#include <linux/dm-io.h>
#include <linux/device-mapper.h>

#define DM_MSG_PREFIX "compress"

/* 模块信息 */
MODULE_AUTHOR("GPU Off-Load Team");
MODULE_DESCRIPTION("Device Mapper Compression Target with GPU Acceleration");
MODULE_LICENSE("GPL");
MODULE_VERSION("1.0.0");

/* 配置参数 */
#define DEFAULT_CHUNK_SIZE (64 * 1024)  /* 64KB */
#define MIN_CHUNK_SIZE (4 * 1024)       /* 4KB */
#define MAX_CHUNK_SIZE (4 * 1024 * 1024) /* 4MB */
#define MAX_COMPRESSED_RATIO 2          /* 压缩后最大为原始的2倍 */

/* 压缩算法 */
enum compress_algo {
    COMPRESS_LZ4 = 0,
    COMPRESS_ZSTD = 1,
    COMPRESS_DEFLATE = 2,
    COMPRESS_NONE = 255,
};

/* 压缩块元数据 */
struct chunk_meta {
    uint64_t logical_block;      /* 逻辑块号 */
    uint64_t physical_block;     /* 物理块号 */
    uint32_t orig_size;          /* 原始大小 */
    uint32_t comp_size;          /* 压缩后大小 */
    uint8_t algo;                /* 压缩算法 */
    uint8_t checksum[16];        /* 校验和 */
} __packed;

/* 压缩设备结构 */
struct compress_c {
    struct dm_dev *dev;          /* 底层设备 */
    struct dm_target *ti;        /* DM目标 */
    
    /* 配置 */
    uint32_t chunk_size;         /* 分块大小 */
    uint32_t chunk_shift;        /* 分块位移 */
    enum compress_algo algo;     /* 压缩算法 */
    int compress_level;          /* 压缩级别 */
    bool use_gpu;                /* 是否使用GPU加速 */
    
    /* 统计 */
    atomic64_t read_bytes;       /* 读字节数 */
    atomic64_t write_bytes;      /* 写字节数 */
    atomic64_t compressed_bytes; /* 压缩后字节数 */
    atomic64_t read_ops;         /* 读操作数 */
    atomic64_t write_ops;        /* 写操作数 */
    
    /* 工作队列 */
    struct workqueue_struct *compress_wq;
    struct workqueue_struct *decompress_wq;
    
    /* 元数据 */
    struct chunk_meta *meta;     /* 块元数据数组 */
    uint64_t meta_size;          /* 元数据大小 */
    uint64_t total_chunks;       /* 总块数 */
    
    /* 锁 */
    spinlock_t lock;
    struct mutex meta_lock;
    
    /* GPU相关 */
    void *gpu_ctx;               /* GPU压缩上下文 */
    bool gpu_available;          /* GPU是否可用 */
};

/* 压缩工作项 */
struct compress_work {
    struct work_struct work;
    struct compress_c *cc;
    struct bio *bio;
    void *data;
    size_t data_size;
    bool is_write;
};

/* 前向声明 */
static int compress_ctr(struct dm_target *ti, unsigned int argc, char **argv);
static void compress_dtr(struct dm_target *ti);
static int compress_map(struct dm_target *ti, struct bio *bio);
static void compress_status(struct dm_target *ti, status_type_t type,
                            unsigned int status_flags, char *result, unsigned int maxlen);
static int compress_message(struct dm_target *ti, unsigned int argc, char **argv,
                            char *result, unsigned int maxlen);
static int compress_iterate_devices(struct dm_target *ti,
                                    iterate_devices_callout_fn fn, void *data);

/* DM目标注册 */
static struct target_type compress_target = {
    .name   = "compress",
    .version = {1, 0, 0},
    .module = THIS_MODULE,
    .ctr    = compress_ctr,
    .dtr    = compress_dtr,
    .map    = compress_map,
    .status = compress_status,
    .message = compress_message,
    .iterate_devices = compress_iterate_devices,
};

/* ============ 辅助函数 ============ */

/**
 * @brief 计算压缩后最大大小
 */
static size_t compress_bound(size_t src_len, enum compress_algo algo)
{
    size_t overhead;
    
    switch (algo) {
    case COMPRESS_LZ4:
        overhead = src_len / 255 + 16;
        break;
    case COMPRESS_ZSTD:
        overhead = src_len / 255 + 128;
        break;
    case COMPRESS_DEFLATE:
        overhead = src_len / 1000 + 12;
        break;
    default:
        overhead = src_len + 64;
        break;
    }
    
    return src_len + overhead;
}

/**
 * @brief 初始化GPU压缩引擎
 */
static int init_gpu_compress(struct compress_c *cc)
{
    /* TODO: 初始化GPU压缩上下文 */
    /* 这里需要调用用户空间的GPU压缩服务 */
    cc->gpu_available = false;
    cc->gpu_ctx = NULL;
    
    /* 检查GPU是否可用 */
    /* 实际实现中需要检查CUDA设备和nvCOMP库 */
    
    return 0;
}

/**
 * @brief 清理GPU压缩引擎
 */
static void cleanup_gpu_compress(struct compress_c *cc)
{
    cc->gpu_available = false;
    cc->gpu_ctx = NULL;
}

/**
 * @brief CPU压缩实现（备用方案）
 */
static int cpu_compress(const void *src, size_t src_len,
                        void *dst, size_t *dst_len,
                        enum compress_algo algo)
{
    /* 使用内核crypto API进行压缩 */
    struct crypto_comp *tfm;
    int ret;
    
    switch (algo) {
    case COMPRESS_LZ4:
        tfm = crypto_alloc_comp("lz4", 0, 0);
        break;
    case COMPRESS_ZSTD:
        tfm = crypto_alloc_comp("zstd", 0, 0);
        break;
    case COMPRESS_DEFLATE:
        tfm = crypto_alloc_comp("deflate", 0, 0);
        break;
    default:
        tfm = crypto_alloc_comp("lz4", 0, 0);
        break;
    }
    
    if (IS_ERR(tfm)) {
        DMERR("无法分配压缩变换: %ld", PTR_ERR(tfm));
        return PTR_ERR(tfm);
    }
    
    ret = crypto_comp_compress(tfm, src, src_len, dst, dst_len);
    crypto_free_comp(tfm);
    
    return ret;
}

/**
 * @brief CPU解压实现（备用方案）
 */
static int cpu_decompress(const void *src, size_t src_len,
                          void *dst, size_t *dst_len,
                          enum compress_algo algo)
{
    struct crypto_comp *tfm;
    int ret;
    
    switch (algo) {
    case COMPRESS_LZ4:
        tfm = crypto_alloc_comp("lz4", 0, 0);
        break;
    case COMPRESS_ZSTD:
        tfm = crypto_alloc_comp("zstd", 0, 0);
        break;
    case COMPRESS_DEFLATE:
        tfm = crypto_alloc_comp("deflate", 0, 0);
        break;
    default:
        tfm = crypto_alloc_comp("lz4", 0, 0);
        break;
    }
    
    if (IS_ERR(tfm)) {
        DMERR("无法分配解压变换: %ld", PTR_ERR(tfm));
        return PTR_ERR(tfm);
    }
    
    ret = crypto_comp_decompress(tfm, src, src_len, dst, dst_len);
    crypto_free_comp(tfm);
    
    return ret;
}

/**
 * @brief 压缩数据
 */
static int do_compress(struct compress_c *cc,
                       const void *src, size_t src_len,
                       void *dst, size_t *dst_len)
{
    int ret;
    
    if (cc->gpu_available && cc->gpu_ctx) {
        /* TODO: GPU压缩 */
        /* 通过ioctl调用用户空间GPU压缩服务 */
    }
    
    /* 使用CPU压缩 */
    ret = cpu_compress(src, src_len, dst, dst_len, cc->algo);
    
    return ret;
}

/**
 * @brief 解压数据
 */
static int do_decompress(struct compress_c *cc,
                         const void *src, size_t src_len,
                         void *dst, size_t *dst_len)
{
    int ret;
    
    if (cc->gpu_available && cc->gpu_ctx) {
        /* TODO: GPU解压 */
    }
    
    /* 使用CPU解压 */
    ret = cpu_decompress(src, src_len, dst, dst_len, cc->algo);
    
    return ret;
}

/* ============ DM目标函数 ============ */

/**
 * @brief 构造函数 - 创建压缩设备
 */
static int compress_ctr(struct dm_target *ti, unsigned int argc, char **argv)
{
    struct compress_c *cc;
    int ret;
    unsigned long long tmp;
    char dummy;
    
    if (argc < 1) {
        ti->error = "参数不足: 需要 <设备路径> [分块大小] [压缩算法]";
        return -EINVAL;
    }
    
    cc = kzalloc(sizeof(*cc), GFP_KERNEL);
    if (!cc) {
        ti->error = "无法分配压缩设备结构";
        return -ENOMEM;
    }
    
    ti->private = cc;
    cc->ti = ti;
    
    /* 获取底层设备 */
    ret = dm_get_device(ti, argv[0], dm_table_get_mode(ti->table), &cc->dev);
    if (ret) {
        ti->error = "无法获取设备";
        goto bad_get_dev;
    }
    
    /* 设置默认参数 */
    cc->chunk_size = DEFAULT_CHUNK_SIZE;
    cc->chunk_shift = ilog2(cc->chunk_size);
    cc->algo = COMPRESS_LZ4;
    cc->compress_level = 5;
    cc->use_gpu = true;
    
    /* 解析可选参数 */
    if (argc >= 2) {
        if (sscanf(argv[1], "%llu%c", &tmp, &dummy) != 1) {
            ti->error = "无效的分块大小";
            ret = -EINVAL;
            goto bad_parse;
        }
        
        if (tmp < MIN_CHUNK_SIZE || tmp > MAX_CHUNK_SIZE) {
            ti->error = "分块大小超出范围";
            ret = -EINVAL;
            goto bad_parse;
        }
        
        if (!is_power_of_2(tmp)) {
            ti->error = "分块大小必须是2的幂";
            ret = -EINVAL;
            goto bad_parse;
        }
        
        cc->chunk_size = tmp;
        cc->chunk_shift = ilog2(cc->chunk_size);
    }
    
    if (argc >= 3) {
        if (strcmp(argv[2], "lz4") == 0) {
            cc->algo = COMPRESS_LZ4;
        } else if (strcmp(argv[2], "zstd") == 0) {
            cc->algo = COMPRESS_ZSTD;
        } else if (strcmp(argv[2], "deflate") == 0) {
            cc->algo = COMPRESS_DEFLATE;
        } else {
            ti->error = "不支持的压缩算法";
            ret = -EINVAL;
            goto bad_parse;
        }
    }
    
    /* 计算总块数 */
    cc->total_chunks = ti->len >> cc->chunk_shift;
    if (cc->total_chunks == 0) {
        ti->error = "设备太小";
        ret = -EINVAL;
        goto bad_parse;
    }
    
    /* 分配元数据 */
    cc->meta_size = cc->total_chunks * sizeof(struct chunk_meta);
    cc->meta = vmalloc(cc->meta_size);
    if (!cc->meta) {
        ti->error = "无法分配元数据";
        ret = -ENOMEM;
        goto bad_meta;
    }
    memset(cc->meta, 0, cc->meta_size);
    
    /* 初始化锁 */
    spin_lock_init(&cc->lock);
    mutex_init(&cc->meta_lock);
    
    /* 创建工作队列 */
    cc->compress_wq = alloc_workqueue("dm-compress-wq", WQ_MEM_RECLAIM, 0);
    if (!cc->compress_wq) {
        ti->error = "无法创建工作队列";
        ret = -ENOMEM;
        goto bad_wq;
    }
    
    /* 初始化GPU压缩 */
    init_gpu_compress(cc);
    
    /* 设置目标限制 */
    ti->num_flush_bios = 1;
    ti->num_discard_bios = 1;
    ti->num_write_same_bios = 0;
    ti->num_write_zeroes_bios = 0;
    ti->per_io_data_size = sizeof(struct compress_work);
    
    DMINFO("压缩设备创建成功: chunk_size=%u, algo=%s, gpu=%s",
           cc->chunk_size,
           cc->algo == COMPRESS_LZ4 ? "lz4" : 
           cc->algo == COMPRESS_ZSTD ? "zstd" : "deflate",
           cc->gpu_available ? "yes" : "no");
    
    return 0;
    
bad_wq:
    vfree(cc->meta);
bad_meta:
bad_parse:
    dm_put_device(ti, cc->dev);
bad_get_dev:
    kfree(cc);
    return ret;
}

/**
 * @brief 析构函数 - 销毁压缩设备
 */
static void compress_dtr(struct dm_target *ti)
{
    struct compress_c *cc = ti->private;
    
    if (!cc)
        return;
    
    /* 打印统计信息 */
    DMINFO("压缩设备统计: read_bytes=%llu, write_bytes=%llu, "
           "compressed_bytes=%llu, read_ops=%llu, write_ops=%llu",
           atomic64_read(&cc->read_bytes),
           atomic64_read(&cc->write_bytes),
           atomic64_read(&cc->compressed_bytes),
           atomic64_read(&cc->read_ops),
           atomic64_read(&cc->write_ops));
    
    /* 清理GPU */
    cleanup_gpu_compress(cc);
    
    /* 销毁工作队列 */
    if (cc->compress_wq)
        destroy_workqueue(cc->compress_wq);
    
    /* 释放元数据 */
    vfree(cc->meta);
    
    /* 释放设备 */
    dm_put_device(ti, cc->dev);
    
    kfree(cc);
}

/**
 * @brief 映射函数 - 处理I/O请求
 */
static int compress_map(struct dm_target *ti, struct bio *bio)
{
    struct compress_c *cc = ti->private;
    sector_t sector = bio->bi_iter.bi_sector;
    unsigned int chunk_num;
    struct chunk_meta *meta;
    
    /* 计算块号 */
    chunk_num = sector >> (cc->chunk_shift - SECTOR_SHIFT);
    if (chunk_num >= cc->total_chunks) {
        DMERR("块号超出范围: %u >= %llu", chunk_num, cc->total_chunks);
        return DM_MAPIO_KILL;
    }
    
    meta = &cc->meta[chunk_num];
    
    /* 根据操作类型处理 */
    switch (bio_op(bio)) {
    case REQ_OP_READ:
        atomic64_add(bio->bi_iter.bi_size, &cc->read_bytes);
        atomic64_inc(&cc->read_ops);
        
        /* 检查块是否已压缩 */
        if (meta->comp_size > 0 && meta->comp_size < meta->orig_size) {
            /* 需要解压 */
            /* TODO: 实现解压逻辑 */
        }
        
        /* 重定向到底层设备 */
        bio_set_dev(bio, cc->dev->bdev);
        return DM_MAPIO_REMAPPED;
        
    case REQ_OP_WRITE:
        atomic64_add(bio->bi_iter.bi_size, &cc->write_bytes);
        atomic64_inc(&cc->write_ops);
        
        /* 压缩数据 */
        /* TODO: 实现压缩逻辑 */
        
        /* 更新统计 */
        atomic64_add(bio->bi_iter.bi_size, &cc->compressed_bytes);
        
        /* 重定向到底层设备 */
        bio_set_dev(bio, cc->dev->bdev);
        return DM_MAPIO_REMAPPED;
        
    case REQ_OP_FLUSH:
        bio_set_dev(bio, cc->dev->bdev);
        return DM_MAPIO_REMAPPED;
        
    case REQ_OP_DISARD:
        bio_set_dev(bio, cc->dev->bdev);
        return DM_MAPIO_REMAPPED;
        
    default:
        return DM_MAPIO_KILL;
    }
}

/**
 * @brief 状态函数 - 返回设备状态
 */
static void compress_status(struct dm_target *ti, status_type_t type,
                            unsigned int status_flags, char *result, unsigned int maxlen)
{
    struct compress_c *cc = ti->private;
    unsigned int sz = 0;
    
    switch (type) {
    case STATUSTYPE_INFO:
        DMEMIT("read_bytes=%llu write_bytes=%llu compressed_bytes=%llu "
               "read_ops=%llu write_ops=%llu ratio=%llu",
               atomic64_read(&cc->read_bytes),
               atomic64_read(&cc->write_bytes),
               atomic64_read(&cc->compressed_bytes),
               atomic64_read(&cc->read_ops),
               atomic64_read(&cc->write_ops),
               atomic64_read(&cc->write_bytes) > 0 ?
               atomic64_read(&cc->compressed_bytes) * 100 / 
               atomic64_read(&cc->write_bytes) : 100);
        break;
        
    case STATUSTYPE_TABLE:
        DMEMIT("%s %u %s",
               cc->dev->name,
               cc->chunk_size,
               cc->algo == COMPRESS_LZ4 ? "lz4" :
               cc->algo == COMPRESS_ZSTD ? "zstd" : "deflate");
        break;
        
    case STATUSTYPE_IMA:
        /* IMA测量 */
        break;
    }
}

/**
 * @brief 消息处理函数
 */
static int compress_message(struct dm_target *ti, unsigned int argc, char **argv,
                            char *result, unsigned int maxlen)
{
    struct compress_c *cc = ti->private;
    
    if (argc < 1) {
        DMERR("消息参数不足");
        return -EINVAL;
    }
    
    if (strcmp(argv[0], "stats") == 0) {
        snprintf(result, maxlen,
                 "read_bytes: %llu\n"
                 "write_bytes: %llu\n"
                 "compressed_bytes: %llu\n"
                 "read_ops: %llu\n"
                 "write_ops: %llu\n"
                 "compression_ratio: %llu%%\n"
                 "gpu_enabled: %s\n",
                 atomic64_read(&cc->read_bytes),
                 atomic64_read(&cc->write_bytes),
                 atomic64_read(&cc->compressed_bytes),
                 atomic64_read(&cc->read_ops),
                 atomic64_read(&cc->write_ops),
                 atomic64_read(&cc->write_bytes) > 0 ?
                 atomic64_read(&cc->compressed_bytes) * 100 / 
                 atomic64_read(&cc->write_bytes) : 100,
                 cc->gpu_available ? "yes" : "no");
        return 0;
    }
    
    if (strcmp(argv[0], "reset_stats") == 0) {
        atomic64_set(&cc->read_bytes, 0);
        atomic64_set(&cc->write_bytes, 0);
        atomic64_set(&cc->compressed_bytes, 0);
        atomic64_set(&cc->read_ops, 0);
        atomic64_set(&cc->write_ops, 0);
        return 0;
    }
    
    DMERR("未知消息: %s", argv[0]);
    return -EINVAL;
}

/**
 * @brief 迭代设备
 */
static int compress_iterate_devices(struct dm_target *ti,
                                    iterate_devices_callout_fn fn, void *data)
{
    struct compress_c *cc = ti->private;
    
    return fn(ti, cc->dev, 0, ti->len, data);
}

/* ============ 模块初始化 ============ */

static int __init dm_compress_init(void)
{
    int r;
    
    r = dm_register_target(&compress_target);
    if (r < 0) {
        DMERR("注册目标失败: %d", r);
        return r;
    }
    
    DMINFO("dm-compress 模块加载成功");
    return 0;
}

static void __exit dm_compress_exit(void)
{
    dm_unregister_target(&compress_target);
    DMINFO("dm-compress 模块卸载");
}

module_init(dm_compress_init);
module_exit(dm_compress_exit);