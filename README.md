# WallpaperExporter

Extract **only the main artwork** from your Wallpaper Engine wallpapers into a
single flat folder — no masks, no layered parts, no clutter.

You subscribe to a wallpaper, it gets stored on disk as a `.pkg` archive plus a
bunch of layer/texture files. A normal extractor dumps *everything*: the
background, the character, the hair layers, the scrolling ribbons, the masks…
`WallpaperExporter` keeps just the full-frame artwork you'd actually want to
save or look at.

### Example

A 12-layer scene wallpaper typically produces 12+ images. WallpaperExporter
keeps the 1–4 that cover the whole frame (the background and full-canvas art):

```
Before (naive extract):  177 images across ~50 wallpapers
After  (WallpaperExporter):   ~1 image per wallpaper (full-frame art only)
```

## How it works

1. Reads each wallpaper's `scene.json` + material files to learn which textures
   it **actually references**.
2. Drops unreferenced leftovers, masks, `_depth`/`_normal` maps, and images
   smaller than 1024px on the long side.
3. Keeps layers that cover the full frame (≈16:9, or ≈9:16 for portrait,
   long side ≥ 1920px).
4. If nothing passes that test, keeps the single largest referenced image so
   every wallpaper still yields at least one picture.

Output files are named `WallpaperTitle - OriginalName.ext` and laid out flat
(no subfolders).

## Download & use

- **Windows users**: download `WallpaperExporter.exe` from the
  [Releases](../../releases) page and double-click it. RePKG is downloaded
  automatically on first run if it isn't found.
- **PowerShell users**: download `WallpaperExporter.ps1` and run
  `powershell -File WallpaperExporter.ps1`.

Paths are auto-detected (Steam library folders, RePKG, your Pictures folder).
To override any path, create `WallpaperExporter.ini` next to the exe/script:

```ini
[Paths]
Workshop=C:\...\steamapps\workshop\content\431960
Repkg=C:\...\RePKG.exe
Output=D:\...\wallpaper
```

Re-running is safe and incremental — already-exported wallpapers are skipped.
To force a full re-export, empty the output folder and delete
`%LOCALAPPDATA%\WallpaperExporter\exported_ids.txt`.

## PowerShell module (optional)

A module wrapper is provided in `module/` exposing one command:

```powershell
Import-Module ./module/WallpaperExporter.psd1
Export-WallpaperImages -Output D:\wallpapers
```

## Credits & license

- [RePKG](https://github.com/notscuffed/repkg) by NotScuffed (MIT) does the
  actual `.pkg`/`.tex` extraction. It is **not** bundled here; it is downloaded
  on first use (or provide your own copy).
- This project is released under the [MIT License](LICENSE).
- This is my first AI-assisted project.
Any feedback, suggestions and issues are welcome.

## Disclaimer

Wallpaper Engine workshop content is copyrighted by its authors. This tool is
intended **for personal backup and viewing of wallpapers you have downloaded**.
Please do not redistribute the extracted images.

---

# WallpaperExporter（中文说明）

只把 Wallpaper Engine 壁纸的**主图**提取到一个平铺文件夹，去掉蒙版、分层素材和杂项。

普通提取器会把壁纸工程里的所有贴图一股脑倒出来（背景、人物、头发分层、飘带、蒙版……）。
`WallpaperExporter` 只保留你真正想保存的全屏美术画面。

### 效果

一个 12 层的场景壁纸通常有 12+ 张图，本工具只留覆盖整个画面的 1–4 张：

```
普通提取：约 50 个壁纸 → 177 张杂图
本工具：  → 每壁纸约 1 张主图（仅全屏美术层）
```

### 工作原理

1. 读取每个壁纸的 `scene.json` + 材质文件，得知它**真正引用**了哪些贴图；
2. 丢弃未被引用的残留、蒙版、`_depth`/`_normal` 图、长边小于 1024px 的小图；
3. 保留覆盖全屏的图层（横屏 ≈16:9、竖屏 ≈9:16、长边 ≥1920px）；
4. 若一张都不剩，则保留面积最大的被引用图，保证每个壁纸至少有 1 张。

输出命名 `壁纸名 - 原文件名.ext`，平铺无子文件夹。

### 使用方法

- **Windows 用户**：从 [Releases](../../releases) 下载 `WallpaperExporter.exe` 双击运行。首次运行会自动下载 RePKG。
- **PowerShell 用户**：下载 `WallpaperExporter.ps1`，执行 `powershell -File WallpaperExporter.ps1`。

路径自动探测（Steam 库目录、RePKG、你的图片文件夹）。如需覆盖，在 exe/脚本旁新建
`WallpaperExporter.ini`：

```ini
[Paths]
Workshop=C:\...\steamapps\workshop\content\431960
Repkg=C:\...\RePKG.exe
Output=D:\...\wallpaper
```

重复运行安全且增量，已导出的壁纸自动跳过。要全量重导：清空输出文件夹并删除
`%LOCALAPPDATA%\WallpaperExporter\exported_ids.txt`。

### 可选 PowerShell 模块

`module/` 内提供了一个命令封装：

```powershell
Import-Module ./module/WallpaperExporter.psd1
Export-WallpaperImages -Output D:\wallpapers
```

### 致谢与许可

- [RePKG](https://github.com/notscuffed/repkg)（作者 NotScuffed，MIT 协议）负责实际的 `.pkg`/`.tex`
  提取，本仓库**不捆绑**它，首次使用时自动下载（也可自备一份）。
- 本项目采用 [MIT 协议](LICENSE)。
- 这是我的第一个借助AI开发的项目，欢迎提交反馈、建议与问题。

### 免责声明

Wallpaper Engine 创意工坊内容的版权归其作者所有。本工具**仅供个人备份和查看已下载壁纸**，
请勿二次分发提取出的图片。
