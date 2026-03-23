# GPU Off-Load 顶层 Makefile
# 用于构建所有组件

# 项目根目录
PROJECT_ROOT := $(shell pwd)

# 构建目录
BUILD_DIR := $(PROJECT_ROOT)/build

# 源代码目录
SRC_DIR := $(PROJECT_ROOT)/src
KERNEL_DIR := $(SRC_DIR)/kernel
USER_DIR := $(SRC_DIR)/user
LIB_DIR := $(SRC_DIR)/lib

# 内核版本
KVER ?= $(shell uname -r)
KDIR := /lib/modules/$(KVER)/build

# CUDA路径
CUDA_PATH ?= /usr/local/cuda
CUDA_INCLUDE := $(CUDA_PATH)/include
CUDA_LIB := $(CUDA_PATH)/lib64

# 编译器设置
CC := gcc
NVCC := $(CUDA_PATH)/bin/nvcc
CFLAGS := -Wall -Wextra -O2 -I$(PROJECT_ROOT)/include
CUDA_FLAGS := -O3 -arch=sm_75 -I$(CUDA_INCLUDE)
LDFLAGS := -L$(CUDA_LIB) -lcuda -lcudart

# 目标
.PHONY: all clean install uninstall help

all: user lib kernel

# 用户空间工具
.PHONY: user
user:
	@echo "构建用户空间工具..."
	$(MAKE) -C $(USER_DIR)/gpu-compress PROJECT_ROOT=$(PROJECT_ROOT) CUDA_PATH=$(CUDA_PATH)
	$(MAKE) -C $(USER_DIR)/tools PROJECT_ROOT=$(PROJECT_ROOT)

# 共享库
.PHONY: lib
lib:
	@echo "构建共享库..."
	$(MAKE) -C $(LIB_DIR) PROJECT_ROOT=$(PROJECT_ROOT) CUDA_PATH=$(CUDA_PATH)

# 内核模块
.PHONY: kernel
kernel:
	@echo "构建内核模块..."
	$(MAKE) -C $(KERNEL_DIR)/dm-compress KDIR=$(KDIR) PWD=$(KERNEL_DIR)/dm-compress

# 安装
.PHONY: install
install: install-lib install-user install-kernel
	@echo "安装完成"

.PHONY: install-user
install-user:
	@echo "安装用户空间工具..."
	$(MAKE) -C $(USER_DIR)/gpu-compress install
	$(MAKE) -C $(USER_DIR)/tools install

.PHONY: install-lib
install-lib:
	@echo "安装共享库..."
	$(MAKE) -C $(LIB_DIR) install

.PHONY: install-kernel
install-kernel:
	@echo "安装内核模块..."
	$(MAKE) -C $(KERNEL_DIR)/dm-compress install

# 卸载
.PHONY: uninstall
uninstall: uninstall-kernel uninstall-user uninstall-lib
	@echo "卸载完成"

.PHONY: uninstall-kernel
uninstall-kernel:
	@echo "卸载内核模块..."
	-sudo rmmod dm_compress 2>/dev/null || true
	-sudo rm -f /lib/modules/$(KVER)/extra/dm_compress.ko

.PHONY: uninstall-user
uninstall-user:
	@echo "卸载用户空间工具..."
	-sudo rm -f /usr/local/bin/gpu-compress
	-sudo rm -f /usr/local/bin/dm-compress-tool

.PHONY: uninstall-lib
uninstall-lib:
	@echo "卸载共享库..."
	-sudo rm -f /usr/local/lib/libgpucompress.so*
	-sudo ldconfig

# 清理
.PHONY: clean
clean: clean-user clean-lib clean-kernel
	@echo "清理完成"

.PHONY: clean-user
clean-user:
	$(MAKE) -C $(USER_DIR)/gpu-compress clean
	$(MAKE) -C $(USER_DIR)/tools clean

.PHONY: clean-lib
clean-lib:
	$(MAKE) -C $(LIB_DIR) clean

.PHONY: clean-kernel
clean-kernel:
	$(MAKE) -C $(KERNEL_DIR)/dm-compress clean

# 测试
.PHONY: test
test:
	@echo "运行测试..."
	$(PROJECT_ROOT)/tests/scripts/run-tests.sh

# 性能测试
.PHONY: perf-test
perf-test:
	@echo "运行性能测试..."
	$(PROJECT_ROOT)/tests/scripts/run-fio-test.sh

# 帮助
.PHONY: help
help:
	@echo "GPU Off-Load 构建系统"
	@echo ""
	@echo "用法: make [目标]"
	@echo ""
	@echo "目标:"
	@echo "  all          构建所有组件（默认）"
	@echo "  user         仅构建用户空间工具"
	@echo "  lib          仅构建共享库"
	@echo "  kernel       仅构建内核模块"
	@echo "  install      安装所有组件"
	@echo "  uninstall    卸载所有组件"
	@echo "  clean        清理构建文件"
	@echo "  test         运行测试"
	@echo "  perf-test    运行性能测试"
	@echo "  help         显示此帮助信息"
	@echo ""
	@echo "变量:"
	@echo "  KVER         内核版本（默认: 当前内核）"
	@echo "  CUDA_PATH    CUDA安装路径（默认: /usr/local/cuda）"
	@echo ""
	@echo "示例:"
	@echo "  make                    # 构建所有组件"
	@echo "  make KVER=5.15.0       # 指定内核版本构建"
	@echo "  make install            # 安装所有组件"
	@echo "  make clean              # 清理构建文件"