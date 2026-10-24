# MyFirstApp — 我的第一个 iOS 应用

一个极简 SwiftUI 应用（iOS 17+）：标题、点按计数按钮、当前日期、一句欢迎语。

## 构建

每次 push 都会触发 GitHub Actions（macOS runner）编译并发布一个**未签名** IPA 到
Release v1.0。未签名 IPA 需要自行重签后才能装到真机，例如：

- 用自己的 .p12 签名证书重签（Sideloadly / AltStore 等工具）
- 或用 SideStore 以免费 Apple ID 自签安装

Bundle ID：`com.example.myfirstapp`
