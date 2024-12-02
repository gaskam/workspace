<h1 align="center">Workspace</h1>

<p align="center">
  <img src="https://img.shields.io/github/v/release/gaskam/workspace?display_name=tag&style=for-the-badge" alt="GitHub Release">
  <img src="https://img.shields.io/github/license/gaskam/workspace?style=for-the-badge" alt="GitHub License">
</p>

<p align="center">
  A powerful Zig-based tool to manage all your GitHub repositories with ease
</p>

## ✨ Features

- 🚀 **Fast & Efficient** - Built with Zig for maximum performance
- 📦 **Bulk Operations** - Clone all repositories from any GitHub organization or user
- 🔄 **Concurrent Processing** - Handle multiple repositories simultaneously
- 🧹 **Cleanup Tools** - Prune unwanted repositories automatically
- 🛠️ **Easy Setup** - Simple installation process for both Windows and Linux

## 📜 Table of Contents
- [Quick Start](#-quick-start)
- [Usage](#-usage)
  - [Example](#example)
- [Development](#️️-development)
  - [Prerequisites](#prerequisites)
  - [Steps](#steps)
- [Contributing](#-contributing)
- [License](#license)

## 🚀 Quick Start

Choose your platform and run the installation command:

🐧 Linux

```bash
curl -fsSL https://raw.githubusercontent.com/gaskam/workspace/refs/heads/main/install.sh | bash
```

🪟 Windows PowerShell

```bash
irm raw.githubusercontent.com/gaskam/workspace/refs/heads/main/install.ps1 | iex
```

This script will:
- Install Workspace.
- Add it to your PATH.
- Ensure all required dependencies are installed.

## 📖 Usage
Workspace can be called with the following arguments:

For **cloning** repositories from a GitHub organization or user:
```bash
workspace clone <organization/user> [destination] [--flags]
```

Flags:
| Flag | Description |
|------|-------------|
| `--limit`, `-l` | Limit the number of repositories to clone |
| `--processes`, `-p` | Limit the number of concurrent processes -> Default is the number of logical CPUs - 1 |
| `--prune` | Delete repositories that do not belong to current user |

For showing **help**:
```bash
workspace help
```

For showing the **version**:
```bash
workspace version
```

For **updating** Workspace:
```bash
workspace update
```

For **uninstalling** Workspace:
```bash
workspace uninstall
```

### Example
Clone repositories from an organization

```bash
# Clone first 10 repos from ziglang
workspace clone ziglang ./workspace -l 10

# Clone all repos with 8 concurrent processes
workspace clone microsoft ./code -p 8

# Clone and clean up old repos
workspace clone gaskam ./projects --prune
```

> [!NOTE] 
> Note that if you provide `--limit` and `--prune` flags, we'll delete 
> the repositories that no longer exist once the limit is reached.

## 🛠️ Development
For developers who want to contribute or build Workspace from source:

### Prerequisites
| Tool | Purpose | Installation |
|------|---------|--------------|
| ⚡ Zig | Building the application | [Download](https://ziglang.org/download/) |
| 🐙 GitHub CLI | Interacting with GitHub | [Download](https://github.com/cli/cli#installation) |
| 📦 Git | Git, forever and ever | [Download](https://git-scm.com/downloads) |

### Steps
1. Clone the repository:

```bash
git clone https://github.com/gaskam/workspace.git
cd workspace
```

2. Build the application:

```bash
zig build
```

3. Run the built binary:

```bash
./zig-out/bin/workspace -h
```
## 🤝 Contributing
Contributions are welcome! Feel free to:

* 🐛 Report bugs
* 💡 Suggest new features
* 📝 Improve documentation
* 🔧 Submit pull requests

## License

Workspace is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.

Made with ❤️ by Gaskam
