# dm-compress-tool Makefile

# 项目根目录
PROJECT_ROOT ?= ../..

# 编译器
CC := gcc

# 编译选项
CFLAGS := -Wall -Wextra -O2
CFLAGS += -I$(PROJECT_ROOT)/include
CFLAGS += -D_GNU_SOURCE

# 链接选项
LDFLAGS := -ldevmapper

# 源文件
SRCS := dm-compress-tool.c
OBJS := $(SRCS:.c=.o)

# 目标
TARGET := dm-compress-tool

# 默认目标
.PHONY: all
all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

# 安装
.PHONY: install
install: $(TARGET)
	install -d $(DESTDIR)/usr/local/bin
	install -m 755 $(TARGET) $(DESTDIR)/usr/local/bin/

# 清理
.PHONY: clean
clean:
	rm -f $(OBJS) $(TARGET)

# 帮助
.PHONY: help
help:
	@echo "dm-compress-tool 构建系统"
	@echo ""
	@echo "目标:"
	@echo "  all     - 构建工具（默认）"
	@echo "  install - 安装工具"
	@echo "  clean   - 清理构建文件"
	@echo "  help    - 显示此帮助"