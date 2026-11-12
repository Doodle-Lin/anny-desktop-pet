# Anny Desktop Pet

Anny 的 Windows 独立桌宠。离线运行，无需 Codex 或账号。

![日常与悬停界面](docs/ui-preview.png)

## 使用

从 [Releases](../../releases) 下载便携包，解压后双击 `AnnyDesktop.exe`，保留同目录的 `assets` 文件夹。需要 Windows 和 .NET Framework 4.x。

- 平时只显示狗狗；悬停显示像素风姓名、状态和互动卡片，移开自动收起。
- 拖动狗狗移动位置，单击摸摸；右键菜单和托盘提供更多操作。
- 喂食连续吃四口（约 3.2 秒），饱食度增加一次；支持睡觉与唤醒。
- 自主走动、十六方向注视和多组动作；睡眠帧对齐中心及落地点。
- 逐像素透明窗口，保留毛发透明边缘。

饱食、心情、精力保存在 `%LOCALAPPDATA%\AnnyDesktop\state.txt`。位置、菜单偏好和睡眠状态不保存。退出旧版后再启动新版，同一时间只运行一个实例。

## 构建与检查

在 Windows PowerShell 中执行：

```powershell
.\build.ps1
$p = Start-Process .\AnnyDesktop.exe -ArgumentList '--smoke-test' -Wait -PassThru
if ($p.ExitCode -ne 0) { throw 'Smoke test failed' }
Get-Content .\qa\result.txt
```

使用 Windows 自带的 .NET Framework C# 编译器，无需安装 NuGet 依赖。检查使用临时存档，覆盖动作、透明渲染、移动、悬停面板、喂食循环和睡眠定位；检查结果输出到 `qa/`。

## 替换素材

`assets/pet.png` 是 8 列 × 13 行的透明 PNG 图集，每格 192 × 208。`assets/pet.ini` 配置动作行号、有效帧数、播放速度和移动速度，修改后重启。

行号从 0 开始：0 待机，1 向右走，2 向左走，3 挥爪，4 跳跃，5 受挫，6 等待，7 思考，8 观察，9–10 十六方向注视，11 吃饭，12 睡觉。注视行固定为 9–10。睡觉会根据不透明像素边界对齐待机中心和基线；替换素材时应保持一致画布、比例及干净透明背景。

计时器约 16ms，但原画每组为 4–8 帧，刷新率不等于原画帧率。可选帧间柔化默认关闭，开启可能有重影。

详细操作见 [使用说明](使用说明.txt)。
