#!/bin/bash

# Apply the chart
helm upgrade --install mydumper . \
  --namespace=mydumper \
  --create-namespace \
  --set waitSeconds=120 \

# Wait for the pod to be ready
kubectl --namespace=mydumper wait --for=condition=ready pod --selector=app.kubernetes.io/name=mydumper --timeout=120s

# Try running commands
MYDUMPER_POD="$(kubectl --namespace=mydumper get pods -l app.kubernetes.io/name=mydumper -o jsonpath="{.items[0].metadata.name}")"
kubectl --namespace=mydumper exec "$MYDUMPER_POD" -- mydumper --version
kubectl --namespace=mydumper exec "$MYDUMPER_POD" -- myloader --version