#!/bin/bash

# Apply the chart
helm upgrade --install mariadb-dev . \
  --namespace=mariadb-dev \
  --create-namespace \
  --set container.env.MARIADB_ROOT_PASSWORD=password \
  --set persistence.enabled=true \
  --set persistence.size=1Gi

# Wait for the pod to be ready
kubectl --namespace=mariadb-dev wait --for=condition=ready pod --selector=app.kubernetes.io/instance=mariadb-dev --timeout=120s

# Try running commands
MARIADB_DEV_POD="$(kubectl --namespace=mariadb-dev get pods -l app.kubernetes.io/name=mariadb-dev -o jsonpath="{.items[0].metadata.name}")"
kubectl --namespace=mariadb-dev exec "$MARIADB_DEV_POD" -- mysql --user=root --password=password --host mariadb-dev-svc --execute="SHOW DATABASES;"