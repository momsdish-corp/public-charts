#!/bin/bash

set -e

# Print usage
print_usage() {
  echo "Ths script runs a test on a website."
  echo
  echo "Usage: $(dirname "$0")/$(basename "$0") --url=\"https://localhost:8443/about\" --status-code=\"301\" --redirects-to=\"https://localhost:8443/about/\""
  echo "Usage: $(dirname "$0")/$(basename "$0") --url=\"https://localhost:8443/\" --css-selector=\"title\" --text=\"My case-sensitive title!\""
  echo "--url                (string) (required) URL to fetch"
  echo "--status-code        (number) (optional) Expected status code. If --status-code and --redirects-to is not provided, it defaults to 200."
  echo "--redirects-to       (string) (optional) Full URL of the expected redirect."
  echo "--css-selector       (string) (optional) CSS selector to require"
  echo "--text               (string) (optional) Case-sensitive value to expect. Requires --css-selector."
  echo "--wait-before-exit   (number) (optional) Wait time in seconds before exiting the script. Default is 0 seconds."
  echo "--debug                       (optional) Show debug/verbose output"
  echo "--help                                   Help"
}

# Arguments handling
while (( ${#} > 0 )); do
  case "${1}" in
    ( '--url='* ) URL="${1#*=}" ;;
  	( '--status-code='* ) EXPECTING_STATUS_CODE="${1#*=}" ;;
    ( '--redirects-to='* ) EXPECTING_REDIRECTS_TO="${1#*=}" ;;
    ( '--css-selector='* ) EXPECTING_CSS_SELECTOR="${1#*=}" ;;
    ( '--text='* ) EXPECTING_TEXT="${1#*=}" ;;
    ( '--wait-before-exit='* ) WAIT_BEFORE_EXIT="${1#*=}" ;;
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

require_value_match() {
	is_true "$DEBUG" && echo "Executing require_value_match()"

	local 'name' 'value' 'match'

	# Arguments handling
	while (( ${#} > 0 )); do
		case "${1}" in
			( '--name='* ) name="${1#*=}" ;;
			( '--value='* ) value="${1#*=}" ;;
			( '--match='* ) match="${1#*=}" ;;
		esac
		shift
	done

	echo "Expecting $name: $match"

	if [[ "$value" == "$match" ]]; then
		echo "Test passed!"
	else
		exit_message "Test failed! Returned $name: $value"
	fi
}

require_value() {
	is_true "$DEBUG" && echo "Executing require_value()"

	local 'name' 'value'

	# Arguments handling
	while (( ${#} > 0 )); do
		case "${1}" in
			( '--name='* ) name="${1#*=}" ;;
			( '--value='* ) value="${1#*=}" ;;
		esac
		shift
	done

	echo "Expecting $name to exist"

	if [[ -n "$value" ]]; then
		echo "Test passed!"
	else
		exit_message "Test failed!"
	fi
}

##############
### Script ###
##############

start_timer

# Validate
if [[ -z "$URL" ]]; then
  exit_message "URL is required."
fi

# Set defaults
# - If no tests passed, request to check the URL for status code 200
if [[ -z "$EXPECTING_STATUS_CODE" ]] && [[ -z "$EXPECTING_REDIRECTS_TO" ]] && [[ -z "$EXPECTING_CSS_SELECTOR" ]]; then
	EXPECTING_STATUS_CODE=200
fi

# Get the basic information of the URL
RETURNED_CURL=$(curl --connect-timeout 5 --max-time 10 --insecure --silent --write-out "\n---BEGIN WRITE-OUT---\nRETURNED_STATUS_CODE: %{response_code}\nRETURNED_REDIRECT_URL: %{redirect_url}\nRETURNED_SIZE: %{size_download}\nRETURNED_LOAD_TIME: %{time_total}\n" "$URL")
RETURNED_HTML=$(echo "$RETURNED_CURL" | perl -pe 'last if /---BEGIN WRITE-OUT---/')
RETURNED_WRITE_OUT=$(echo "$RETURNED_CURL" | perl -0777 -pe 's/.*?---BEGIN WRITE-OUT---\n//s')
RETURNED_STATUS_CODE=$(echo "$RETURNED_WRITE_OUT" | grep "RETURNED_STATUS_CODE" | awk '{print $2}')
RETURNED_REDIRECT_URL=$(echo "$RETURNED_WRITE_OUT" | grep "RETURNED_REDIRECT_URL" | awk '{print $2}')
RETURNED_SIZE=$(echo "$RETURNED_WRITE_OUT" | grep "RETURNED_SIZE" | awk '{print $2}')
RETURNED_LOAD_TIME=$(echo "$RETURNED_WRITE_OUT" | grep "RETURNED_LOAD_TIME" | awk '{print $2}')
RETURNED_PAGE_TITLE=$(echo "$RETURNED_HTML" | htmlq --text "title")

echo "Testing URL: $URL"
echo "Status code: $RETURNED_STATUS_CODE"
echo "Redirects to: $RETURNED_REDIRECT_URL"
echo "Size: $RETURNED_SIZE"
echo "Load time: $RETURNED_LOAD_TIME"
echo "Page title: $RETURNED_PAGE_TITLE"


# Test
# - Check status code
if [[ -n "$EXPECTING_STATUS_CODE" ]]; then
	require_value_match --name="status code" --value="$RETURNED_STATUS_CODE" --match="$EXPECTING_STATUS_CODE"
fi

# Checks redirects
if [[ -n "$EXPECTING_REDIRECTS_TO" ]]; then
	require_value_match --name="redirects to" --value="$RETURNED_REDIRECT_URL" --match="$EXPECTING_REDIRECTS_TO"
fi

# Check html elements
if [[ -n "$EXPECTING_CSS_SELECTOR" ]]; then
	RETURNED_ELEMENT=$(echo "$RETURNED_HTML" | htmlq "$EXPECTING_CSS_SELECTOR")
  require_value --name="CSS selector ($EXPECTING_CSS_SELECTOR)" --value="$RETURNED_ELEMENT"
  if [[ -n "$EXPECTING_TEXT" ]]; then
  	RETURNED_ELEMENT_TEXT=$(echo "$RETURNED_HTML" | htmlq --text "$EXPECTING_CSS_SELECTOR")
		require_value_match --name="CSS selector ($EXPECTING_CSS_SELECTOR) text" --value="$RETURNED_ELEMENT_TEXT" --match="$EXPECTING_TEXT"
	fi
elif [[ -n "$EXPECTING_TEXT" ]]; then
	exit_message "--text requires --css-selector."
fi

show_timer