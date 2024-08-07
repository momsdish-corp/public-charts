#!/bin/bash

# Create an s3 bucket
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
sleep 10

# Upload some directory to the bucket before testing
MINIO_POD="$(kubectl --namespace=minio get pods -l app.kubernetes.io/name=minio -o jsonpath="{.items[0].metadata.name}")"
kubectl --namespace minio cp ../s3-pull/README.md "$MINIO_POD":/tmp
kubectl --namespace=minio exec "$MINIO_POD" -- bash -c "echo 'README.md' > /tmp/.latest && \
  mc config host add minio https://localhost:9000 root password --insecure && \
  mc cp --recursive /tmp/README.md minio/mybucket/subfolder"

# Helm apply the s3-pull chart
helm upgrade --install s3-pull . \
  --namespace=s3-pull \
  --create-namespace \
  --set noVerifySSL=true \
  --set container.env.S3_ACCESS_KEY=root \
  --set container.env.S3_SECRET_KEY=password \
  --set container.env.S3_ENDPOINT=minio.minio.svc.cluster.local:9000 \
  --set container.env.S3_BUCKET=mybucket \
  --set container.env.S3_PATH=subfolder/README.md

# Show logs
S3_PULL_POD="$(kubectl --namespace=s3-pull get pods -l job-name=s3-pull-job -o jsonpath="{.items[0].metadata.name}")"
sleep 10
kubectl --namespace=s3-pull logs "$S3_PULL_POD" --container=aws-cli --follow
sleep 10
# Require that /s3-data/README.md and /s3-data/.pull files exist
kubectl --namespace=s3-pull exec "$S3_PULL_POD" --container=busybox -- sh -c 'if [ ! -f /s3-data/README.md ] || [ ! -f /s3-data/.pull ]; then exit 1; else rm /s3-data/.pull; fi'
kubectl --namespace=s3-pull logs "$S3_PULL_POD" --container=busybox --follow
