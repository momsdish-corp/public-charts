#!/bin/bash

# Apply the chart
helm upgrade --install simple-website-tester . \
  --namespace=simple-website-tester \
  --create-namespace \
  --values test.yaml

# Wait for the pod to be ready
kubectl --namespace=simple-website-tester wait --for=condition=ready pod --selector=app.kubernetes.io/name=simple-website-tester --timeout=120s

# Show logs
SIMPLE_WEBSITE_TESTER_POD="$(kubectl --namespace=simple-website-tester get pods -l app.kubernetes.io/name=simple-website-tester -o jsonpath="{.items[0].metadata.name}")"
kubectl --namespace=simple-website-tester logs "$SIMPLE_WEBSITE_TESTER_POD" --follow