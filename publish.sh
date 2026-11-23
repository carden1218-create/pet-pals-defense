#!/usr/bin/env bash
# Republish 萌宠防线 / Pet Pals Defense to GitHub Pages.
# Reads the GitHub token from a local file; never prints it.
set -euo pipefail
# Do not enable xtrace — it could leak the token.
set +x

SRC="${GAME_SRC:-/workspace/pet-td}"
DEST="$(cd "$(dirname "$0")" && pwd)"
TOKEN_FILE="${GH_TOKEN_FILE:-/home/box/.gh_token}"
OWNER="carden1218-create"
REPO="pet-pals-defense"
REMOTE_URL="https://github.com/${OWNER}/${REPO}.git"
BRANCH="main"

die() { echo "$*" >&2; exit 1; }

[[ -f "$SRC/index.html" ]] || die "Missing $SRC/index.html"
[[ -d "$SRC/assets" ]] || die "Missing $SRC/assets"
[[ -f "$TOKEN_FILE" ]] || die "Missing GitHub token file at $TOKEN_FILE (chmod 600, classic token with repo and workflow scopes)."

copy_game() {
  cp "$SRC/index.html" "$DEST/index.html"
  mkdir -p "$DEST/assets"
  for d in bg eggs enemies pets ui; do
    if [[ -d "$SRC/assets/$d" ]]; then
      rm -rf "$DEST/assets/$d"
      mkdir -p "$DEST/assets/$d"
      cp -a "$SRC/assets/$d/." "$DEST/assets/$d/"
    fi
  done
  # sprite atlases live in assets/ (not a subfolder)
  mkdir -p "$DEST/assets"
  cp -a "$SRC"/assets/atlas-*.webp "$DEST/assets/" 2>/dev/null || true
  # Never publish raw source art or stray backups
  rm -rf "$DEST/assets"/raw*
  find "$DEST/assets" -maxdepth 1 -type d -name 'raw*' -exec rm -rf {} + 2>/dev/null || true
  touch "$DEST/.nojekyll"
}

config_is_clean() {
  # Return 1 if a secret-like value is in local git config, without printing it.
  local list
  list="$(git -C "$DEST" config --local --list 2>/dev/null || true)"
  if printf '%s\n' "$list" | grep -Eq 'ghp_|github_pat_|AUTHORIZATION:|x-access-token:'; then
    return 1
  fi
  return 0
}

scrub_config() {
  git -C "$DEST" remote set-url origin "$REMOTE_URL" 2>/dev/null || true
  git -C "$DEST" config --local --unset-all "http.https://github.com/.extraheader" 2>/dev/null || true
  git -C "$DEST" config --local --unset-all "http.extraheader" 2>/dev/null || true
}

copy_game

cd "$DEST"

if [[ ! -d .git ]]; then
  git init -b "$BRANCH"
  git config user.name "carden1218-create"
  git config user.email "carden1218-create@users.noreply.github.com"
  git remote add origin "$REMOTE_URL"
fi

# Keep the stored remote URL free of credentials.
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE_URL"
else
  git remote add origin "$REMOTE_URL"
fi

# Local identity (does not have to be global)
git config user.name "carden1218-create"
git config user.email "carden1218-create@users.noreply.github.com"

git add -A
if git diff --cached --quiet; then
  echo "No file changes to publish."
else
  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    git commit -m "Update Pet Pals Defense"
  else
    git commit -m "Publish Pet Pals Defense"
  fi
fi

# Push using a temporary GIT_ASKPASS helper so the token never lands in
# .git/config or in the remote URL.
ASKPASS="$(mktemp)"
chmod 700 "$ASKPASS"
cat > "$ASKPASS" << 'ASK'
#!/bin/sh
case "$1" in
  *[Uu]sername*) echo "x-access-token" ;;
  *) cat "${GH_TOKEN_FILE:-/home/box/.gh_token}" ;;
esac
ASK
# Make sure the helper sees the same token file path
export GH_TOKEN_FILE="$TOKEN_FILE"
export GIT_ASKPASS="$ASKPASS"
export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_NOSYSTEM=1

set +e
git push -u origin "$BRANCH"
PUSH_STATUS=$?
set -e

rm -f "$ASKPASS"
unset GIT_ASKPASS
unset GH_TOKEN

scrub_config
if ! config_is_clean; then
  echo "WARNING: git config still looked secret-like after scrub; remotes reset." >&2
  scrub_config
fi

if [[ $PUSH_STATUS -ne 0 ]]; then
  die "git push failed (exit $PUSH_STATUS)."
fi

echo "Published."
echo "Repo: https://github.com/${OWNER}/${REPO}"
echo "Live: https://${OWNER}.github.io/${REPO}/"
