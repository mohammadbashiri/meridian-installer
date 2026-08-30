# Meridian installer

Install or update [Meridian](https://github.com/mohammadbashiri/meridian) on Apple Silicon macOS:

```bash
curl -fsSL https://raw.githubusercontent.com/mohammadbashiri/meridian-installer/main/install.sh | sh
```

While Meridian is private, run `gh auth login` once first. The installer uses that authenticated GitHub CLI session to download the private release. Once Meridian is public, it falls back to anonymous release downloads automatically.

This repository intentionally contains only the bootstrap installer. Meridian source code and release artifacts remain in the Meridian repository.
