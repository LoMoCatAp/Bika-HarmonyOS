# Bika

HarmonyOS（ArkTS / ArkUI）哔咔漫画第三方客户端。

## 特性

- **登录与资料**：邮箱+密码登录，token 持久化，自动重登；头像/昵称/等级/签名/签到
- **首页频道**：推荐、排行榜、最近更新、随机本子等 45 个频道
- **漫画详情**：详情 / 章节 / 评论三 Tab，收藏点赞，相关推荐
- **阅读器**：五种阅读模式、沉浸工具栏、横竖屏锁定、亮度调节
- **评论互动**：点赞 / 回复 / 发表，子回复展开
- **下载**：仅 WiFi 下载、并发数设置、失败重试、本地离线阅读
- **筛选与搜索**：主题/排除主题/状态/话数/页数五组筛选，关键词推荐 + 高级搜索
- **设置**：深浅色模式、沉浸光感档位、自动签到、防截屏、存储与空间管理、DNS 优化、清理图片缓存

## 构建

- DevEco Studio（HarmonyOS 6.1.1 / API 24）
- 打开工程直接构建，或：

```powershell
$env:DEVECO_SDK_HOME = "C:\Program Files\Huawei\DevEco Studio\sdk"
node "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" --mode module -p product=default -p buildMode=debug assembleHap --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-signed.hap`

## 许可

本项目基于 [GNU General Public License v3.0](LICENSE) 开源。
