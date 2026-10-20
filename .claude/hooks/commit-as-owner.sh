#!/bin/bash
# SessionStart hook: commits made in this repository by Claude Code are authored and committed as the owner, and
# the commit-msg hook in .githooks/ removes assistant attribution trailers. Repository-local git config, so it
# overrides any global identity the session's machine has. Signing is turned off here: a cloud session signs with
# Claude's key, which GitHub only accepts for Claude's address, so signed commits in the owner's name would show as
# Unverified; unsigned commits show no badge.
set -euo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"
git config user.name "Arshiya Rahgozar"
git config user.email "57055687+marshiyar@users.noreply.github.com"
git config core.hooksPath .githooks
git config commit.gpgsign false
