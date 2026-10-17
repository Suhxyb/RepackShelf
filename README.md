# Repack Shelf

A Windows 11 style game library manager. It finds installed games, shows them as a cover-art grid, launches them, and uninstalls them completely.

- Detects installer-based games (Inno Setup uninstall data) and folder-based games
- Cover art fetched automatically from Steam, with manual override
- Launch, open folder, choose the executable, full uninstall with leftover cleanup
- Built-in updater: checks GitHub Releases and updates itself in one click

## Install (for users)

1. Open the **Releases** page of this repository.
2. Download `RepackShelf.exe` and put it anywhere you like (a folder you can write to, not `Program Files`).
3. Run it. Windows SmartScreen may warn because the file is unsigned: choose **More info > Run anyway**.

### Updating

Repack Shelf checks for new versions each time it starts. When one is available a banner appears: click **Update now**. It downloads the new exe, verifies its SHA-256 checksum, replaces itself and restarts. You can also click **Updates** in the top bar at any time.

## Publishing updates (for the maintainer)

### One-time setup

1. Create a **public** GitHub repository (for example `RepackShelf`) and push this folder to it:

   ```
   git init
   git add .
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/YOUR-USERNAME/RepackShelf.git
   git push -u origin main
   ```

2. In the repo go to **Settings > Actions > General > Workflow permissions** and choose **Read and write permissions**.

Nothing needs editing in the code: the release workflow stamps your repository name and the version into the app when it builds.

### Releasing a new version

Commit your changes, then run:

```
release.bat 1.1.0
```

(or manually: `git push`, `git tag v1.1.0`, `git push origin v1.1.0`)

GitHub Actions then builds `RepackShelf.exe`, creates a checksum file, and publishes a release with auto-generated notes. Every installed copy will offer the update the next time it starts. Version numbers must look like `1.2.3`.

### Building locally

Double-click `build.bat`. The exe appears in `dist\`. Local builds are marked "dev build" and have update checking turned off. You can also run `src\RepackShelf.ps1` directly with PowerShell.

## How updating works

- The app calls the GitHub API for the latest release of its own repository and compares the tag to its built-in version.
- It downloads the release asset `RepackShelf.exe`, checks it against `RepackShelf.exe.sha256`, then a small helper script swaps the files after the app closes and starts the new version.
- If the app is in a folder it cannot write to, it opens the release page instead.

## Notes

- Requires Windows 10/11 with built-in Windows PowerShell 5.1.
- Settings and the cover cache live in `%APPDATA%\RepackShelf`.
- The app only manages games already on your PC. It does not download games.

## License

MIT
