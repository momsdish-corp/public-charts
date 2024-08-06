#!/bin/bash

# Create namespace if it doesn't exist
kubectl create namespace cloudflare-recache || true

# Create a fake website
kubectl create configmap nginx-static-site \
  --namespace=cloudflare-recache \
  --from-literal=index.html='<h1>Hello, World!</h1>' \
  --from-literal=page1.html='<h1>Hello, World!</h1>' \
  --from-literal=page2.html='<h1>Hello, World!</h1>' \
  --from-literal=sitemap.xml='<urlset><url><loc>http://nginx/page1.html</loc></url><url><loc>http://nginx/page2.html</loc></url></urlset>'

helm upgrade --install nginx \
  --namespace=cloudflare-recache \
  --create-namespace \
  --set staticSiteConfigmap=nginx-static-site \
  oci://registry-1.docker.io/bitnamicharts/nginx

# Wait for the nginx pod to be ready
kubectl --namespace=cloudflare-recache wait --for=condition=ready pod --selector=app.kubernetes.io/name=nginx --timeout=120s

# Apply the chart
helm upgrade --install cloudflare-recache . \
  --namespace=cloudflare-recache \
  --create-namespace \
  --values test.yaml

# Show logs
SIMPLE_CRAWLER_POD="$(kubectl --namespace=cloudflare-recache get pods -l job-name=cloudflare-recache-job -o jsonpath="{.items[0].metadata.name}")"
sleep 10
kubectl --namespace=cloudflare-recache logs "$SIMPLE_CRAWLER_POD" --container=htmlq --follow