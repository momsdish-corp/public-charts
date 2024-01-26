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

# Helm apply the object-storage-push chart
helm upgrade --install object-storage-push . \
  --namespace=object-storage-push \
  --create-namespace \
  --set activeDeadlineSeconds=120 \
  --set noVerifySSL=true \
  --set container.env.AWS_ACCESS_KEY_ID=root \
  --set container.env.AWS_SECRET_ACCESS_KEY=password \
  --set container.env.OBJECT_STORAGE_ENDPOINT=minio.minio.svc.cluster.local:9000 \
  --set container.env.OBJECT_STORAGE_BUCKET=mybucket \
  --set container.env.OBJECT_STORAGE_DIR=subfolder \
  --set container.env.OBJECT_STORAGE_SOURCE="object-storage-push"

# Wait for the object-storage-push pod to be ready
kubectl --namespace=object-storage-push wait --for=condition=ready pod --selector=app.kubernetes.io/name=object-storage-push --timeout=120s

# Copy the object-storage-push directory to the object-storage-push pod
POD="$(kubectl --namespace=object-storage-push get pods -l app.kubernetes.io/name=object-storage-push -o jsonpath="{.items[0].metadata.name}")"
kubectl --namespace=object-storage-push cp ../object-storage-push "$POD":/files

# Mark it as ready
kubectl --namespace=object-storage-push exec "$POD" -- touch /files/.ready
# Show logs
kubectl --namespace=object-storage-push logs -f "$POD" --follow