# Bika HarmonyOS

<p align="center">
  <img src="https://img.shields.io/badge/HarmonyOS-API%2024-0D8BFF?logo=harmonyos&logoColor=white" alt="HarmonyOS">
  <img src="https://img.shields.io/badge/ArkTS-5.0-0D8BFF" alt="ArkTS">
  <img src="https://img.shields.io/badge/ArkUI-Native-0D8BFF" alt="ArkUI">
  <img src="https://img.shields.io/badge/license-GPL--3.0-FF7CA8" alt="License">
</p>

## 声明
本仓库的所有内容仅供学习交流使用。如果您认为该内容侵犯了您的权益，请在 issue 中与我们联系，我们将立即删除相关内容。

## 简介
哔咔漫画的 HarmonyOS 第三方客户端。项目使用 ArkTS 与 ArkUI 原生构建，内置沉浸光感材质、完整阅读体验与离线下载。

## 当前功能

- 登录与资料：邮箱+密码登录，token 持久化与自动重登，头像/昵称/等级/签名/签到。
- 首页频道：推荐、排行榜、最近更新、随机本子等 45 个频道。
- 漫画详情：详情 / 章节 / 评论三 Tab，收藏点赞，相关推荐。
- 阅读器：五种阅读模式、沉浸工具栏、横竖屏锁定、亮度调节。
- 评论互动：点赞 / 回复 / 发表，子回复展开。
- 下载：仅 WiFi 下载、并发数设置、失败重试、本地离线阅读。
- 筛选与搜索：主题/排除主题/状态/话数/页数五组筛选，关键词推荐 + 高级搜索。
- 设置：深浅色模式、沉浸光感档位、自动签到、防截屏、存储与空间管理、DNS 优化、清理图片缓存。

## 致谢

本项目在实现过程中参考了以下项目，特此致谢：

- [shizq123/BIKA](https://github.com/shizq123/BIKA) — 哔咔 Android 客户端，功能与交互的主要参考。
- [raoxwup/haka_comic](https://github.com/raoxwup/haka_comic) — 请求签名与图片镜像链路的协议参考。
- [YuanChu-Tec/JMComic-HarmonyOS](https://github.com/YuanChu-Tec/JMComic-HarmonyOS) — HarmonyOS 阅读器工程结构与体验参考。
- 哔咔官方服务与国内镜像线路 — API 与图片服务来源。

## 源码运行

1. 安装 DevEco Studio，并在 SDK Manager 中安装 HarmonyOS SDK API 24 或更新版本。
2. 将 `build-profile.json5.example` 复制为本机的 `build-profile.json5`，并在 DevEco Studio 中配置自己的签名材料；该文件已被 Git 忽略。
3. 使用 DevEco Studio 打开项目根目录，选择 `entry` 模块和已连接设备或模拟器后运行。

也可以在 PowerShell 中构建：

```powershell
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
node 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js' --mode module -p product=default -p buildMode=debug assembleHap --no-daemon
```

生成的 HAP 位于 `entry/build/default/outputs/default/`。

## 隐私与数据

- 登录凭据仅保存在应用私有目录，用于访问哔咔 API。
- 头像、昵称、等级等资料由哔咔服务器提供，应用不额外收集或上传。
- 下载的漫画与图片缓存储存在应用沙箱内，卸载后随沙箱一并清除。
- 网络请求仅发往哔咔官方接口（含国内镜像线路），不包含第三方统计。

完整说明见应用内「关于 → 隐私政策」。

## 项目结构

```text
AppScope/                           应用级配置和图标资源
entry/src/main/ets/
  common/                           存储、下载、图片加载与材质兼容层
  components/                       可复用 ArkUI 组件
  models/                           领域模型与视图模型
  network/                          请求签名、直连路由与 API 服务
  pages/                            首页、详情、阅读器、搜索等页面
entry/src/main/resources/           字符串、颜色和主题资源
```

## 反馈

- 项目仓库：[LoMoCatAp/Bika-HarmonyOS](https://github.com/LoMoCatAp/Bika-HarmonyOS)
- 问题反馈：[GitHub Issues](https://github.com/LoMoCatAp/Bika-HarmonyOS/issues)

## License

本项目基于 [GNU General Public License v3.0](LICENSE) 开源。
