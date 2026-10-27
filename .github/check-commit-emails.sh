#!/usr/bin/env bash
# Fails when a commit in the history carries an email outside the allowlist.
# Keeps personal addresses out of a public repository.
set -euo pipefail
allowed='^(developer@pesapeer\.com|noreply@github\.com|[^@]+@users\.noreply\.github\.com)$'
bad=$(git log --format='%ae%n%ce' | sort -u | grep -Ev "$allowed" || true)
if [ -n "$bad" ]; then
  echo "commits with a non-allowlisted email:" >&2
  echo "$bad" | sed 's/^/  /' >&2
  exit 1
fi
echo "commit emails ok"
