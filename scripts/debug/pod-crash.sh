#!/usr/bin/env bash
# Debug helper for CrashLoopBackOff / OOMKilled pods.
# Usage: ./scripts/debug/pod-crash.sh <pod-name-or-app-label> [namespace]
set -euo pipefail

TARGET="${1:?Usage: $0 <pod-name-or-app-label> [namespace]}"
NAMESPACE="${2:-online-boutique}"

resolve_pods() {
  # Accept either an exact pod name or an app label (e.g. "cartservice")
  if kubectl -n "$NAMESPACE" get pod "$TARGET" >/dev/null 2>&1; then
    echo "$TARGET"
  else
    kubectl -n "$NAMESPACE" get pods -l "app=$TARGET" -o jsonpath='{.items[*].metadata.name}'
  fi
}

PODS=$(resolve_pods)
if [ -z "$PODS" ]; then
  echo "No pods found matching '$TARGET' in namespace '$NAMESPACE'." >&2
  exit 1
fi

for POD in $PODS; do
  echo "=================================================================="
  echo "POD: $POD (namespace: $NAMESPACE)"
  echo "=================================================================="

  echo
  echo "--- restart count + last state reason ---"
  kubectl -n "$NAMESPACE" get pod "$POD" \
    -o jsonpath='{range .status.containerStatuses[*]}{.name}{"\trestarts="}{.restartCount}{"\treason="}{.lastState.terminated.reason}{"\texitCode="}{.lastState.terminated.exitCode}{"\n"}{end}'

  echo
  echo "--- describe (Events + Last State) ---"
  kubectl -n "$NAMESPACE" describe pod "$POD" | sed -n '/State:/,/^$/p; /Last State:/,/^$/p; /Events:/,$p'

  echo
  echo "--- previous container logs (last 100 lines, this is what actually crashed) ---"
  kubectl -n "$NAMESPACE" logs "$POD" --previous --tail=100 2>/dev/null || echo "(no previous logs — pod hasn't restarted yet, or this is its first run)"

  echo
  echo "--- current container logs (last 50 lines) ---"
  kubectl -n "$NAMESPACE" logs "$POD" --tail=50 2>/dev/null || echo "(container not currently running)"
  echo
done

echo "Next: see docs/runbooks/pod-crash-looping.md for common causes and fixes."
