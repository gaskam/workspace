# Workspace

> [!NOTE] 
> This project is still in development and may not be stable.

Workspace is a powerful application designed to install and manage all your repositories in your chosen destination. Built with **Zig**, it uses **gh** to fetch your repositories from GitHub with ease.

## Table of Contents
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
  - [Limitations](#limitations)
- [Development](#development)
  - [Prerequisites](#prerequisites)
  - [Steps](#steps)
- [License](#license)

## Features
- Clone all repositories from a GitHub organization or user.
- Lightweight, fast, and written in **Zig**.
- Easy-to-use CLI for managing repositories.

## Installation
To install Workspace, run the following command:

For **Linux**:
```bash
curl -fsSL https://raw.githubusercontent.com/gaskam/workspace/refs/heads/main/install.sh | bash
```

For **Windows PowerShell**:
```bash
irm raw.githubusercontent.com/gaskam/workspace/refs/heads/main/install.ps1 | iex
```

This script will:
- Install Workspace.
- Add it to your PATH.
- Ensure all required dependencies are installed.

## Usage
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

### Example
To clone the first 10 repositories from the `ziglang` organization to the `./workspace` directory with a limit of 10 repositories and 5 concurrent processes:
```bash
workspace clone ziglang ./workspace --limit 10 --processes 5 --prune
```

## Development
For developers who want to contribute or build Workspace from source:

### Prerequisites
* Zig (latest version recommended). Install from [here](https://ziglang.org/download/)

* GitHub CLI (gh), with their installation instructions [here](https://github.com/cli/cli#installation)

* Git, forever and ever.

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

## License

Workspace is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.
