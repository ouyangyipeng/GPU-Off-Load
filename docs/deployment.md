# GPU Off-Load 部署指南

## 1. 快速部署

### 1.1 一键安装

```bash
# 克隆项目
git clone <repository-url>
cd GPU-Off-Load

# 运行环境搭建脚本
sudo ./scripts/setup-env.sh --all

# 编译项目
make all

# 安装
sudo make install
```

### 1.2 验证安装

```bash
# 检查内核模块
lsmod | grep dm_compress

# 检查用户空间库
ldconfig -p | grep gpucompress

# 检查GPU
nvidia-smi
```

## 2. 创建压缩块设备

### 2.1 基本用法

```bash
# 创建压缩设备
sudo dmsetup create compress_dev --table \
    "0 `blockdev --getsize /dev/nvme0n1` compress /dev/nvme0n1 65536 lz4"

# 参数说明:
# - 0: 起始扇区
# - `blockdev --getsize /dev/nvme0n1`: 设备大小（扇区数）
# - compress: 目标类型
# - /dev/nvme0n1: 底层设备
# - 65536: 分块大小（字节），必须是2的幂
# - lz4: 压缩算法（lz4/zstd/deflate）
```

### 2.2 使用压缩设备

```bash
# 查看设备
ls -la /dev/mapper/compress_dev

# 创建文件系统
sudo mkfs.xfs /dev/mapper/compress_dev

# 挂载
sudo mkdir -p /mnt/compress
sudo mount /dev/mapper/compress_dev /mnt/compress

# 使用
cd /mnt/compress
# 创建文件、运行应用等
```

### 2.3 查看设备状态

```bash
# 查看状态
sudo dmsetup status compress_dev

# 查看详细信息
sudo dmsetup table compress_dev

# 查看压缩统计
sudo dmsetup message compress_dev 0 stats
```

### 2.4 删除设备

```bash
# 卸载文件系统
sudo umount /mnt/compress

# 删除设备
sudo dmsetup remove compress_dev
```

## 3. 配置选项

### 3.1 分块大小

分块大小影响压缩效率和性能：

| 分块大小 | 压缩效率 | 性能 | 适用场景 |
|----------|----------|------|----------|
| 4KB | 低 | 高 | 小文件、随机I/O |
| 64KB | 中 | 中 | 通用场景 |
| 256KB | 高 | 中 | 大文件、顺序I/O |
| 1MB | 高 | 低 | 大文件、归档 |

### 3.2 压缩算法

| 算法 | 压缩比 | 压缩速度 | 解压速度 | 适用场景 |
|------|--------|----------|----------|----------|
| LZ4 | 中 | 极快 | 极快 | 高性能场景 |
| ZSTD | 高 | 快 | 快 | 存储优化场景 |
| DEFLATE | 高 | 中 | 中 | 兼容性要求 |

### 3.3 配置示例

```bash
# 高性能配置（适合数据库）
sudo dmsetup create db_compress --table \
    "0 `blockdev --getsize /dev/nvme0n1` compress /dev/nvme0n1 65536 lz4"

# 高压缩比配置（适合归档）
sudo dmsetup create archive_compress --table \
    "0 `blockdev --getsize /dev/sdb` compress /dev/sdb 262144 zstd"

# 平衡配置（适合通用场景）
sudo dmsetup create general_compress --table \
    "0 `blockdev --getsize /dev/nvme1n1` compress /dev/nvme1n1 131072 lz4"
```

## 4. 性能调优

### 4.1 GPU优化

```bash
# 设置GPU性能模式
sudo nvidia-smi -pm 1
sudo nvidia-smi -pl 250  # 功耗限制

# 持久化模式
sudo nvidia-smi -pm 1
```

### 4.2 内核参数调优

```bash
# 增加I/O队列深度
echo 128 | sudo tee /sys/block/nvme0n1/queue/nr_requests

# 调度器
echo none | sudo tee /sys/block/nvme0n1/queue/scheduler

# 预读
echo 256 | sudo tee /sys/block/nvme0n1/queue/read_ahead_kb
```

### 4.3 文件系统优化

```bash
# XFS优化
sudo mkfs.xfs -f -b size=64k -d su=1g,sw=4 /dev/mapper/compress_dev

# 挂载选项
sudo mount -o noatime,nodiratime,logbufs=8,logbsize=256k \
    /dev/mapper/compress_dev /mnt/compress
```

## 5. 监控和诊断

### 5.1 实时监控

```bash
# 监控GPU使用率
watch -n 1 nvidia-smi

# 监控I/O
iostat -x 1

# 监控CPU
mpstat 1

# 监控内存
free -h
```

### 5.2 性能分析

```bash
# 使用perf分析
sudo perf record -g -a sleep 10
sudo perf report

# 使用fio测试
fio --filename=/dev/mapper/compress_dev --name=test \
    --rw=randread --bs=4k --iodepth=32 --numjobs=4 \
    --time_based --runtime=60 --group_reporting
```

### 5.3 日志查看

```bash
# 内核日志
dmesg | grep -i compress

# 系统日志
journalctl -f | grep -i compress
```

## 6. 故障排除

### 6.1 设备创建失败

```bash
# 检查模块是否加载
lsmod | grep dm_compress

# 检查内核日志
dmesg | tail -20

# 检查设备是否存在
ls -la /dev/nvme0n1
```

### 6.2 性能问题

```bash
# 检查GPU是否被使用
nvidia-smi dmon -s puc

# 检查压缩统计
sudo dmsetup message compress_dev 0 stats

# 检查I/O统计
iostat -x 1 /dev/nvme0n1
```

### 6.3 数据损坏

```bash
# 卸载设备
sudo umount /mnt/compress

# 检查文件系统
sudo xfs_repair -n /dev/mapper/compress_dev

# 如果需要，重建压缩设备
sudo dmsetup remove compress_dev
# 重新创建...
```

## 7. 生产环境部署

### 7.1 系统服务配置

创建systemd服务 `/etc/systemd/system/dm-compress.service`:

```ini
[Unit]
Description=GPU Off-Load Compress Device
After=local-fs.target nvidia-persistenced.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/dm-compress-start.sh
ExecStop=/usr/local/bin/dm-compress-stop.sh

[Install]
WantedBy=multi-user.target
```

启动脚本 `/usr/local/bin/dm-compress-start.sh`:

```bash
#!/bin/bash
# 加载模块
modprobe dm_compress

# 创建压缩设备
dmsetup create compress_dev --table \
    "0 `blockdev --getsize /dev/nvme0n1` compress /dev/nvme0n1 65536 lz4"

# 挂载
mount /dev/mapper/compress_dev /mnt/compress
```

停止脚本 `/usr/local/bin/dm-compress-stop.sh`:

```bash
#!/bin/bash
# 卸载
umount /mnt/compress

# 删除设备
dmsetup remove compress_dev
```

启用服务:

```bash
chmod +x /usr/local/bin/dm-compress-*.sh
systemctl enable dm-compress.service
systemctl start dm-compress.service
```

### 7.2 监控集成

Prometheus监控指标导出:

```bash
# 安装node_exporter自定义收集器
cat > /etc/node_exporter/textfile_collector/dm_compress.prom << EOF
# HELP dm_compress_read_bytes Total bytes read
# TYPE dm_compress_read_bytes counter
dm_compress_read_bytes $(dmsetup message compress_dev 0 stats | grep read_bytes | awk '{print $2}')

# HELP dm_compress_write_bytes Total bytes written
# TYPE dm_compress_write_bytes counter
dm_compress_write_bytes $(dmsetup message compress_dev 0 stats | grep write_bytes | awk '{print $2}')

# HELP dm_compress_ratio Compression ratio
# TYPE dm_compress_ratio gauge
dm_compress_ratio $(dmsetup message compress_dev 0 stats | grep ratio | awk '{print $2}')
EOF
```

## 8. 升级和迁移

### 8.1 升级流程

```bash
# 1. 备份数据
rsync -avz /mnt/compress/ /backup/compress/

# 2. 卸载和删除设备
sudo umount /mnt/compress
sudo dmsetup remove compress_dev

# 3. 卸载旧版本
sudo make uninstall

# 4. 安装新版本
git pull
make all
sudo make install

# 5. 重新创建设备
sudo dmsetup create compress_dev --table \
    "0 `blockdev --getsize /dev/nvme0n1` compress /dev/nvme0n1 65536 lz4"

# 6. 挂载
sudo mount /dev/mapper/compress_dev /mnt/compress
```

### 8.2 数据迁移

```bash
# 从普通设备迁移到压缩设备
# 1. 创建压缩设备
sudo dmsetup create new_compress --table \
    "0 `blockdev --getsize /dev/sdb` compress /dev/sdb 65536 lz4"

# 2. 创建文件系统
sudo mkfs.xfs /dev/mapper/new_compress

# 3. 挂载
sudo mount /dev/mapper/new_compress /mnt/new_compress

# 4. 迁移数据
rsync -avz /mnt/old_data/ /mnt/new_compress/

# 5. 验证数据
diff -r /mnt/old_data/ /mnt/new_compress/
```

## 9. 安全考虑

### 9.1 访问控制

```bash
# 设置设备权限
sudo chmod 660 /dev/mapper/compress_dev
sudo chown root:disk /dev/mapper/compress_dev

# 挂载选项
sudo mount -o noexec,nosuid,nodev \
    /dev/mapper/compress_dev /mnt/compress
```

### 9.2 数据加密

可以结合dm-crypt实现加密压缩:

```bash
# 创建压缩设备
sudo dmsetup create compress_dev --table \
    "0 `blockdev --getsize /dev/nvme0n1` compress /dev/nvme0n1 65536 lz4"

# 在压缩设备上创建加密设备
sudo cryptsetup luksFormat /dev/mapper/compress_dev
sudo cryptsetup open /dev/mapper/compress_dev encrypted_dev

# 创建文件系统
sudo mkfs.xfs /dev/mapper/encrypted_dev
```

## 10. 附录

### 10.1 命令速查

| 命令 | 说明 |
|------|------|
| `dmsetup create` | 创建设备 |
| `dmsetup remove` | 删除设备 |
| `dmsetup status` | 查看状态 |
| `dmsetup table` | 查看配置 |
| `dmsetup message` | 发送消息 |
| `dmsetup targets` | 列出目标类型 |

### 10.2 配置文件

- 内核模块参数: `/etc/modprobe.d/dm-compress.conf`
- systemd服务: `/etc/systemd/system/dm-compress.service`
- 环境变量: `/etc/environment`