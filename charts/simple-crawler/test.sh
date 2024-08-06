#!/bin/bash

# Create namespace if it doesn't exist
kubectl create namespace simple-crawler || true

# Create a fake website
kubectl create configmap nginx-static-site \
  --namespace=simple-crawler \
  --from-literal=index.html='<h1>Hello, World!</h1>' \
  --from-literal=page1.html='<h1>Hello, World!</h1>' \
  --from-literal=page2.html='<h1>Hello, World!</h1>' \
  --from-literal=sitemap.xml='<urlset><url><loc>http://nginx/page1.html</loc></url><url><loc>http://nginx/page2.html</loc></url></urlset>'

helm upgrade --install nginx \
  --namespace=simple-crawler \
  --create-namespace \
  --set staticSiteConfigmap=nginx-static-site \
  oci://registry-1.docker.io/bitnamicharts/nginx

# Wait for the nginx pod to be ready
kubectl --namespace=simple-crawler wait --for=condition=ready pod --selector=app.kubernetes.io/name=nginx --timeout=120s

# Apply the chart
helm upgrade --install simple-crawler . \
  --namespace=simple-crawler \
  --create-namespace \
  --values test.yaml

# Show logs
SIMPLE_CRAWLER_POD="$(kubectl --namespace=simple-crawler get pods -l job-name=simple-crawler-job -o jsonpath="{.items[0].metadata.name}")"
sleep 10
kubectl --namespace=simple-crawler logs "$SIMPLE_CRAWLER_POD" --container=htmlq --follow