#!/usr/bin/env bash
# Copyright MIT License - code from Bun.sh software installation, 2024
# Edited by Gaskam
set -euo pipefail

platform=$(uname -ms)
if [[ ${OS:-} = Windows_NT ]]; then
    if [[ $platform != MINGW64* ]]; then
        powershell -c "irm raw.githubusercontent.com/gaskam/workspace/refs/heads/main/install.ps1 | iex"
        exit $?
    fi
fi

# Reset
Color_Off=''

# Regular Colors
Red=''
Green=''
Dim='' # White

# Bold
Bold_White=''
Bold_Green=''

if [[ -t 1 ]]; then
    # Reset
    Color_Off='\033[0m' # Text Reset

    # Regular Colors
    Red='\033[0;31m'   # Red
    Green='\033[0;32m' # Green
    Dim='\033[0;2m'    # White

    # Bold
    Bold_Green='\033[1;32m' # Bold Green
    Bold_White='\033[1m'    # Bold White
fi

error() {
    echo -e "${Red}error${Color_Off}:" "$@" >&2
    exit 1
}

info() {
    echo -e "${Dim}$@ ${Color_Off}"
}

info_bold() {
    echo -e "${Bold_White}$@ ${Color_Off}"
}

success() {
    echo -e "${Green}$@ ${Color_Off}"
}

command -v unzip >/dev/null ||
    error "unzip is required to install workspace"

command -v curl >/dev/null ||
    error "curl is required to install workspace"

command -v git >/dev/null ||
    error "git is required to install workspace"

if [[ $# -gt 1 ]]; then
    error "Too many arguments, only 1 are allowed. It's can be a specific tag of workspace to install. (e.g. 'v0.1.0')"
fi

case $platform in
'Darwin x86_64')
    target=x86_64-macos
    ;;
'Darwin arm64')
    target=aarch64-macos
    ;;
'Linux aarch64' | 'Linux arm64')
    target=aarch64-linux
    ;;
'MINGW64'*)
    target=x86_64-windows
    ;;
'Linux x86_64' | *)
    target=x86_64-linux
    ;;
esac

case "$target" in
'linux'*)
    if [ -f /etc/alpine-release ]; then
        target="$target-musl"
    elif [ -f /etc/debian_version ]; then
        target="$target-gnu"
    fi
    ;;
esac

if [[ $target = x86_64-macos ]]; then
    # Is this process running in Rosetta?
    # redirect stderr to devnull to avoid error message when not running in Rosetta
    if [[ $(sysctl -n sysctl.proc_translated 2>/dev/null) = 1 ]]; then
        target=aarch64-macos
        info "Your shell is running in Rosetta 2. Downloading workspace for $target instead"
    fi
fi

if ! command -v gh >/dev/null; then
    info "gh is required to run workspace"
    if [[ $target == *linux* ]]; then
        if ! command -v sudo >/dev/null || ! sudo apt-get install -y gh; then
            error "Failed to install gh"
            info "You can install gh by running:"
            info_bold "  sudo apt-get install gh"
        fi
    elif [[ $target == *macos* ]]; then
        if ! brew install gh; then
            error "Failed to install gh"
            info "You can install gh by running:"
            info_bold "  brew install gh"
        fi
    elif [[ $target == *windows* ]]; then
        if ! winget install --id GitHub.cli; then
            error "Failed to install gh"
            info "You can install gh by running:"
            info_bold "  winget install --id GitHub.cli"
        fi
    else
        error "No automatic installation of gh available for this platform"
        error "Full installation instructions can be found at https://github.com/cli/cli#installation"
    fi
fi

GITHUB=${GITHUB-"https://github.com"}

github_repo="$GITHUB/gaskam/workspace"

# If AVX2 isn't supported, use the -baseline build
case "$target" in
'x86_64-macos'*)
    if [[ $(sysctl -a | grep machdep.cpu | grep AVX2) == '' ]]; then
        target="$target-baseline"
    fi
    ;;
'x86_64-linux'*)
    # If AVX2 isn't supported, use the -baseline build
    if [[ $(cat /proc/cpuinfo | grep avx2) = '' ]]; then
        target="$target-baseline"
    fi
    ;;
esac

exe_name=workspace

if [[ $# = 0 ]]; then
    workspace_uri=$github_repo/releases/latest/download/workspace-$target.zip
else
    workspace_uri=$github_repo/releases/download/$1/workspace-$target.zip
fi

install_env=WORKSPACE_INSTALL
bin_env=\$$install_env/bin

install_dir=${!install_env:-$HOME/.workspace}
bin_dir=$install_dir/bin
exe=$bin_dir/workspace

if [[ ! -d $bin_dir ]]; then
    mkdir -p "$bin_dir" ||
        error "Failed to create install directory \"$bin_dir\""
fi

curl --fail --location --progress-bar --output "$exe.zip" "$workspace_uri" ||
    error "Failed to download workspace from \"$workspace_uri\""

unzip -oqd "$bin_dir" "$exe.zip" ||
    error 'Failed to extract workspace'

chmod +x "$exe" ||
    error 'Failed to set permissions on workspace executable'

rm -r "$exe.zip"

tildify() {
    if [[ $1 = $HOME/* ]]; then
        local replacement=\~/

        echo "${1/$HOME\//$replacement}"
    else
        echo "$1"
    fi
}

success "workspace was installed successfully to $Bold_Green$(tildify "$exe")"

if command -v workspace >/dev/null; then
    echo "Run 'workspace --help' to get started"
    exit
fi

refresh_command=''

tilde_bin_dir=$(tildify "$bin_dir")
quoted_install_dir=\"${install_dir//\"/\\\"}\"

if [[ $quoted_install_dir = \"$HOME/* ]]; then
    quoted_install_dir=${quoted_install_dir/$HOME\//\$HOME/}
fi

echo

case $(basename "$SHELL") in
fish)
    commands=(
        "set --export $install_env $quoted_install_dir"
        "set --export PATH $bin_env \$PATH"
    )

    fish_config=$HOME/.config/fish/config.fish
    tilde_fish_config=$(tildify "$fish_config")

    if [[ -w $fish_config ]]; then
        {
            echo -e '\n# workspace'

            for command in "${commands[@]}"; do
                echo "$command"
            done
        } >>"$fish_config"

        info "Added \"$tilde_bin_dir\" to \$PATH in \"$tilde_fish_config\""

        refresh_command="source $tilde_fish_config"
    else
        echo "Manually add the directory to $tilde_fish_config (or similar):"

        for command in "${commands[@]}"; do
            info_bold "  $command"
        done
    fi
    ;;
zsh)
    commands=(
        "export $install_env=$quoted_install_dir"
        "export PATH=\"$bin_env:\$PATH\""
    )

    zsh_config=$HOME/.zshrc
    tilde_zsh_config=$(tildify "$zsh_config")

    if [[ -w $zsh_config ]]; then
        {
            echo -e '\n# workspace'

            for command in "${commands[@]}"; do
                echo "$command"
            done
        } >>"$zsh_config"

        info "Added \"$tilde_bin_dir\" to \$PATH in \"$tilde_zsh_config\""

        refresh_command="exec $SHELL"
    else
        echo "Manually add the directory to $tilde_zsh_config (or similar):"

        for command in "${commands[@]}"; do
            info_bold "  $command"
        done
    fi
    ;;
bash)
    commands=(
        "export $install_env=$quoted_install_dir"
        "export PATH=\"$bin_env:\$PATH\""
    )

    bash_configs=(
        "$HOME/.bashrc"
        "$HOME/.bash_profile"
    )

    if [[ ${XDG_CONFIG_HOME:-} ]]; then
        bash_configs+=(
            "$XDG_CONFIG_HOME/.bash_profile"
            "$XDG_CONFIG_HOME/.bashrc"
            "$XDG_CONFIG_HOME/bash_profile"
            "$XDG_CONFIG_HOME/bashrc"
        )
    fi

    set_manually=true
    for bash_config in "${bash_configs[@]}"; do
        tilde_bash_config=$(tildify "$bash_config")

        if [[ -w $bash_config ]]; then
            {
                echo -e '\n# workspace'

                for command in "${commands[@]}"; do
                    echo "$command"
                done
            } >>"$bash_config"

            info "Added \"$tilde_bin_dir\" to \$PATH in \"$tilde_bash_config\""

            refresh_command="source $bash_config"
            set_manually=false
            break
        fi
    done

    if [[ $set_manually = true ]]; then
        echo "Manually add the directory to $tilde_bash_config (or similar):"

        for command in "${commands[@]}"; do
            info_bold "  $command"
        done
    fi
    ;;
*)
    echo 'Manually add the directory to ~/.bashrc (or similar):'
    info_bold "  export $install_env=$quoted_install_dir"
    info_bold "  export PATH=\"$bin_env:\$PATH\""
    ;;
esac

echo
info "To get started, run:"
echo

if [[ $refresh_command ]]; then
    info_bold "  $refresh_command"
fi

info_bold "  workspace help"
