# Workspace
Workspace is a powerful application designed to install and manage all your repositories in your chosen destination. Built with **Zig**, it uses **gh** to fetch your repositories from GitHub with ease.

## Features
- Clone all repositories from a GitHub organization or user.
- Lightweight, fast, and written in **Zig**.
- Easy-to-use CLI for managing repositories.

## Installation
To install Workspace, run the installation script:

```bash
curl -fsSL https://raw.githubusercontent.com/gaskam/workspace/refs/heads/main/install.sh | bash
```

This script will:
- Install Workspace.
- Add it to your PATH.
- Ensure all required dependencies are installed.

## Usage
Workspace can be called with the following arguments:
- `workspace -h` or `workspace --help`: Display help information.
- `workspace -v` or `workspace --version`: Show the current version.
- `workspace [org or usr]`: Clone all repositories from the specified GitHub organization or user.

### Example
```bash
workspace my-organization
```

## Development
For developers who want to contribute or build Workspace from source:

### Prerequisites
- Zig (latest version recommended)
- GitHub CLI (gh)
- Git

### Steps
1. Clone the repository:

```bash
git clone https://github.com/gaskam/workspace.git
cd workspace
```

2. Build the application:

```bash
zig build -Drelease-fast
```

3. Run the built binary:

```bash
./zig-out/bin/workspace -h
```

## License

Workspace is licensed under the MIT License.

