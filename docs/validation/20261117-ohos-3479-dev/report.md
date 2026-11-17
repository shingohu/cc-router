# OHOS oh-3.47.9-dev 兼容性验证

日期：2026-11-17。CCRouter 源码：`156ff7cbe634ffbbad56f6b2d8c25c5bda393cd5`。
所有解算、生成、测试与 HAP 构建均在该提交的干净临时副本执行，当前分支继续固定标准 SDK。

## 结论与 SDK 身份

**当前代码与这个固定修订的 OHOS 开发 SDK 条件兼容，可用于联调；不构成稳定 OHOS
3.47.9 或完整真机功能认证。** 无需修改框架源码、manifest 约束或依赖 lockfile。

| 项目 | 实测值 |
| --- | --- |
| FVM 安装别名 / Git 分支 | `ohos/oh-3.47.9-dev` / `oh-3.47.9-dev` |
| 官方仓库 | `https://gitcode.com/CPF-Flutter/flutter_flutter.git` |
| Framework 修订 | `a9e95461918a678c15d8ba80cdddb85b274cf1ce` |
| 修复版本识别后的自报版本 | `3.47.7+ohos-0.0.1-canary` |
| Dart / DevTools | `3.13.5` / `2.60.0` |
| Flutter / Flutter Test 的 meta 约束 | `^1.18.3` |
| OHOS engine / HAR 修订 | `aee5c121eb902bf3346d2efc9bf5abbe8afe41f6` / `8750288ade519f7456277d7dc94cf76b13f18739` |
| 本机 HarmonyOS 工具链 | DevEco SDK API 26、ohpm、hvigorw 可用 |

安装别名中的 3.47.9 不能替代实际版本和修订。当前 tag 元数据仍为 canary，本次只认证表中
固定修订与当前源码的组合。SDK 详细信息与产物指纹见 [manifest.json](manifest.json)。

## 原样安装失败与版本识别修复

原样安装为 depth=1 的浅克隆，本地没有版本 tag，`flutter --version --machine` 报
`0.0.0-unknown`。第一次 Pub 因 `webview_flutter 4.14.1` 要求 Flutter `>=3.38.0` 而失败。
这次阻断来自 SDK 版本元数据；旧 OHOS SDK 的 meta 1.17.0 冲突已经不适用于该修订。

从官方远端补取以下真实标签及必要祖先历史后，版本恢复识别，Pub 成功：

```sh
git -C <ohos-sdk> fetch --deepen=200 origin oh-3.47.9-dev \
  tag 3.47.7+ohos-0.0.1-canary tag 3.47.7+ohos-0.0.1-pre
<ohos-sdk>/bin/flutter --version --machine
```

SDK 的 HEAD 始终为 `a9e95461`，受版本控制的源文件保持干净。版本修复依据官方标签和
真实祖先关系，未切换 SDK 代码修订。版本识别修复仅涉及 Git 历史/tag 与版本缓存；
测试另按 SDK 正常流程下载构建缓存。
所有测试显式使用该 SDK 的 Flutter、Dart 和 `FLUTTER_ROOT`，没有混用全局旧 SDK。

- [原始 Pub 失败](pub.log) / [官方标签查询](remote-tags.log) / [fetch 记录](sdk-tags-fetch.log)
- [版本识别恢复后的 Pub](pub-resolved.log)

## 本轮新执行结果

| 验证 | 结果 |
| --- | --- |
| Workspace Pub / packages 分析 | 成功，无需改依赖约束或 overrides |
| Framework VM 全量 | **1719 项通过** |
| Demo 全目录 | **188 项通过** |
| 原标准 SDK Portable State | `toolMismatch`，按设计严格拒绝 |
| OHOS SDK 的 portable prepare | 成功，生成 9 份当前 SDK 状态 |
| Demo / 独立 Order Example 生成与 no-cache check | 全部成功 |
| Host / Order Package portable publish | 全部成功 |
| 独立 Plugin | Pub、analyze、真实 LSP UI-only 专项 **1 项通过** |
| Hvigor preflight 对应函数 | 显式调用成功，使用 OHOS SDK 自带的 Dart |
| OHOS Debug HAP | 未签名构建成功 |
| OHOS Release HAP | 未签名 AOT 构建成功，产物包含 `libflutter.so` 与 `libapp.so` |

本轮没有运行整个 Generator 目录或 Plugin 全量 215 项，也没有将标准 SDK 的历史数字当作
OHOS 新执行结果。Framework/Demo 测试在 macOS 主机运行，不等同于 HarmonyOS 真机运行。

关键证据：[Framework 摘录](framework-summary.log)、[Demo 摘录](demo-summary.log)、
[生成](prepare.log)、[Host check](host-check.log)、[Example check](example-check.log)、
[Plugin LSP](plugin-lsp.log)、[Hvigor preflight](hvigor-preflight.log)、
[Debug HAP](hap-debug.log)、[Release HAP](hap-release.log)。完整命令与退出码见
[results.json](results.json)。

Release 未签名 HAP 为 26,372,443 bytes，SHA-256：
`fceab01ff2266c2630b8704aa04b9ed5a2219af4084edb87db705eb77428f434`。
编译产物保留在仓库外临时副本，未提交 HAP、SDK、Pub cache 或签名材料。

## 使用边界与建议

1. **预生成组件不能直接混用。** 标准 SDK 使用 Dart 3.13.7，本 OHOS SDK 使用 3.13.5。
   Portable 工具身份因此不同；初次 `portable publish demo` 实测被拒绝，重新 prepare 后
   才通过。对 Git/Pub 只读组件，应先由对应工具链重新生成并分发，不能靠 `--no-cache`
   绕过。不要将本轮 OHOS 状态直接覆盖当前分支的标准 SDK 状态。
2. **框架源码和生成 Dart 输出可复用。** 构建后与提交逐文件比较，仅 9 份 Portable State
   不同；全部其他受版本控制的源码、Dart 生成物、manifest 和 lockfile 字节一致。
   对照见 [state-differences.json](state-differences.json)。
3. **Demo 原生插件仍缺 OHOS 实现。** 当前解析的 OHOS plugin 列表为空，生成的
   `GeneratedPluginRegistrant.ets` 没有插件注册。所用 `app_links 7.0.0` 和
   `webview_flutter 4.14.1` 未声明 OHOS 平台，Deep Link / WebView 的原生功能尚未验收。
   这些实现属于 Host/应用平台集成，应单独选择、适配和验证，不能通过 HAP 编译推断可用。
4. **没有 HarmonyOS 真机。** 本轮未签名、安装或运行 HAP，未验证系统返回、Deep Link、
   WebView、窗口/生命周期、Hot Reload 或原生内存行为；实际 IDE Plugin 会话也未验收。

推荐保持标准 `3.47.9` 为当前分支默认，将 `oh-3.47.9-dev@a9e95461` 列为开发验证矩阵。
OHOS 使用独立工作区、对应 SDK 和独立生成状态；在官方稳定身份、原生插件和真机验收
闭环前，继续保留旧主分支与现代工具链分支的维护边界。
