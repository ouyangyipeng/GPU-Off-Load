# GPU Off-Load 项目文档目录

本目录存放项目相关的所有文档。

## 文档结构

```
docs/
├── README.md           # 文档目录说明
├── introduction.md     # 项目介绍（面向新成员）
├── design.md           # 系统设计文档
├── environment.md      # 环境搭建指南
├── api.md              # API接口文档
├── test-report.md      # 测试报告模板
├── deployment.md       # 部署指南
└── third-party.md      # 第三方依赖说明
```

## 文档说明

| 文档 | 说明 | 状态 |
|------|------|------|
| [introduction.md](introduction.md) | 项目介绍、赛题解释、进度说明 | ✅ 已完成 |
| [design.md](design.md) | 系统架构设计、技术选型、模块划分 | ✅ 已完成 |
| [environment.md](environment.md) | 开发环境搭建、依赖安装 | ✅ 已完成 |
| [api.md](api.md) | 核心API接口说明 | ✅ 已完成 |
| [test-report.md](test-report.md) | 功能测试报告模板 | ✅ 已完成 |
| [deployment.md](deployment.md) | 部署和二次开发指南 | ✅ 已完成 |
| [third-party.md](third-party.md) | 第三方依赖和许可证说明 | ✅ 已完成 |

## 快速导航

### 新成员入门
1. **首先阅读** [项目介绍](introduction.md) 了解赛题和项目全貌
2. 阅读 [环境搭建指南](environment.md) 配置开发环境
3. 阅读 [部署指南](deployment.md) 了解如何部署和使用

### 开发者
1. 阅读 [设计文档](design.md) 了解系统架构
2. 参考 [API文档](api.md) 进行开发
3. 查看 [第三方依赖](third-party.md) 了解使用的库

### 测试人员
1. 参考 [测试报告模板](test-report.md) 进行测试
2. 使用 `tests/` 目录下的测试脚本

## 文档更新日志

| 日期 | 更新内容 |
|------|----------|
| 2026-03-23 | 创建所有核心文档 |
| 2026-03-23 | 新增项目介绍文档和第三方依赖说明 |