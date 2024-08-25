# Cloudflare DNS管理脚本

## 概述
此Bash脚本允许您管理托管在Cloudflare上的域名DNS记录。它提供查看、添加、编辑和删除DNS记录的功能。您还可以设置并保存Cloudflare API凭据以便重复使用。

## 功能
- **查看DNS记录：** 可按记录类型筛选或查看所选域名的所有记录。
- **添加DNS记录：** 轻松添加新DNS记录，支持默认值或自定义值。
- **编辑DNS记录：** 修改现有的DNS记录。
- **删除DNS记录：** 通过确认后安全删除DNS记录。
- **凭据管理：** 设置并保存API凭据到脚本中。

## 系统需求
- **Bash：** 请确保使用的是Bash shell。
- **jq：** 用于处理API响应的JSON解析器。
- **curl：** 用于发起API请求。

## 安装
脚本会自动安装`jq`和`curl`，如果系统上没有这些工具的话。它支持多种Linux发行版，包括Debian、Red Hat、Fedora和Alpine。

## 使用方法

### DNS 管理脚本

```bash
  curl -Ls https://raw.githubusercontent.com/fxxsj/Cloudflare-DNS-Management-Script/master/cf-dns-mgr.sh -o cf-dns-mgr.sh && chmod +x cf-dns-mgr.sh && ./cf-dns-mgr.sh
  
```

### DNS自动更新IP脚本

```bash
  curl -Ls https://raw.githubusercontent.com/fxxsj/Cloudflare-DNS-Management-Script/master/cf-v4-ddns.sh -o cf-v4-ddns.sh && chmod +x cf-v4-ddns.sh && ./cf-v4-ddns.sh

```
