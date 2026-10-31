# 限免速查 — 我的第一个 iOS 应用

一个 SwiftUI 应用（iOS 17+），每天帮你速查 App Store 限时免费应用。

数据源是反斗限免的公开快照（https://appstore.apprcn.com/，后端
`monitor-appstore.apprcn.com/api/v1/snapshot`），只读，不登录、不采集。

## 功能

- 今日限免列表：图标、原价→免费、评分、区服（国区/美区）、平台
- 筛选：全部 / 国区 / 美区；排序：原价最高 / 评分最高 / 最新上架
- 搜索应用名或开发者；下拉刷新；离线时读上次缓存
- 左滑收藏，收藏页单独看；详情页一点就跳 App Store
- 新图标：橙粉渐变上的 ¥0 价签

## 构建

每次 push 都会触发 GitHub Actions（macOS runner）编译并发布一个**未签名** IPA 到
Release v1.2。未签名 IPA 需要自行重签后才能装到真机，例如：

- 用自己的 .p12 签名证书重签（Sideloadly / AltStore 等工具）
- 或用 SideStore 以免费 Apple ID 自签安装，或用全能签导入

Bundle ID：`com.example.myfirstapp`（沿用 v1.1，覆盖安装即可）

## 版本

- v1.2：限免速查（列表/筛选/搜索/收藏/详情 + 新图标）
- v1.1：补图标与显示名，解决全能签无法导入
- v1.0：极简计数演示
