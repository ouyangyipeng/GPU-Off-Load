#!/bin/bash
#
# GPU Off-Load 性能测试脚本
# 使用fio测试压缩块设备的性能
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 默认配置
TEST_DEVICE=${TEST_DEVICE:-/dev/nvme0n1}
TEST_DIR=${TEST_DIR:-/mnt/compress-test}
FIO_CONFIG=${FIO_CONFIG:-$(dirname $0)/../fio/compress-test.fio}
OUTPUT_DIR=${OUTPUT_DIR:-$(dirname $0)/../results}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."
    
    local missing=0
    
    if ! command -v fio &> /dev/null; then
        log_error "fio 未安装"
        missing=1
    fi
    
    if ! command -v dmsetup &> /dev/null; then
        log_error "dmsetup 未安装"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        log_error "请安装缺失的依赖"
        exit 1
    fi
    
    log_success "依赖检查通过"
}

# 创建压缩块设备
create_compress_device() {
    log_info "创建压缩块设备..."
    
    local device=$1
    local device_size=$(blockdev --getsize $device)
    local compress_dev="compress_test"
    
    # 检查设备是否已存在
    if dmsetup info $compress_dev &> /dev/null; then
        log_warn "压缩设备已存在，先移除"
        dmsetup remove $compress_dev || true
    fi
    
    # 创建压缩设备
    dmsetup create $compress_dev --table "0 $device_size compress $device 65536 lz4"
    
    if [ $? -eq 0 ]; then
        log_success "压缩设备创建成功: /dev/mapper/$compress_dev"
        echo "/dev/mapper/$compress_dev"
    else
        log_error "压缩设备创建失败"
        return 1
    fi
}

# 移除压缩块设备
remove_compress_device() {
    log_info "移除压缩块设备..."
    
    local compress_dev="compress_test"
    
    dmsetup remove $compress_dev 2>/dev/null || true
    log_success "压缩设备已移除"
}

# 运行fio测试
run_fio_test() {
    local device=$1
    local output_file=$2
    
    log_info "运行fio测试: $device"
    
    # 创建输出目录
    mkdir -p $(dirname $output_file)
    
    # 运行fio
    fio --filename=$device --output=$output_file --output-format=json $FIO_CONFIG
    
    if [ $? -eq 0 ]; then
        log_success "fio测试完成"
    else
        log_error "fio测试失败"
        return 1
    fi
}

# 分析测试结果
analyze_results() {
    local result_file=$1
    
    log_info "分析测试结果..."
    
    # 解析JSON结果
    local read_bw=$(cat $result_file | jq -r '.jobs[0].read.bw')
    local write_bw=$(cat $result_file | jq -r '.jobs[0].write.bw')
    local read_iops=$(cat $result_file | jq -r '.jobs[0].read.iops')
    local write_iops=$(cat $result_file | jq -r '.jobs[0].write.iops')
    local read_lat=$(cat $result_file | jq -r '.jobs[0].read.lat_ns.mean')
    local write_lat=$(cat $result_file | jq -r '.jobs[0].write.lat_ns.mean')
    
    echo ""
    echo "========================================"
    echo "         性能测试结果"
    echo "========================================"
    echo ""
    echo "读取性能:"
    echo "  带宽: $read_bw KB/s"
    echo "  IOPS: $read_iops"
    echo "  平均延迟: $read_lat ns"
    echo ""
    echo "写入性能:"
    echo "  带宽: $write_bw KB/s"
    echo "  IOPS: $write_iops"
    echo "  平均延迟: $write_lat ns"
    echo ""
    echo "========================================"
}

# 收集系统资源使用情况
collect_resource_usage() {
    local output_file=$1
    
    log_info "收集系统资源使用情况..."
    
    # CPU使用率
    echo "CPU使用率:" >> $output_file
    mpstat 1 5 >> $output_file 2>&1 || true
    
    # 内存使用
    echo "" >> $output_file
    echo "内存使用:" >> $output_file
    free -h >> $output_file
    
    # GPU使用率
    if command -v nvidia-smi &> /dev/null; then
        echo "" >> $output_file
        echo "GPU使用率:" >> $output_file
        nvidia-smi >> $output_file
    fi
    
    # 磁盘I/O统计
    echo "" >> $output_file
    echo "磁盘I/O统计:" >> $output_file
    iostat -x 1 5 >> $output_file 2>&1 || true
}

# 主测试流程
main() {
    echo "========================================"
    echo "  GPU Off-Load 性能测试"
    echo "========================================"
    echo ""
    
    # 检查依赖
    check_dependencies
    
    # 创建输出目录
    mkdir -p $OUTPUT_DIR
    
    # 测试原始设备性能
    log_info "测试原始设备性能..."
    run_fio_test $TEST_DEVICE $OUTPUT_DIR/baseline_${TIMESTAMP}.json
    analyze_results $OUTPUT_DIR/baseline_${TIMESTAMP}.json
    
    # 收集资源使用
    collect_resource_usage $OUTPUT_DIR/resource_baseline_${TIMESTAMP}.txt
    
    # 创建压缩设备
    COMPRESS_DEV=$(create_compress_device $TEST_DEVICE)
    
    if [ -z "$COMPRESS_DEV" ]; then
        log_error "无法创建压缩设备"
        exit 1
    fi
    
    # 等待设备就绪
    sleep 2
    
    # 测试压缩设备性能
    log_info "测试压缩设备性能..."
    run_fio_test $COMPRESS_DEV $OUTPUT_DIR/compress_${TIMESTAMP}.json
    analyze_results $OUTPUT_DIR/compress_${TIMESTAMP}.json
    
    # 收集资源使用
    collect_resource_usage $OUTPUT_DIR/resource_compress_${TIMESTAMP}.txt
    
    # 获取压缩统计
    log_info "获取压缩统计..."
    dmsetup message compress_test 0 stats > $OUTPUT_DIR/compress_stats_${TIMESTAMP}.txt 2>&1 || true
    
    # 清理
    remove_compress_device
    
    echo ""
    log_success "测试完成！结果保存在: $OUTPUT_DIR"
    echo ""
    echo "结果文件:"
    ls -la $OUTPUT_DIR/*${TIMESTAMP}*
}

# 帮助信息
print_help() {
    echo "GPU Off-Load 性能测试脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "环境变量:"
    echo "  TEST_DEVICE   测试设备（默认: /dev/nvme0n1）"
    echo "  TEST_DIR      测试目录（默认: /mnt/compress-test）"
    echo "  FIO_CONFIG    fio配置文件（默认: ../fio/compress-test.fio）"
    echo "  OUTPUT_DIR    结果输出目录（默认: ../results）"
    echo ""
    echo "示例:"
    echo "  TEST_DEVICE=/dev/sdb $0"
    echo "  $0 --help"
}

# 解析参数
case "$1" in
    --help|-h)
        print_help
        exit 0
        ;;
    *)
        main
        ;;
esac