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
>
> This is useful for keeping your workspace clean and up-to-date.

> [!WARNING]
> If you use the `--processes` flag with a number higher than your 
> number of CPU threads, you may experience performance issues.
>
> This can be useful if you want to override the default number of 
> simultaneous processes, in order to go faster. It *will* be faster 
> than the default value, but at the cost of a higher ressource usage.

## Benchmarks
This benchmark was run on a **GitHub codespaces** instance with **4 vCPUs** and **16GB of RAM**.

> [!NOTE] GitHub Codespaces is quite slow, since it clones with just one process.

We're using **hyperfine** to measure the time taken to clone each **repositories** from the specified organization.

Realized on **2024-12-03** with the **1.2.2** version of Workspace.

| Organization | Repositories Cloned | Time Taken [s]   |
|--------------|---------------------|------------------|
| ziglang      | 24                  | 103.458 ± 4.833  |
| gaskam       | 11                  | 3.454 ± 0.185    |

## 🛠️ Development
For developers who want to contribute or build Workspace from source:

### Prerequisites
| Tool          | Purpose                         | Installation                                        |
|---------------|---------------------------------|-----------------------------------------------------|
| ⚡ Zig         | Building the application        | [Download](https://ziglang.org/download/)           |
| 🐙 GitHub CLI | Interacting with GitHub         | [Download](https://github.com/cli/cli#installation) |
| 📦 Git        | Git, forever and ever           | [Download](https://git-scm.com/downloads)           |

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
