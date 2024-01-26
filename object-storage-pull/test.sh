#!/bin/bash

# Create an object-storage bucket
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install minio bitnami/minio --version 13.2.1 \
  --namespace minio \
  --create-namespace \
  --set auth.rootUser=root \
  --set auth.rootPassword=password \
  --set defaultBuckets="mybucket" \
  --set persistence.enabled=false \
  --set tls.enabled=true \
  --set tls.autoGenerated=true

# Wait for the minio pod to be ready
kubectl --namespace=minio wait --for=condition=ready pod --selector=app.kubernetes.io/name=minio --timeout=120s

# Wait for the minio service to create the bucket
sleep 5

# Upload some directory to the bucket before testing
MINIO_POD="$(kubectl --namespace=minio get pods -l app.kubernetes.io/name=minio -o jsonpath="{.items[0].metadata.name}")"
kubectl --namespace minio cp ../object-storage-pull "$MINIO_POD":/tmp
kubectl --namespace=minio exec "$MINIO_POD" -- bash -c "echo 'object-storage-pull' > /tmp/.last-push && \
  mc config host add minio https://localhost:9000 root password --insecure && \
  mc cp --recursive /tmp/object-storage-pull minio/mybucket/subfolder"

# Helm apply the object-storage-pull chart
helm upgrade --install object-storage-pull . \
  --namespace=object-storage-pull \
  --create-namespace \
  --set waitSeconds=120 \
  --set noVerifySSL=true \
  --set container.env.AWS_ACCESS_KEY_ID=root \
  --set container.env.AWS_SECRET_ACCESS_KEY=password \
  --set container.env.OBJECT_STORAGE_ENDPOINT=minio.minio.svc.cluster.local:9000 \
  --set container.env.OBJECT_STORAGE_BUCKET=mybucket \
  --set container.env.OBJECT_STORAGE_DIR=subfolder \
  --set container.env.OBJECT_STORAGE_SOURCE="object-storage-pull"

# Wait for the object-storage-pull pod to start
sleep 5

# Show logs
OBJECT_STORAGE_PULL_POD="$(kubectl --namespace=object-storage-pull get pods -l app.kubernetes.io/name=object-storage-pull -o jsonpath="{.items[0].metadata.name}")"
kubectl --namespace=object-storage-pull logs "$OBJECT_STORAGE_PULL_POD" --container=aws-cli --follow
