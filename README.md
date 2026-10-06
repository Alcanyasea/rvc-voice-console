# 变声控制台 · RVC 游戏实时变声工具链

基于 [RVC (Retrieval-based-Voice-Conversion)](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI) 的 Windows 游戏实时变声一键控制台。

```
麦克风 → NVIDIA Broadcast（降噪）→ RVC 实时变声 → VB-CABLE（虚拟声卡）→ 游戏麦克风
```

## 功能

- **托盘控制台，一键整链**：打开面板 = 系统默认麦克风自动切到虚拟声卡 + 自动拉起 RVC（启动即自动开始转换）；托盘右键退出 = 自动恢复原声麦克风
- **状态栏实时检测**（2 秒刷新）：绿色"变声生效中" / 橙色"RVC 未运行 / 未开转换"——转换流状态由 RVC 侧写的 `stream_state.txt` 标记
- **RVC 意外退出气泡提醒**；「启动 RVC」按钮在 RVC 已运行时把收进托盘的窗口调回前台
- 默认麦克风切换走未公开 COM 接口 `IPolicyConfig::SetDefaultEndpoint`，免管理员、免第三方工具
- RVC 侧补丁：X/最小化收真托盘（infi.systray）、启动即自动开始转换、音频回调线程安全化、软限幅、回调停摆自动复位等（完整清单见 `变声设置说明.md`）

## 文件说明

| 文件 | 作用 |
|---|---|
| `变声控制台.ps1` | 托盘面板主体（WinForms + NotifyIcon + COM 音频设备切换） |
| `build_panel.ps1` | 生成图标、用系统 csc 编译 `变声控制台.exe`、更新桌面/开始菜单快捷方式 |
| `panel_launcher.cs` | exe 启动器源码（无黑框静默拉起 pwsh 运行面板） |
| `切换麦克风.ps1` | 命令行双模式切换：`game`（虚拟声卡）/ `voice`（真实麦克风） |
| `扫描游戏麦克风.ps1`、`check_naraka_mic.ps1` | 枚举音频会话，定位游戏实际从哪个设备采集 |
| `测试变声链路.ps1`、`test_bc_level.ps1`、`test_misiom.ps1`、`mic_fix.py` | 链路上下游电平自测、麦克风音量检查修复 |
| `debug_sessions.ps1`、`check_procs.ps1` | 音频会话 / 进程调试工具 |
| `RVC2026/.../realtime_gui.py` | 打过补丁的 RVC 实时 GUI（补丁逐条记录在 `变声设置说明.md`） |
| `RVC2026/.../realtime_guiw.pyw` | pythonw 无控制台启动器（stdout/stderr 重定向到日志） |
| `RVC2026/.../configs/config.json` | 当前实时变声参数（模型、延迟块、音高等） |

## 环境与重建

- 依赖：PowerShell 7（pwsh）、RVC 完整包（含 Python runtime，**不在本仓库**）、VB-CABLE 虚拟声卡、NVIDIA Broadcast（可选，降噪用）
- 重建 exe 与快捷方式：`pwsh build_panel.ps1`（改过 ps1 文件名/路径后需要跑）
- RVC 补丁清单、重打补丁步骤、常见坑：见 [`变声设置说明.md`](变声设置说明.md)

## 仓库范围

本仓库只包含自研工具与补丁文件。RVC 本体（数 GB runtime）、第三方声音模型（.pth/.index）、各类安装包、个人录音均不入库，由白名单式 `.gitignore` 严格控制。

## License

本仓库包含的 `realtime_gui.py` 等文件基于 RVC 项目（MIT License）修改，遵循其原始许可；其余自研脚本同以 MIT 发布。
