#!/usr/bin/env bash
# Refuses a release tag that is not SSH-signed by a maintainer listed in
# .github/allowed_signers. Run from the repository root with the tag name.
set -euo pipefail
tag="${1:?tag}"
git config gpg.ssh.allowedSignersFile .github/allowed_signers
if ! git tag -v "$tag" >/dev/null 2>&1; then
  echo "tag $tag is not signed by a key in .github/allowed_signers" >&2
  exit 1
fi
echo "tag $tag verified"
