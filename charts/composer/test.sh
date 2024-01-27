#!/bin/bash

# Apply the chart
helm upgrade --install composer . \
  --namespace=composer \
  --create-namespace \
  --set waitSeconds=120 \

# Wait for the pod to be ready
kubectl --namespace=composer wait --for=condition=ready pod --selector=app.kubernetes.io/name=composer --timeout=120s

# Try running commands
composer_POD="$(kubectl --namespace=composer get pods -l app.kubernetes.io/name=composer -o jsonpath="{.items[0].metadata.name}")"
kubectl --namespace=composer exec "$composer_POD" -- composer --version