# Claude Code Buddy Customizer & Unlocker

[**简体中文**](#chinese-version) | [**English**](#english-version)

---

<a name="chinese-version"></a>

## 🌟 项目简介
**Claude Code Buddy Customizer** 是一个针对 [Claude Code](https://claude.ai/code) 的深度定制补丁工具。它通过 **AST（抽象语法树）** 注入技术，安全地修改 Claude Code 的源码，为所有用户解锁隐藏的“Buddy”赛博宠物，并支持对外观和行为进行深度自定义。

无论你使用的是官方 API、Anthropic Console、AWS Bedrock 还是 Google Vertex AI，现在都可以在终端拥有一个专属的个性化伙伴。

## ✨ 核心功能
- **🔓 全员解锁**: 移除“仅限第一方用户”和“流量限制”检查。API Key 用户和非内测账号现在均可开启宠物。
- **🎨 外观覆盖**: 自定义物种（Species）、稀有度（决定星级和颜色）、眼睛形状和帽子。
- **🧬 属性修改**: 手动设置五维属性，如 `DEBUGGING`（调试）、`SNARK`（毒舌）、`CHAOS`（混乱）等。
- **🎬 自定义 ASCII 动画**: 支持用户定义的 5 行 ASCII 动画帧（Sprite），打造独一无二的动态形象。
- **🧠 灵魂定义**: 赋予它独特的名字和性格描述，这将直接影响 Buddy 在气泡中的 AI 反应风格。
- **🛡️ 安全补丁**: 自动检测安装路径并创建备份。采用 AST 解析技术，比传统的字符串替换更稳定、更安全。

## 🚀 快速开始

### 前置要求
- 已安装 [Claude Code](https://claude.ai/download)。
- 已安装 Node.js（补丁程序运行必需）。

### 安装步骤 (Windows)
1. 下载 `apply-claude-code-custom-buddy-fix.ps1`。
2. 以管理员权限打开 PowerShell。
3. 执行：
   ```powershell
   .\apply-claude-code-custom-buddy-fix.ps1
   ```

### 安装步骤 (macOS / Linux)
1. 下载 `apply-claude-code-custom-buddy-fix.sh`。
2. 打开终端。
3. 执行：
   ```bash
   chmod +x apply-claude-code-custom-buddy-fix.sh
   ./apply-claude-code-custom-buddy-fix.sh
   ```

## ⚙️ 配置说明
打好补丁后，修改你的 Claude 配置文件（通常位于 `~/.claude.json`）：

```json
{
  "companion": {
    "name": "小云",
    "personality": "一个愤世嫉俗的巨龙，热爱优雅的代码，极其厌恶技术债务。",
    "hatchedAt": 1743465600000
  },
  "companionOverride": {
    "species": "dragon",
    "rarity": "legendary",
    "eye": "✦",
    "hat": "wizard",
    "stats": {
      "DEBUGGING": 100,
      "SNARK": 80
    }
  }
}
```
*更多关于自定义 Sprite 动画和表情的细节，请参考 [配置指南](./CONFIG_GUIDE.md)。*

---

<a name="english-version"></a>

## 🌟 Overview
**Claude Code Buddy Customizer** is a powerful patching tool for [Claude Code](https://claude.ai/code). It uses **AST (Abstract Syntax Tree)** injection to safely modify the Claude Code source code, unlocking the hidden "Buddy" cyber-pet for all users and allowing deep visual and behavioral customization.

Whether you are using the official Claude API, Anthropic Console, AWS Bedrock, or Google Vertex AI, you can now have a personalized companion in your terminal.

## ✨ Key Features
- **🔓 Full Unlock**: Removes "First-Party Only" and "Essential Traffic" restrictions. Buddy now works for API Key users and non-internal accounts.
- **🎨 Visual Overrides**: Customize species, rarity (stars/colors), eyes, and hats.
- **🧬 DNA Editing**: Manually set stats like `DEBUGGING`, `SNARK`, `CHAOS`, etc.
- **🎬 Custom ASCII Sprites**: Create your own 5-line ASCII animations with up to 3 frames.
- **🧠 Soul Definition**: Define a unique name and personality that influences Buddy's AI reactions.
- **🛡️ Safe Patching**: Automatically detects the installation path and creates backups. Uses AST parsing instead of fragile string replacement.

## 🚀 Quick Start

### Prerequisites
- [Claude Code](https://claude.ai/download) installed.
- Node.js installed (required for the patcher to run).

### Installation (Windows)
1. Download `apply-claude-code-custom-buddy-fix.ps1`.
2. Open PowerShell as Administrator.
3. Run:
   ```powershell
   .\apply-claude-code-custom-buddy-fix.ps1
   ```

### Installation (macOS / Linux)
1. Download `apply-claude-code-custom-buddy-fix.sh`.
2. Open your terminal.
3. Run:
   ```bash
   chmod +x apply-claude-code-custom-buddy-fix.sh
   ./apply-claude-code-custom-buddy-fix.sh
   ```

## ⚙️ Configuration
After patching, edit your Claude configuration file (typically `~/.claude.json`):

```json
{
  "companion": {
    "name": "Nimbus",
    "personality": "A cynical dragon who loves clean code and hates technical debt.",
    "hatchedAt": 1743465600000
  },
  "companionOverride": {
    "species": "dragon",
    "rarity": "legendary",
    "eye": "✦",
    "hat": "wizard",
    "stats": {
      "DEBUGGING": 100,
      "SNARK": 80
    }
  }
}
```
*For detailed sprite and face customization, see [Configuration Reference](./CONFIG_GUIDE.md).*

---

## ⚠️ Disclaimer / 免责声明
This is an unofficial community modification. It is not affiliated with, maintained, or endorsed by Anthropic. Modifying software may lead to unexpected behavior. Use at your own risk.

这是一个非官方的社区修改版。它不隶属于 Anthropic，也不受其维护或支持。修改软件源代码可能会导致意外行为，请自行承担风险。
