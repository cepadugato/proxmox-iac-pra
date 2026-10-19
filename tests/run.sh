#!/usr/bin/env bash
# Oracle du projet : lance chaque tests/test-*.sh, sort 1 si l'un échoue.
# Usage : bash tests/run.sh [motif]
set -u
d="$(cd "$(dirname "$0")/.." && pwd)"
motif="${1:-}"
total=0; ko=0
for t in "$d"/tests/test-*.sh; do
  [ -f "$t" ] || continue
  case "$t" in *"$motif"*) ;; *) continue ;; esac
  total=$((total + 1))
  echo "== $(basename "$t")"
  bash "$t" || { ko=$((ko + 1)); echo "ECHEC: $(basename "$t")"; }
done
echo "$((total - ko))/$total fichiers de test verts"
[ "$ko" -eq 0 ]
