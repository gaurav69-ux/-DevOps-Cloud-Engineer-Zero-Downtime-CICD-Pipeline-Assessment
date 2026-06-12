#!/bin/bash
# scripts/verify-version-consistency.sh
# Ensures all pods in a namespace run the same image tag (Knight Capital prevention)
set -euo pipefail

TARGET_TAG="${1:?Usage: $0 <image-tag> <namespace>}"
NAMESPACE="${2:?Usage: $0 <image-tag> <namespace>}"

echo "Checking version consistency: all pods in ${NAMESPACE} must run ${TARGET_TAG}"

MISMATCHED=$(kubectl get pods -n "$NAMESPACE" -l app=novapay \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}' \
  | grep -v "$TARGET_TAG" || true)

if [[ -n "$MISMATCHED" ]]; then
  echo "VERSION MISMATCH DETECTED:"
  echo "$MISMATCHED"
  echo "BLOCKING: All pods must run identical image. This prevents Knight Capital-style incidents."
  exit 1
fi

POD_COUNT=$(kubectl get pods -n "$NAMESPACE" -l app=novapay --no-headers | wc -l)
echo "✓ Version consistency check PASSED: ${POD_COUNT} pods all running ${TARGET_TAG}"