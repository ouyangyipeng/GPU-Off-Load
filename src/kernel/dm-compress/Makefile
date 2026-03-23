# dm-compress 内核模块 Makefile
#
# 构建命令:
#   make KDIR=/path/to/kernel/source
#   或
#   make (使用当前内核)

# 模块名称
obj-m := dm_compress.o

# 源文件
dm_compress-objs := dm-compress.o

# 内核构建目录
KDIR ?= /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

# 默认目标
all: modules

# 构建模块
modules:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

# 安装模块
install:
	$(MAKE) -C $(KDIR) M=$(PWD) modules_install
	depmod -a

# 卸载模块
uninstall:
	-rmmod dm_compress 2>/dev/null || true
	-rm -f /lib/modules/$(shell uname -r)/extra/dm_compress.ko
	depmod -a

# 清理
clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	rm -f Module.symvers modules.order

# 帮助
help:
	@echo "dm-compress 内核模块构建系统"
	@echo ""
	@echo "目标:"
	@echo "  all      - 构建内核模块（默认）"
	@echo "  install  - 安装内核模块"
	@echo "  uninstall - 卸载内核模块"
	@echo "  clean    - 清理构建文件"
	@echo "  help     - 显示此帮助"
	@echo ""
	@echo "变量:"
	@echo "  KDIR     - 内核源码目录（默认: /lib/modules/\$(uname -r)/build）"
	@echo ""
	@echo "示例:"
	@echo "  make                    # 使用当前内核构建"
	@echo "  make KDIR=/path/to/src  # 指定内核源码目录"
	@echo "  sudo make install       # 安装模块"

.PHONY: all modules install uninstall clean help