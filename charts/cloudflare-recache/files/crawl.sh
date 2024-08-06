#!/bin/bash

set -e

#################
### Functions ###
#################

# Example: is_true true && echo "true" || echo "false"
is_true() {
    local -r bool="${1:-}"
    if [[ "$bool" = 1 || "$bool" =~ ^(yes|true)$ ]]; then
        true
    else
        false
    fi
}

start_timer() {
  START_TIME=$(date +%s)
}

show_timer() {
    is_true "$DEBUG" && echo "$(($(date +%s)-START_TIME)) seconds passed since the start of script." || true
}

exit_message() {
  # Wait for 5 seconds to allow k8s to collect logs
  echo "Error! $1" && \
    sleep "$WAIT_BEFORE_EXIT" && \
    exit 1
}

crawl_url() {
    local url="$1"
    RESPONSE=$(curl -s -w "\n---BEGIN WRITE-OUT---\nHTTP_CODE:%{http_code}\nTIME_TOTAL:%{time_total}\nSIZE_DOWNLOAD:%{size_download}\n" --insecure "$url")
    WRITE_OUT=$(echo "$RESPONSE" | sed -n '/---BEGIN WRITE-OUT---/,$p' | tail -n +2)

    HTTP_CODE=$(echo "$WRITE_OUT" | grep HTTP_CODE | cut -d':' -f2)
    TIME_TOTAL=$(echo "$WRITE_OUT" | grep TIME_TOTAL | cut -d':' -f2)
    SIZE_DOWNLOAD=$(echo "$WRITE_OUT" | grep SIZE_DOWNLOAD | cut -d':' -f2)

    echo "Status: $HTTP_CODE, Time: ${TIME_TOTAL}s, Size: $SIZE_DOWNLOAD bytes"

    if [[ "$HTTP_CODE" != "200" ]]; then
        echo "Warning: Non-200 status code for $url"
    fi
}

collect_sitemaps() {
    local sitemap_url="$1"
    echo "Collecting sitemap: $sitemap_url"

    SITEMAP_CONTENT=$(curl -sL --insecure "$sitemap_url")

    # Check if it's a sitemap index
    if [[ -n "$(echo "$SITEMAP_CONTENT" | htmlq 'sitemapindex')" ]]; then
        echo "This is a sitemap index. Collecting nested sitemaps..."
        NESTED_SITEMAPS=$(echo "$SITEMAP_CONTENT" | htmlq 'sitemapindex sitemap loc' --text)
        for nested_sitemap in $NESTED_SITEMAPS; do
            collect_sitemaps "$nested_sitemap"
        done
    elif [[ -n "$(echo "$SITEMAP_CONTENT" | htmlq 'urlset')" ]]; then
        echo "Collecting URLs from sitemap..."
        URLS=$(echo "$SITEMAP_CONTENT" | htmlq 'urlset url loc' --text)
        if [[ -z "$URLS" ]]; then
            echo "No URLs found in sitemap $sitemap_url"
            return
        fi
        echo "$URLS" >> "$TEMP_URL_FILE"
    else
        echo "Unrecognized sitemap format for $sitemap_url"
    fi
}

###############
### Globals ###
###############

# Print usage
print_usage() {
  echo "Description:"
  echo "This script crawls URLs from a sitemap, including nested sitemaps."
  echo
  echo "Usage: $(dirname "$0")/$(basename "$0") --sitemap=\"https://example.com/sitemap.xml\" [--wait=1] [--purge-cache]"
  echo "--sitemap            (string) (required) URL of the sitemap to crawl."
  echo "--wait               (number) (optional) Time to wait between crawls in seconds. Default is 1 second."
  echo "--purge-cache        (bool)   (optional) Whether to purge Cloudflare cache. Requires CLOUDFLARE_ZONE_ID nad CLOUDFLARE_API_KEY env vars."
  echo "--waitBeforeExit     (number) (optional) Wait time in seconds before exiting the script. Default is 1 second."
  echo "--debug                       (optional) Show debug/verbose output"
  echo "--help                                   Help"
}

# Set defaults
WAIT_TIME=1
WAIT_BEFORE_EXIT=1
PURGE_CACHE=0
TEMP_URL_FILE=$(mktemp)

# Arguments handling
while (( ${#} > 0 )); do
  case "${1}" in
    ( '--sitemap='* ) SITEMAP_URL="${1#*=}" ;;
    ( '--wait='* ) WAIT_TIME="${1#*=}" ;;
    ( '--purge-cache' ) PURGE_CACHE=1 ;;
    ( '--waitBeforeExit='* ) WAIT_BEFORE_EXIT="${1#*=}" ;;
    ( '--debug' ) DEBUG=1 ;;
    ( '--help' ) print_usage; exit 0 ;;
    ( * ) print_usage; exit 1 ;;
  esac
  shift
done

##############
### Script ###
##############

start_timer

# Validate
if [[ -z "$SITEMAP_URL" ]]; then
  exit_message "Missing --sitemap flag. Try --help for more information."
fi

if is_true "$PURGE_CACHE" ; then
  if [[ -z "$CLOUDFLARE_ZONE_ID" ]]; then
    exit_message "CLOUDFLARE_ZONE_ID is not defined. Try --help for more information."
  fi
  if [[ -z "$CLOUDFLARE_API_KEY" ]]; then
    exit_message "CLOUDFLARE_API_KEY is not defined. Try --help for more information."
  fi
fi

if is_true "$PURGE_CACHE"; then
  echo "Phase 1: Fetching sitemap => Phase 2: Purging cache => Phase 3: Crawling pages"
else
  echo "Phase 1: Fetching sitemap => (SKIPPING) Phase 2: Purging cache => Phase 3: Crawling pages"
fi

# Phase 1: Collect all sitemaps and URLs
echo "Phase 1: Collecting all sitemaps and URLs"
collect_sitemaps "$SITEMAP_URL"

# Phase 2: Cloudflare purge all cache
if is_true "$PURGE_CACHE" ; then
  echo "Phase 2: Cache purge"
  RESPONSE="$(curl -X DELETE "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/purge_cache" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_KEY}" \
    -H "Content-Type: application/json" \
    --data '{"purge_everything":true}' \
    -w "\n---BEGIN WRITE-OUT---\nHTTP_CODE:%{http_code}\n" \
    -s)"
  BODY=$(echo "$RESPONSE" | sed -n '1,/---BEGIN WRITE-OUT---/p' | sed '$d')
  WRITE_OUT=$(echo "$RESPONSE" | sed -n '/---BEGIN WRITE-OUT---/,$p' | tail -n +2)
  HTTP_CODE=$(echo "$WRITE_OUT" | grep HTTP_CODE | cut -d':' -f2)
  echo "$BODY"
  # Require status 200 to continue
  if [[ "$HTTP_CODE" != 200 ]]; then
    exit_message "Unable to clear Cloudflare cache!"
  fi
else
  echo "(SKIPPING) Phase 2: Cache purge"
fi

# Phase 3: Crawl all collected URLs
echo "Phase 3: Crawling all collected URLs with a $WAIT_TIME second wait time"
TOTAL_URLS=$(wc -l < "$TEMP_URL_FILE")
CURRENT_URL=0

# Require URLs
if [[ "$TOTAL_URLS" -eq 0 ]]; then
    exit_message "Unable to crawl. No URLs found."
fi

while IFS= read -r url; do
    CURRENT_URL=$((CURRENT_URL + 1))
    echo "${CURRENT_URL}/${TOTAL_URLS} Crawling $url"
    crawl_url "$url"
    sleep "$WAIT_TIME"
done < "$TEMP_URL_FILE"

# Clean up
rm -f "$TEMP_URL_FILE"

show_timer
echo "Crawl completed successfully."