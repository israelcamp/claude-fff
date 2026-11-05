# Claude FFF

Use the FFF search library used by OpenCode for file and folder suggestions in Claude Code's terminal `@` picker. This is a standalone adapter, not an official OpenCode or Anthropic plugin.

The launcher indexes your current directory, starts Claude Code, forwards its arguments, and stops the search server when Claude exits. The server keeps the FFF index in memory between searches.

## Install

Download or clone this repository from GitHub, open a terminal in its directory, and run:

```sh
bash install.sh
```

Open a new terminal, then run `claude-fff` from the project you want to search. Sign in to Claude Code when prompted on your first launch.

The installer:

- Copies the app to `~/.local/share/claude-fff` and creates `~/.local/bin/claude-fff`. You can delete the downloaded repository afterward.
- Reuses Node.js 22+ and npm when available, or downloads Node.js 24 LTS and npm into the app's private `runtime` directory. Downloads are verified against Node.js's published SHA-256 checksums.
- Reuses Claude Code when available, or installs it with [Anthropic's native installer](https://code.claude.com/docs/en/setup).
- Installs the pinned FFF dependency and checks that the native module loads.
- Adds the command directory to `.zshrc`, `.bashrc`, and `.bash_profile`, preserving existing contents and backing up existing files before changes. Rerunning the installer does not duplicate these additions.

No `sudo` is required. Installation needs internet access, Bash, `curl`, `tar`, and either `shasum` or `sha256sum` when downloading Node.js. macOS includes these tools; on minimal Linux systems, install missing tools using your system package manager first. Claude Code requires a subscription or another supported authentication method.

The installer supports macOS and glibc-based Linux, on x64 or ARM64, including WSL. Native Windows and Alpine/musl are not supported. FFF compatibility depends on the pinned SDK's available native binaries.

### Custom paths and shells

```sh
CLAUDE_FFF_INSTALL_DIR="$HOME/apps/claude-fff" \
CLAUDE_FFF_BIN_DIR="$HOME/bin" \
bash install.sh --no-shell
```

Both paths must be absolute. `--no-shell` skips shell startup changes; add the chosen command directory to PATH yourself. Fish and other shells require manual PATH configuration. Run `bash install.sh --help` for options.

## Picker configuration

The launcher configures the picker automatically for its session with Claude Code's [`--settings` option](https://code.claude.com/docs/en/cli-reference). Existing user and project settings are preserved. No per-project setup is needed. Use `claude` for a regular session without FFF.

If you prefer FFF every time, optionally add this function to your shell startup file:

```sh
claude() { claude-fff "$@"; }
```

The launcher invokes the underlying Claude executable directly. Use `command claude` to bypass the function.

Migrating from the old manual setup: remove your old machine-specific `claude` function and manually added `fileSuggestion` settings.

## Usage

Only one FFF session can run at a time, using localhost port `43871`. Stop any manually started FFF server first. Then run Claude from the project you want to search:

```sh
cd /path/to/project
claude-fff
```

Type `@` followed by part of a file or folder name. Arguments work normally:

```sh
claude-fff --resume
```

Exit Claude normally to stop its FFF server. Cleanup also runs on interrupt, hangup, and termination signals; a forced kill or system crash cannot run shell cleanup.

Bypass the wrapper when needed:

```sh
command claude --version
```

Run the installed command directly if its directory is not on PATH:

```sh
"$HOME/.local/bin/claude-fff"
```

In VS Code, enable **Extensions → Claude Code → Use Terminal** to use this CLI customization. Support for the graphical chat panel's picker has not been verified. When launching from the extension rather than your shell, run `claude-fff` in the terminal; the extension does not automatically invoke this wrapper.

## Update

Download or pull the latest repository and rerun `bash install.sh`. Use the same path overrides if you chose custom directories. Existing Claude Code installations are left in place. If you change your Node.js installation or remove an nvm-managed version, rerun the installer to refresh the runtime path recorded in the launcher.

## Development and testing

Run `npm install` and `bash claude-fff.sh` to use the repository directly. Run the isolated installer and launcher checks with `bash tests/smoke.sh`.

### Manual testing

Start the server in one terminal:

```sh
node "$HOME/.local/share/claude-fff/server.mjs" /path/to/project
```

From another terminal:

```sh
curl --silent --show-error --fail \
  --header 'Content-Type: application/json' \
  --data '{"query":"src"}' \
  http://127.0.0.1:43871/search
```

Press Ctrl+C in the server terminal to stop it.

## Troubleshooting

- **Port already in use:** close the other wrapped Claude session or manually started server. The launcher reports `EADDRINUSE` and exits if another server owns the port.
- **Wrong project's results:** the server indexes the directory where you launched the wrapper. Exit and restart from the intended project root. Resuming a session in another directory or using `--worktree` does not retarget the index.
- **No suggestions:** test the curl command above, check that the project is trusted, and avoid overriding `--settings` when using the wrapper. Managed policies and safe mode can disable custom suggestion commands.
- **Native module fails:** rerun the installer and check FFF's supported platforms. The installer reports an error if the pinned SDK cannot load its native module.
- **Folder selection differs from OpenCode:** this adapter replaces search suggestions only. It does not port OpenCode's attachment handling or line-range syntax.

## Removal

For the default installation:

```sh
rm -rf "$HOME/.local/share/claude-fff"
rm -f "$HOME/.local/bin/claude-fff"
```

Remove lines marked `# claude-fff PATH` from your shell startup files and any optional `claude` function you added. Use your custom paths if applicable. Claude Code and its configuration are retained; see [Anthropic's uninstall instructions](https://code.claude.com/docs/en/setup#uninstall-claude-code) to remove Claude Code too.

## References

- [Claude Code custom file suggestions](https://code.claude.com/docs/en/settings-reference#filesuggestion)
- [FFF Node/Bun SDK](https://github.com/dmtrKovalenko/fff#node--bun-sdk)
- [Claude Code VS Code terminal mode](https://code.claude.com/docs/en/vs-code#switch-to-terminal-mode)
