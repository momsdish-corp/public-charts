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

return_url_encoded() {
  # Usage: url_encode "string"
  printf '%s\n' "$1" | awk -v ORS="" '{ gsub(/./,"&\n") ; print }' | while read -r line ; do
    printf %s "${line}" | grep -q "[^-._~0-9a-zA-Z]" && printf '%%%02X' "'${line}" || printf %s "${line}"
  done
  printf '\n'
}

return_url_decoded() {
  # Usage: url_decode "string"
  : "${*//+/ }"
  printf '%b\n' "${_//%/\\x}"
}

return_number() {
  local re='^[0-9]+$'
  if [[ $1 =~ $re ]] ; then
    echo "$1"
  else
    echo ""
  fi
}

exit_message() {
  # Wait for 5 seconds to allow k8s to collect logs
  echo "Error! $1" && \
    sleep "$WAIT_BEFORE_EXIT" && \
    exit 1
}

###############
### Globals ###
###############

# Print usage
print_usage() {
  echo "Description:"
  echo "Ths script reloads a path on a website. All passed flag values must be URL encoded."
  echo
  echo "Usage: $(dirname "$0")/$(basename "$0") --baseURL=\"$(return_url_encoded https://localhost:8443)\" --path=\"$(return_url_encoded /some-path)\" --count=\"$(return_url_encoded 3)\" --intervalSeconds=\"$(return_url_encoded 5)\""
  echo "--baseURL            (string) (required) URL to fetch, including the protocol and port."
  echo "--waitBeforeExit     (number) (optional) Wait time in seconds before exiting the script. Default is 1 second."
  echo "--path               (string) (optional) Path, relative to the URL"
  echo "--count							 (number) (optional) Number of times to reload. Default is 1."
  echo "--intervalSeconds    (number) (optional) Interval in seconds between reloads. Default is 3 seconds."
  echo "--debug                       (optional) Show debug/verbose output"
  echo "--help                                   Help"
}

# Set defaults
INTERVAL_SECONDS=3
WAIT_BEFORE_EXIT=1

# Arguments handling
while (( ${#} > 0 )); do
  case "${1}" in
    ( '--baseURL='* ) BASE_URL="$(return_url_decoded "${1#*=}")" ;;
  	( '--path='* ) URL_PATH="$(return_url_decoded "${1#*=}")" ;;
 		( '--count='* ) COUNT="$(return_number "${1#*=}")" ;;
		( '--intervalSeconds='* ) INTERVAL_SECONDS="$(return_number "${1#*=}")" ;;
		( '--waitBeforeExit='* ) WAIT_BEFORE_EXIT="$(return_number "${1#*=}")" ;;
  	( '--debug' ) DEBUG=1 ;;
    ( * ) print_usage
          exit 1;;
  esac
  shift
done

##############
### Script ###
##############

start_timer

# Validate
if [[ -z "$BASE_URL" ]]; then
  exit_message "Missing --baseURL flag. Try --help for more information."
fi

# Plural/Singular
[[ "$COUNT" -gt 1 ]] && \
	TIMES_STRING="times (${INTERVAL_SECONDS}s pauses)" || \
	TIMES_STRING="time"

echo "### Reloading ${BASE_URL}${URL_PATH} $COUNT $TIMES_STRING ###"
for (( i=1; i<=$COUNT; i++ )); do
	# Get the basic information of the URL
	# - Do not exit if the curl timesout/fails
  RETURNED_WRITE_OUT=$(curl --connect-timeout 5 --max-time 10 --insecure --silent --output /dev/null --write-out "\nRETURNED_STATUS_CODE: %{response_code}\nRETURNED_REDIRECT_URL: %{redirect_url}\nRETURNED_SIZE: %{size_download}\nRETURNED_LOAD_TIME: %{time_total}\n" "${BASE_URL}${URL_PATH}" 2>/dev/null) || true
  if [ $? -ne 0 ]; then
    echo "$RETURNED_WRITE_OUT"
  else
    RETURNED_STATUS_CODE=$(echo "$RETURNED_WRITE_OUT" | grep "RETURNED_STATUS_CODE" | awk '{print $2}')
    RETURNED_REDIRECT_URL=$(echo "$RETURNED_WRITE_OUT" | grep "RETURNED_REDIRECT_URL" | awk '{print $2}')
    RETURNED_SIZE=$(echo "$RETURNED_WRITE_OUT" | grep "RETURNED_SIZE" | awk '{print $2}')
    RETURNED_LOAD_TIME=$(echo "$RETURNED_WRITE_OUT" | grep "RETURNED_LOAD_TIME" | awk '{print $2}')
  fi

	# Show the separator
  [[ $i != 1 ]] && echo '-'

	echo "Count: $i of $COUNT"
	echo "Status code: $RETURNED_STATUS_CODE"
	echo "Redirects to: $RETURNED_REDIRECT_URL"
	echo "Size: $RETURNED_SIZE"
	echo "Load time: $RETURNED_LOAD_TIME"

	sleep "$INTERVAL_SECONDS"
done

show_timer
