#!/bin/zsh
# Safely updates the repo from GitHub. Use this INSTEAD of `git pull`.
#  1. fetches without touching your files
#  2. every new commit must be signed by a key from ~/.config/git/allowed_signers
#     (that file lives only on your Mac, so a hacked GitHub can't fake it)
#  3. scans the incoming changes for suspicious code
#  4. shows what changed and asks before applying (fast-forward only)
set -euo pipefail
cd "$(dirname "$0")"

SIGNERS=~/.config/git/allowed_signers
[[ -s $SIGNERS ]] || { echo "✗ $SIGNERS missing: no trusted keys, refusing to update."; exit 1; }
git config gpg.ssh.allowedSignersFile "$SIGNERS"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
git fetch --quiet origin "$BRANCH"
NEW="origin/$BRANCH"

if [[ $(git rev-parse HEAD) == $(git rev-parse "$NEW") ]]; then
  echo "✓ Already up to date."; exit 0
fi
if ! git merge-base --is-ancestor HEAD "$NEW"; then
  echo "✗ GitHub history was rewritten (not a fast-forward). Possible tampering — refusing."
  exit 1
fi

# 1. Signatures
bad=0
for c in $(git rev-list HEAD.."$NEW"); do
  if git verify-commit "$c" >/dev/null 2>&1; then
    echo "✓ signed  $(git log -1 --format='%h %s' "$c")"
  else
    echo "✗ NOT SIGNED BY YOUR KEY  $(git log -1 --format='%h %an %s' "$c")"; bad=1
  fi
done
(( bad )) && { echo "\n✗ Unsigned/foreign commits. Nothing was applied."; exit 1; }

# 2. Suspicious patterns in added lines
echo "\nChanged files:"
git diff --stat HEAD "$NEW"
PATTERNS='curl |wget |base64|eval |osascript|launchctl|LaunchAgents|crontab|chmod \+x|/bin/(ba|z)?sh -c|Process\(|NSTask|URLSession|http://|https://|\.ssh|Keychain|SecItem|xattr|sudo '
hits=$(git diff HEAD "$NEW" | grep -E '^\+[^+]' | grep -nE "$PATTERNS" || true)
if [[ -n $hits ]]; then
  echo "\n⚠️  Suspicious lines in the update — read them carefully:"
  echo "$hits"
fi
# Binary files never belong in this repo
bins=$(git diff --numstat HEAD "$NEW" | awk '$1=="-"{print $3}')
[[ -n $bins ]] && echo "\n⚠️  Binary files in the update:\n$bins"

echo
read "ans?Apply the update? [y/N] "
[[ $ans == [yYдД]* ]] || { echo "Cancelled. Nothing changed."; exit 1; }
git merge --ff-only --quiet "$NEW"
echo "✓ Updated. Run ./build.sh to reinstall the app."
