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

require_value_match() {
	is_true "$DEBUG" && echo "Executing require_value_match()" || true

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

	echo "Requiring $name to match: $match"

	if [[ "$value" == "$match" ]]; then
		echo "Test passed!"
	else
		exit_message "Test failed! Returned $name: $value"
	fi
}

require_value() {
	is_true "$DEBUG" && echo "Executing require_value()" || true

	local 'name' 'value'

	# Arguments handling
	while (( ${#} > 0 )); do
		case "${1}" in
			( '--name='* ) name="${1#*=}" ;;
			( '--value='* ) value="${1#*=}" ;;
		esac
		shift
	done

	echo "Requiring $name to exist"

	if [[ -n "$value" ]]; then
		echo "Test passed!"
	else
		exit_message "Test failed!"
	fi
}

require_value_no_match() {
  is_true "$DEBUG" && echo "Executing require_value_no_match()" || true

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

  echo "Requiring $name not to match: $match"

  if [[ "$value" != "$match" ]]; then
    echo "Test passed!"
  else
    exit_message "Test failed!"
  fi
}

require_no_value() {
  is_true "$DEBUG" && echo "Executing require_no_value()" || true

  local 'name' 'value'

  # Arguments handling
  while (( ${#} > 0 )); do
    case "${1}" in
      ( '--name='* ) name="${1#*=}" ;;
      ( '--value='* ) value="${1#*=}" ;;
    esac
    shift
  done

  echo "Requiring $name not to exist"

  if [[ -z "$value" ]]; then
    echo "Test passed!"
  else
    exit_message "Test failed!"
  fi
}

###############
### Globals ###
###############

# Print usage
print_usage() {
  echo "Description:"
  echo "Ths script runs a test on a web page. All passed flag values must be URL encoded."
  echo
  echo "Usage: $(dirname "$0")/$(basename "$0") --baseURL=\"$(return_url_encoded https://localhost:8443)\" --path=\"$(return_url_encoded /about)\" --statusCode=\"$(return_url_encoded 301)\" --redirectsTo=\"$(return_url_encoded https://localhost:8443/about/)\""
  echo "Usage: $(dirname "$0")/$(basename "$0") --baseURL=\"$(return_url_encoded https://localhost:8443/)\" --cssSelector=$(return_url_encoded 'title:text(\"My case-sensitive title!\")')"
  echo "--baseURL            (string) (required) URL to fetch, including the protocol and port."
  echo "--path               (string) (optional) Path, relative to the URL."
  echo "--timeout            (number) (optional) Max time to wait in seconds. You may use decimals. Default is 10 seconds."
  echo "--statusCode         (number) (optional) Expected status code. Defaults to 200."
  echo "--redirectsTo        (string) (optional) Full URL of the expected redirect."
  echo "--cssSelector        (string) (optional) CSS selector to require. Append :text(text) to require a specific text. Allows for multiple selectors."
  echo "--antiCssSelector    (string) (optional) CSS selector to require not to exist. Append :text(text) to require a specific text not to exist (this does not require a text containing element to exist). Allows for multiple selectors."
  echo "--waitBeforeExit     (number) (optional) Wait time in seconds before exiting the script. Default is 1 second."
  echo "--debug                       (optional) Show debug/verbose output"
  echo "--help                                   Help"
}

# Set defaults
TIMEOUT_SECONDS=10
EXPECTING_STATUS_CODE=200
WAIT_BEFORE_EXIT=1

# Arguments handling
while (( ${#} > 0 )); do
  case "${1}" in
    ( '--baseURL='* ) BASE_URL="$(return_url_decoded "${1#*=}")" ;;
  	( '--path='* ) URL_PATH="$(return_url_decoded "${1#*=}")" ;;
    ( '--timeout='* ) TIMEOUT_SECONDS="$(return_number "${1#*=}")" ;;
  	( '--statusCode='* ) EXPECTING_STATUS_CODE="$(return_number "${1#*=}")" ;;
    ( '--redirectsTo='* ) EXPECTING_REDIRECTS_TO="$(return_url_decoded "${1#*=}")" ;;
    ( '--cssSelector='* ) EXPECTING_CSS_SELECTOR+=("$(return_url_decoded "${1#*=}")") ;; # Store in an array
    ( '--antiCssSelector='* ) EXPECTING_ANTI_CSS_SELECTOR+=("$(return_url_decoded "${1#*=}")") ;; # Store in an array
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

# Get the basic information of the URL
echo "### Fetching ${BASE_URL}${URL_PATH} ###"
# - Instead of exiting on curl error, show error, then exit
RETURNED_CURL=$(curl --connect-timeout "$TIMEOUT_SECONDS" --max-time "$TIMEOUT_SECONDS" --insecure --silent --write-out "\n---BEGIN WRITE-OUT---\nRETURNED_STATUS_CODE: %{response_code}\nRETURNED_REDIRECT_URL: %{redirect_url}\nRETURNED_SIZE: %{size_download}\nRETURNED_LOAD_TIME: %{time_total}\n" "${BASE_URL}${URL_PATH}" 2>/dev/null) || true
# shellcheck disable=SC2181
if [[ $? -ne 0 ]]; then
  echo "$RETURNED_CURL"
  exit_message "Curl failed to fetch the ${BASE_URL}${URL_PATH} in under ${TIMEOUT_SECONDS}s."
fi
RETURNED_HTML=$(echo "$RETURNED_CURL" | perl -pe 'last if /---BEGIN WRITE-OUT---/')
RETURNED_WRITE_OUT=$(echo "$RETURNED_CURL" | perl -0777 -pe 's/.*?---BEGIN WRITE-OUT---\n//s')
RETURNED_STATUS_CODE=$(echo "$RETURNED_WRITE_OUT" | grep "RETURNED_STATUS_CODE" | awk '{print $2}')
RETURNED_REDIRECT_URL=$(echo "$RETURNED_WRITE_OUT" | grep "RETURNED_REDIRECT_URL" | awk '{print $2}')
RETURNED_SIZE=$(echo "$RETURNED_WRITE_OUT" | grep "RETURNED_SIZE" | awk '{print $2}')
RETURNED_LOAD_TIME=$(echo "$RETURNED_WRITE_OUT" | grep "RETURNED_LOAD_TIME" | awk '{print $2}')
RETURNED_PAGE_TITLE=$(echo "$RETURNED_HTML" | htmlq --text "title")
echo "> Status code: $RETURNED_STATUS_CODE"
echo "> Redirects to: $RETURNED_REDIRECT_URL"
echo "> Size: $RETURNED_SIZE"
echo "> Load time: $RETURNED_LOAD_TIME"
echo "> Page title: $RETURNED_PAGE_TITLE"

# Check status code
if [[ -n "$EXPECTING_STATUS_CODE" ]]; then
	echo '-'
	require_value_match --name="status code" --value="$RETURNED_STATUS_CODE" --match="$EXPECTING_STATUS_CODE"
fi

# Checks redirects
if [[ -n "$EXPECTING_REDIRECTS_TO" ]]; then
	echo '-'
	require_value_match --name="redirects to" --value="$RETURNED_REDIRECT_URL" --match="${BASE_URL}${EXPECTING_REDIRECTS_TO}"
fi

# Check html elements
if [[ -n "$EXPECTING_CSS_SELECTOR" ]]; then
	for selector_text in "${EXPECTING_CSS_SELECTOR[@]}"; do
		echo '-'
		selector=$(echo "$selector_text" | perl -n -e "/(.*?)(?=:text|$)/ && print \$1")
		text=$(echo "$selector_text" | perl -n -e "/(?<=:text\()[\"']?([^\"']*)[\"']?(?=\))/ && print \$1")

		if [[ -z "$text" ]]; then
		  # If text is empty, check for the existence of the element
		  RETURNED_ELEMENT=$(echo "$RETURNED_HTML" | htmlq "$selector")
		  require_value --name="CSS selector ($selector)" --value="$RETURNED_ELEMENT"
    else
      # If text is not empty, check for the existence of the element and its text
			RETURNED_ELEMENT_TEXT=$(echo "$RETURNED_HTML" | htmlq --text "$selector")
			require_value_match --name="CSS selector ($selector) text" --value="$RETURNED_ELEMENT_TEXT" --match="$text"
		fi
	done
fi

# Check html elements not to have
if [[ -n "$EXPECTING_ANTI_CSS_SELECTOR" ]]; then
  for selector_text in "${EXPECTING_ANTI_CSS_SELECTOR[@]}"; do
    echo '-'
    selector=$(echo "$selector_text" | perl -n -e "/(.*?)(?=:text|$)/ && print \$1")
    text=$(echo "$selector_text" | perl -n -e "/(?<=:text\()[\"']?([^\"']*)[\"']?(?=\))/ && print \$1")

    if [[ -z "$text" ]]; then
      # If text is empty, check for the existence of the element
      RETURNED_ELEMENT=$(echo "$RETURNED_HTML" | htmlq "$selector")
      require_no_value --name="CSS selector ($selector)" --value="$RETURNED_ELEMENT"
    else
      RETURNED_ELEMENT_TEXT=$(echo "$RETURNED_HTML" | htmlq --text "$selector")
      require_value_no_match --name="CSS selector ($selector) text" --value="$RETURNED_ELEMENT_TEXT" --match="$text"
    fi
  done
fi

show_timer
