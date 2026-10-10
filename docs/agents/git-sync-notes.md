# Push failed - need credentials

## GitHub Push Setup Required

Current workspace needs GitHub credentials configured for automatic push.

### Options:
1. **SSH Key**: Add SSH key to GitHub account, switch remote to SSH URL
   ```bash
   git remote set-url origin git@github.com:ford442/image_video_effects.git
   ```

2. **GitHub Token**: Use personal access token with HTTPS
   ```bash
   git remote set-url origin https://TOKEN@github.com/ford442/image_video_effects.git
   ```

3. **Credential helper**: Store credentials locally
   ```bash
   git config --global credential.helper store
   # Then push once manually to enter credentials
   ```

### Auto-push script (for cron/heartbeat)
```bash
#!/bin/bash
cd /root/.openclaw/workspace
git add -A
git diff --cached --quiet || git commit -m "auto-sync: $(date +%Y-%m-%d-%H:%M)"
git push origin main
```

### Recommended sync frequency
- Every 15-30 minutes during active development
- Before/after major task switches
- When agent tasks complete
