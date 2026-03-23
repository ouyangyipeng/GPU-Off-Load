# GPU压缩引擎 Makefile

# 项目根目录
PROJECT_ROOT ?= ../..
CUDA_PATH ?= /usr/local/cuda

# 编译器
NVCC := $(CUDA_PATH)/bin/nvcc
CC := gcc

# 编译选项
NVCC_FLAGS := -O3 -arch=sm_75 -std=c++14
NVCC_FLAGS += -I$(PROJECT_ROOT)/include
NVCC_FLAGS += -I$(CUDA_PATH)/include

# 链接选项
LDFLAGS := -L$(CUDA_PATH)/lib64
LDFLAGS += -lcuda -lcudart -lnvcomp

# 源文件
SRCS := gpu_compress.cu
OBJS := $(SRCS:.cu=.o)

# 目标
TARGET := libgpucompress.so
TEST_TARGET := test_gpu_compress

# 默认目标
.PHONY: all
all: $(TARGET)

# 编译共享库
$(TARGET): $(OBJS)
	$(NVCC) -shared -o $@ $^ $(LDFLAGS)

# 编译目标文件
%.o: %.cu
	$(NVCC) $(NVCC_FLAGS) -c -o $@ $<

# 编译测试程序
.PHONY: test
test: $(TEST_TARGET)

$(TEST_TARGET): test_gpu_compress.cu $(TARGET)
	$(NVCC) $(NVCC_FLAGS) -o $@ test_gpu_compress.cu -L. -lgpucompress $(LDFLAGS)

# 安装
.PHONY: install
install: $(TARGET)
	install -d $(DESTDIR)/usr/local/lib
	install -d $(DESTDIR)/usr/local/include
	install -m 755 $(TARGET) $(DESTDIR)/usr/local/lib/
	install -m 644 $(PROJECT_ROOT)/include/gpu_compress.h $(DESTDIR)/usr/local/include/
	ldconfig

# 清理
.PHONY: clean
clean:
	rm -f $(OBJS) $(TARGET) $(TEST_TARGET)

# 帮助
.PHONY: help
help:
	@echo "GPU压缩引擎构建系统"
	@echo ""
	@echo "目标:"
	@echo "  all     - 构建共享库（默认）"
	@echo "  test    - 构建测试程序"
	@echo "  install - 安装共享库"
	@echo "  clean   - 清理构建文件"
	@echo "  help    - 显示此帮助"