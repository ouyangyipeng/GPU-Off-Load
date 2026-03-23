/**
 * @file dm-compress-tool.c
 * @brief GPU Off-Load 管理工具
 * 
 * 用于创建、管理和监控GPU压缩块设备
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <libdevmapper.h>

/* 版本信息 */
#define VERSION "1.0.0"
#define TOOL_NAME "dm-compress-tool"

/* 默认配置 */
#define DEFAULT_CHUNK_SIZE "65536"
#define DEFAULT_ALGO "lz4"

/* 颜色定义 */
#define RED     "\033[0;31m"
#define GREEN   "\033[0;32m"
#define YELLOW  "\033[1;33m"
#define BLUE    "\033[0;34m"
#define NC      "\033[0m"

/* 日志函数 */
#define log_info(fmt, ...)  printf(BLUE "[INFO]" NC " " fmt "\n", ##__VA_ARGS__)
#define log_success(fmt, ...) printf(GREEN "[SUCCESS]" NC " " fmt "\n", ##__VA_ARGS__)
#define log_warn(fmt, ...)  printf(YELLOW "[WARN]" NC " " fmt "\n", ##__VA_ARGS__)
#define log_error(fmt, ...) fprintf(stderr, RED "[ERROR]" NC " " fmt "\n", ##__VA_ARGS__)

/* 压缩算法列表 */
static const char *algorithms[] = {
    "lz4",
    "zstd",
    "deflate",
    NULL
};

/* 设备信息结构 */
struct device_info {
    char name[256];
    char backing_dev[256];
    uint64_t size;
    uint32_t chunk_size;
    char algo[32];
    uint64_t read_bytes;
    uint64_t write_bytes;
    uint64_t compressed_bytes;
    uint64_t read_ops;
    uint64_t write_ops;
    double compression_ratio;
    int gpu_enabled;
};

/* 前向声明 */
static int cmd_create(int argc, char **argv);
static int cmd_remove(int argc, char **argv);
static int cmd_list(int argc, char **argv);
static int cmd_status(int argc, char **argv);
static int cmd_stats(int argc, char **argv);
static int cmd_reset(int argc, char **argv);
static int cmd_help(int argc, char **argv);

/* 命令结构 */
struct command {
    const char *name;
    const char *desc;
    int (*fn)(int argc, char **argv);
};

static struct command commands[] = {
    {"create", "创建压缩块设备", cmd_create},
    {"remove", "删除压缩块设备", cmd_remove},
    {"list",   "列出所有压缩设备", cmd_list},
    {"status", "显示设备状态", cmd_status},
    {"stats",  "显示压缩统计", cmd_stats},
    {"reset",  "重置统计信息", cmd_reset},
    {"help",   "显示帮助信息", cmd_help},
    {NULL, NULL, NULL}
};

/* ============ 辅助函数 ============ */

/**
 * @brief 检查设备是否存在
 */
static int device_exists(const char *dev_path) {
    struct stat st;
    return (stat(dev_path, &st) == 0 && S_ISBLK(st.st_mode));
}

/**
 * @brief 获取设备大小（扇区数）
 */
static uint64_t get_device_size(const char *dev_path) {
    int fd;
    uint64_t size;
    
    fd = open(dev_path, O_RDONLY);
    if (fd < 0) {
        return 0;
    }
    
    if (ioctl(fd, BLKGETSIZE, &size) < 0) {
        close(fd);
        return 0;
    }
    
    close(fd);
    return size;
}

/**
 * @brief 验证压缩算法
 */
static int validate_algo(const char *algo) {
    for (int i = 0; algorithms[i]; i++) {
        if (strcmp(algo, algorithms[i]) == 0) {
            return 1;
        }
    }
    return 0;
}

/**
 * @brief 检查dm-compress模块是否加载
 */
static int check_module_loaded(void) {
    FILE *fp;
    char line[256];
    int found = 0;
    
    fp = fopen("/proc/modules", "r");
    if (!fp) {
        return 0;
    }
    
    while (fgets(line, sizeof(line), fp)) {
        if (strncmp(line, "dm_compress", 11) == 0) {
            found = 1;
            break;
        }
    }
    
    fclose(fp);
    return found;
}

/* ============ 命令实现 ============ */

/**
 * @brief 创建压缩设备
 */
static int cmd_create(int argc, char **argv) {
    static struct option long_options[] = {
        {"device",    required_argument, 0, 'd'},
        {"name",      required_argument, 0, 'n'},
        {"chunk-size", required_argument, 0, 'c'},
        {"algo",      required_argument, 0, 'a'},
        {"help",      no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };
    
    char *device = NULL;
    char *name = NULL;
    char *chunk_size = DEFAULT_CHUNK_SIZE;
    char *algo = DEFAULT_ALGO;
    
    int opt;
    while ((opt = getopt_long(argc, argv, "d:n:c:a:h", long_options, NULL)) != -1) {
        switch (opt) {
        case 'd':
            device = optarg;
            break;
        case 'n':
            name = optarg;
            break;
        case 'c':
            chunk_size = optarg;
            break;
        case 'a':
            algo = optarg;
            break;
        case 'h':
            printf("用法: %s create -d <设备> -n <名称> [-c <分块大小>] [-a <算法>]\n", TOOL_NAME);
            printf("\n选项:\n");
            printf("  -d, --device <设备>      底层块设备路径\n");
            printf("  -n, --name <名称>        压缩设备名称\n");
            printf("  -c, --chunk-size <大小>  分块大小（字节，默认65536）\n");
            printf("  -a, --algo <算法>        压缩算法（lz4/zstd/deflate，默认lz4）\n");
            printf("  -h, --help               显示此帮助\n");
            printf("\n示例:\n");
            printf("  %s create -d /dev/nvme0n1 -n compress_dev\n", TOOL_NAME);
            printf("  %s create -d /dev/sdb -n archive -c 262144 -a zstd\n", TOOL_NAME);
            return 0;
        default:
            return 1;
        }
    }
    
    /* 验证参数 */
    if (!device) {
        log_error("必须指定底层设备");
        return 1;
    }
    
    if (!name) {
        log_error("必须指定设备名称");
        return 1;
    }
    
    if (!device_exists(device)) {
        log_error("设备不存在: %s", device);
        return 1;
    }
    
    if (!validate_algo(algo)) {
        log_error("不支持的压缩算法: %s", algo);
        log_info("支持的算法: lz4, zstd, deflate");
        return 1;
    }
    
    /* 检查模块 */
    if (!check_module_loaded()) {
        log_warn("dm_compress模块未加载，尝试加载...");
        if (system("modprobe dm_compress") != 0) {
            log_error("无法加载dm_compress模块");
            return 1;
        }
    }
    
    /* 获取设备大小 */
    uint64_t size = get_device_size(device);
    if (size == 0) {
        log_error("无法获取设备大小");
        return 1;
    }
    
    /* 构建DM表 */
    char table[1024];
    snprintf(table, sizeof(table), "0 %lu compress %s %s %s",
             size, device, chunk_size, algo);
    
    /* 使用dmsetup创建设备 */
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "dmsetup create %s --table \"%s\"", name, table);
    
    log_info("创建压缩设备: %s", name);
    log_info("  底层设备: %s", device);
    log_info("  分块大小: %s 字节", chunk_size);
    log_info("  压缩算法: %s", algo);
    
    int ret = system(cmd);
    if (ret != 0) {
        log_error("创建设备失败");
        return 1;
    }
    
    log_success("设备创建成功: /dev/mapper/%s", name);
    return 0;
}

/**
 * @brief 删除压缩设备
 */
static int cmd_remove(int argc, char **argv) {
    static struct option long_options[] = {
        {"name", required_argument, 0, 'n'},
        {"help", no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };
    
    char *name = NULL;
    
    int opt;
    while ((opt = getopt_long(argc, argv, "n:h", long_options, NULL)) != -1) {
        switch (opt) {
        case 'n':
            name = optarg;
            break;
        case 'h':
            printf("用法: %s remove -n <名称>\n", TOOL_NAME);
            printf("\n选项:\n");
            printf("  -n, --name <名称>  压缩设备名称\n");
            printf("  -h, --help         显示此帮助\n");
            return 0;
        default:
            return 1;
        }
    }
    
    if (!name) {
        log_error("必须指定设备名称");
        return 1;
    }
    
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "dmsetup remove %s", name);
    
    log_info("删除设备: %s", name);
    int ret = system(cmd);
    if (ret != 0) {
        log_error("删除设备失败");
        return 1;
    }
    
    log_success("设备已删除");
    return 0;
}

/**
 * @brief 列出所有压缩设备
 */
static int cmd_list(int argc, char **argv) {
    (void)argc;
    (void)argv;
    
    /* 使用dmsetup列出设备 */
    FILE *fp;
    char line[256];
    int found = 0;
    
    fp = popen("dmsetup ls --target compress", "r");
    if (!fp) {
        log_error("无法获取设备列表");
        return 1;
    }
    
    printf("\n%-20s %-20s\n", "设备名称", "状态");
    printf("----------------------------------------\n");
    
    while (fgets(line, sizeof(line), fp)) {
        char name[128], status[32];
        if (sscanf(line, "%127s\t%31s", name, status) >= 1) {
            printf("%-20s %-20s\n", name, status);
            found = 1;
        }
    }
    
    pclose(fp);
    
    if (!found) {
        printf("没有找到压缩设备\n");
    }
    
    return 0;
}

/**
 * @brief 显示设备状态
 */
static int cmd_status(int argc, char **argv) {
    static struct option long_options[] = {
        {"name", required_argument, 0, 'n'},
        {"help", no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };
    
    char *name = NULL;
    
    int opt;
    while ((opt = getopt_long(argc, argv, "n:h", long_options, NULL)) != -1) {
        switch (opt) {
        case 'n':
            name = optarg;
            break;
        case 'h':
            printf("用法: %s status -n <名称>\n", TOOL_NAME);
            return 0;
        default:
            return 1;
        }
    }
    
    if (!name) {
        log_error("必须指定设备名称");
        return 1;
    }
    
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "dmsetup status %s", name);
    
    return system(cmd);
}

/**
 * @brief 显示压缩统计
 */
static int cmd_stats(int argc, char **argv) {
    static struct option long_options[] = {
        {"name", required_argument, 0, 'n'},
        {"help", no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };
    
    char *name = NULL;
    
    int opt;
    while ((opt = getopt_long(argc, argv, "n:h", long_options, NULL)) != -1) {
        switch (opt) {
        case 'n':
            name = optarg;
            break;
        case 'h':
            printf("用法: %s stats -n <名称>\n", TOOL_NAME);
            return 0;
        default:
            return 1;
        }
    }
    
    if (!name) {
        log_error("必须指定设备名称");
        return 1;
    }
    
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "dmsetup message %s 0 stats", name);
    
    return system(cmd);
}

/**
 * @brief 重置统计信息
 */
static int cmd_reset(int argc, char **argv) {
    static struct option long_options[] = {
        {"name", required_argument, 0, 'n'},
        {"help", no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };
    
    char *name = NULL;
    
    int opt;
    while ((opt = getopt_long(argc, argv, "n:h", long_options, NULL)) != -1) {
        switch (opt) {
        case 'n':
            name = optarg;
            break;
        case 'h':
            printf("用法: %s reset -n <名称>\n", TOOL_NAME);
            return 0;
        default:
            return 1;
        }
    }
    
    if (!name) {
        log_error("必须指定设备名称");
        return 1;
    }
    
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "dmsetup message %s 0 reset_stats", name);
    
    log_info("重置统计: %s", name);
    int ret = system(cmd);
    if (ret == 0) {
        log_success("统计已重置");
    }
    
    return ret;
}

/**
 * @brief 显示帮助信息
 */
static int cmd_help(int argc, char **argv) {
    (void)argc;
    (void)argv;
    
    printf("\n%s v%s - GPU Off-Load 管理工具\n\n", TOOL_NAME, VERSION);
    printf("用法: %s <命令> [选项]\n\n", TOOL_NAME);
    printf("命令:\n");
    
    for (int i = 0; commands[i].name; i++) {
        printf("  %-10s %s\n", commands[i].name, commands[i].desc);
    }
    
    printf("\n选项:\n");
    printf("  -h, --help     显示帮助信息\n");
    printf("  -v, --version  显示版本信息\n");
    
    printf("\n示例:\n");
    printf("  %s create -d /dev/nvme0n1 -n compress_dev\n", TOOL_NAME);
    printf("  %s list\n", TOOL_NAME);
    printf("  %s stats -n compress_dev\n", TOOL_NAME);
    printf("  %s remove -n compress_dev\n", TOOL_NAME);
    
    printf("\n更多信息请参考: docs/deployment.md\n");
    
    return 0;
}

/* ============ 主函数 ============ */

int main(int argc, char **argv) {
    if (argc < 2) {
        cmd_help(0, NULL);
        return 1;
    }
    
    /* 版本选项 */
    if (strcmp(argv[1], "-v") == 0 || strcmp(argv[1], "--version") == 0) {
        printf("%s v%s\n", TOOL_NAME, VERSION);
        return 0;
    }
    
    /* 查找命令 */
    for (int i = 0; commands[i].name; i++) {
        if (strcmp(argv[1], commands[i].name) == 0) {
            return commands[i].fn(argc - 1, argv + 1);
        }
    }
    
    log_error("未知命令: %s", argv[1]);
    log_info("使用 '%s help' 查看帮助", TOOL_NAME);
    
    return 1;
}