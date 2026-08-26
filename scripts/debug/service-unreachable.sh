#!/usr/bin/env bash
# Debug helper for "service X can't reach service Y" / connection refused
# / DNS resolution failures inside the cluster.
# Usage: ./scripts/debug/service-unreachable.sh <service-name> [namespace]
set -euo pipefail

SVC="${1:?Usage: $0 <service-name> [namespace]}"
NAMESPACE="${2:-online-boutique}"

echo "=================================================================="
echo "Reachability check: service=$SVC (namespace: $NAMESPACE)"
echo "=================================================================="

echo
echo "--- does the Service exist, and does it have endpoints? ---"
kubectl -n "$NAMESPACE" get svc "$SVC" 2>&1 || { echo "Service '$SVC' not found in namespace '$NAMESPACE'."; exit 1; }
echo
kubectl -n "$NAMESPACE" get endpoints "$SVC" 2>&1
echo "  (if ADDRESSES is empty: the Service's selector doesn't match any Ready pod —"
echo "   check 'kubectl get pods -l <selector>' against the Service's spec.selector)"

echo
echo "--- backing pods: are they Running and Ready? ---"
SELECTOR=$(kubectl -n "$NAMESPACE" get svc "$SVC" -o jsonpath='{.spec.selector}' | tr -d '{}"' | tr ',' '\n' | sed 's/:/=/' | paste -sd, -)
kubectl -n "$NAMESPACE" get pods -l "$SELECTOR" -o wide

echo
echo "--- DNS resolution from inside the cluster ---"
kubectl -n "$NAMESPACE" run dns-test-"$RANDOM" --rm -i --restart=Never --image=busybox:1.36 -- \
  nslookup "$SVC.$NAMESPACE.svc.cluster.local" || echo "DNS lookup failed — check CoreDNS: kubectl -n kube-system get pods -l k8s-app=kube-dns"

echo
echo "--- TCP connectivity to the Service port ---"
PORT=$(kubectl -n "$NAMESPACE" get svc "$SVC" -o jsonpath='{.spec.ports[0].port}')
kubectl -n "$NAMESPACE" run conn-test-"$RANDOM" --rm -i --restart=Never --image=busybox:1.36 -- \
  sh -c "nc -zv -w3 $SVC.$NAMESPACE.svc.cluster.local $PORT" || echo "TCP connection failed — port not open, NetworkPolicy blocking it, or the app isn't listening"

echo
echo "--- NetworkPolicies in this namespace (can silently block traffic) ---"
kubectl -n "$NAMESPACE" get networkpolicy 2>&1 || echo "(none found)"

echo
echo "Common causes in this app:"
echo "  - Service selector doesn't match pod labels (deploy/manifest typo)"
echo "  - Target pods exist but aren't Ready (readiness probe failing) -- see"
echo "    ./scripts/debug/pod-crash.sh $SVC"
echo "  - Wrong port: gRPC services here typically listen on a specific port"
echo "    that must match both the container port and the Service's targetPort"
echo "  - On minikube: if this is being reached from outside the cluster, remember"
echo "    'minikube tunnel' or 'minikube service <name>' is required for LoadBalancer/NodePort access"
