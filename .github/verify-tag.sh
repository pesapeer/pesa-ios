#!/usr/bin/env bash
# Refuses a release tag whose commit is not SSH-signed by a maintainer listed
# in .github/allowed_signers. Run from the repository root with the tag name.
# The tag itself may be unsigned: the v* ruleset limits who can push one.
set -euo pipefail
tag="${1:?tag}"
git config gpg.ssh.allowedSignersFile .github/allowed_signers
commit=$(git rev-list -n 1 "$tag")
if ! git verify-commit "$commit" >/dev/null 2>&1; then
  echo "commit $commit at tag $tag is not signed by a key in .github/allowed_signers" >&2
  exit 1
fi
echo "tag $tag -> commit $commit verified"
