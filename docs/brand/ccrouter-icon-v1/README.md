# CCRouter Icon · V1

设计依据：CCRouter 是组件化运行时与类型安全路由框架。图形以双 C 对应名称，外层表达组件边界，内层开放路径与向右箭头表达路由出口。图形寓意不作为框架架构图或 API 语义说明。

比较过的方向：节点网络容易理解，但通用性较强且缩小后细节多；R 字母标简洁，但与组件化的联系较弱；本版选择双 C + 路由箭头，兼顾名称识别与小尺寸使用。

## 资产

- `ccrouter-mark.svg`：透明底双色矢量标记，适合浅色背景。
- `ccrouter-icon-dark.svg`：深色圆角背景图标，可任意缩放。
- `ccrouter-mark-mono.svg`：深色单色标记。
- `ccrouter-mark-white.svg`：白色标记，适合深色背景。
- `ccrouter-icon-{1024,256,64,32}.png`：深色图标的 PNG 导出。
- `preview.svg` / `preview.svg.png`：设计展示板。展示板文字依赖系统字体；图标本体只有矢量路径，不依赖字体。

## 配色与使用

浅底版使用蓝色 `#4263EB` 与青绿色 `#16B8A6`；深底版使用蓝色 `#7F97FF` 与薄荷色 `#5DE4CE`，底色为 `#101A30`。单色深色为 `#17243C`。

保持正方形画布和原有比例，不单独拉伸路径。32px PNG 已实际检查；更小的 favicon 建议另做像素对齐简化版。平台启动图标应从 SVG 按目标平台规范另行导出，例如 iOS 需要不含透明通道的方形源图，不应直接使用这里的圆角 PNG。

双 C + 路由箭头方向已确认，现已接入根 README 与主 Demo 的 Android、iOS、macOS、Web、OHOS 图标。组件独立 example 保留自己的资源。

## 重新导出 Demo 图标

在 macOS 上从仓库根运行（需要 Xcode Command Line Tools）：

```bash
swift docs/brand/ccrouter-icon-v1/export-demo-icons.swift
```

脚本以 `ccrouter-icon-dark.svg` 为唯一平台图标母版，通过 AppKit 读取 SVG，再由 Core Graphics 以 sRGB 导出各尺寸 PNG；会覆盖主 Demo 对应的图标文件及本目录四个品牌预览 PNG。iOS/macOS 尺寸读取各自 `Contents.json`。iOS 使用不含透明通道的方形图，macOS 使用 86% 大小的透明留边圆角图；Android 继续使用已有 legacy launcher PNG；OHOS 使用 512px 方形图；Web maskable 版本缩小到 90%，使标记保持在中央安全圆内。Web 主题色与图标深色背景保持一致。

导出后应核对 PNG 尺寸、iOS 透明通道和 Web maskable 安全区，并在对应平台重新构建安装检查实际效果；资源检查不能代替桌面启动器验证。展示板与单色/浅色 SVG 是独立展示资产，改形状或配色时需同步维护，不由该脚本更新。

制作方式：直接绘制 SVG，使用 macOS Quick Look 渲染不透明展示板；透明图标与平台 PNG 使用 AppKit/Core Graphics 导出，避免 Quick Look 缩略图的白色底图；未调用图像生成模型。
