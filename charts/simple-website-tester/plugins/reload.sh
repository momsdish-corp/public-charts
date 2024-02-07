#!/bin/bash

set -e

# Print usage
print_usage() {
  echo "Ths script reloads a path on a website."
  echo
  echo "Usage: $(dirname "$0")/$(basename "$0") --url=\"https://localhost:8443/about\" --count=\"3\" --interval-seconds=\"5\""
  echo "--url                (string) (required) URL to fetch"
  echo "--count							 (number) (optional) Number of times to reload. Default is 1."
  echo "--interval-seconds   (number) (optional) Interval in seconds between reloads. Default is 3 seconds."
  echo "--debug                       (optional) Show debug/verbose output"
  echo "--help                                   Help"
}

# Arguments handling
while (( ${#} > 0 )); do
  case "${1}" in
    ( '--url='* ) URL="${1#*=}" ;;
  	( '--count='* ) COUNT="${1#*=}" ;;
		( '--interval-seconds='* ) INTERVAL_SECONDS="${1#*=}" ;;
  	( '--debug' ) DEBUG=1 ;;
    ( * ) print_usage
          exit 1;;
  esac
  shift
done


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
	if is_true "$DEBUG"; then
  	echo "$(($(date +%s)-START_TIME)) seconds passed since the start of script."
	else
		:
	fi
}

exit_message() {
  # Wait for 5 seconds to allow k8s to collect logs
  echo "Error! $1" && \
    sleep "$WAIT_BEFORE_EXIT" && \
    exit 1
}

##############
### Script ###
##############

start_timer

# Validate
if [[ -z "$URL" ]]; then
  exit_message "URL is required."
fi

echo "Reloading $URL ($COUNT times)"
for (( i=1; i<=$COUNT; i++ )); do
	# Get the basic information of the URL
  RETURNED_WRITE_OUT=$(curl --connect-timeout 5 --max-time 10 --insecure --silent --output /dev/null --write-out "\nRETURNED_STATUS_CODE: %{response_code}\nRETURNED_REDIRECT_URL: %{redirect_url}\nRETURNED_SIZE: %{size_download}\nRETURNED_LOAD_TIME: %{time_total}\n" "$URL")
  RETURNED_STATUS_CODE=$(echo "$RETURNED_WRITE_OUT" | grep "RETURNED_STATUS_CODE" | awk '{print $2}')
  RETURNED_REDIRECT_URL=$(echo "$RETURNED_WRITE_OUT" | grep "RETURNED_REDIRECT_URL" | awk '{print $2}')
  RETURNED_SIZE=$(echo "$RETURNED_WRITE_OUT" | grep "RETURNED_SIZE" | awk '{print $2}')
  RETURNED_LOAD_TIME=$(echo "$RETURNED_WRITE_OUT" | grep "RETURNED_LOAD_TIME" | awk '{print $2}')

	echo "Count: $i of $COUNT"
	echo "Status code: $RETURNED_STATUS_CODE"
	echo "Redirects to: $RETURNED_REDIRECT_URL"
	echo "Size: $RETURNED_SIZE"
	echo "Load time: $RETURNED_LOAD_TIME"

	sleep "$INTERVAL_SECONDS"
done

show_timer
