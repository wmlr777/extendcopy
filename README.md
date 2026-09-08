# ExtendCopy

ExtendCopy 是一个轻量级 macOS 菜单栏应用。它保留系统原有的 `⌘C`，同时提供 `⌘⇧C`，把当前选中的文字追加到剪贴板，而不是覆盖已有内容。

## 功能

- `⌘C`：保持系统原生复制行为
- `⌘⇧C`：追加复制当前选中的文字
- 支持换行、空行、空格和逗号四种拼接分隔符
- 菜单栏中撤销上一次追加、清空剪贴板
- 所有内容只经过 macOS 系统剪贴板，不上传网络

## 系统要求

- macOS 13 或更高版本
- Swift 6（开发构建）
- 首次使用需要开启“系统设置 → 隐私与安全性 → 辅助功能”权限，以便快捷键触发系统复制

## 构建

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./scripts/build-app.sh
```

生成的应用位于 `dist/ExtendCopy.app`。

## 使用

1. 运行 `ExtendCopy.app`，菜单栏会出现剪贴板图标。
2. 首次点击“检查辅助功能权限…”，按系统提示授权。
3. 在任意应用中选中文字，按 `⌘⇧C`。
4. 继续选择其他文字并重复按 `⌘⇧C`。
5. 用普通的 `⌘V` 一次粘贴全部累计内容。

> 当前版本专注纯文本。图片、富文本和 Finder 文件会在后续版本中处理。

## 开发

这是一个无第三方依赖的 Swift Package。可以在 Xcode 中直接打开 `Package.swift`，也可以仅使用命令行工具构建。

## License

MIT
