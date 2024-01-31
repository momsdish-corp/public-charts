#!/bin/bash

set -e

# Print usage
print_usage() {
  echo "Ths script runs a test on a website."
  echo
  echo "Usage: $(dirname "$0")/$(basename "$0") --url=\"https://localhost:8443/about\" --status-code=\"301\" --redirects-to=\"https://localhost:8443/about/\""
  echo "Usage: $(dirname "$0")/$(basename "$0") --url=\"https://localhost:8443/\" --css-selector=\"title\" --text=\"My case-sensitive title!\""
  echo "--url                (string) (required) URL to fetch"
  echo "--status-code        (number) (optional) Expected status code. Default: 200."
  echo "--redirects-to       (string) (optional) Full URL of the expected redirect."
  echo "--css-selector       (string) (optional) CSS selector to require"
  echo "--text               (string) (optional) Case-sensitive value to expect. Requires --css-selector."
  echo "--debug                       (optional) Show debug/verbose output"
  echo "--help                                   Help"
}

# Arguments handling
while (( ${#} > 0 )); do
  case "${1}" in
    ( '--url='* ) URL="${1#*=}" ;;
  	( '--status-code='* ) STATUS_CODE="${1#*=}" ;;
    ( '--redirects-to='* ) REDIRECTS_TO="${1#*=}" ;;
    ( '--css-selector='* ) CSS_SELECTOR="${1#*=}" ;;
    ( '--text='* ) TEXT="${1#*=}" ;;
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

test_status_code() {
	is_true "$DEBUG" && echo "Executing test_status_code()"

  local 'url' 'status_code'

  # Arguments handling
  while (( ${#} > 0 )); do
    case "${1}" in
      ( '--url='* ) url="${1#*=}" ;;
      ( '--status-code='* ) status_code="${1#*=}" ;;
    esac
    shift
  done

  echo "Expecting status code $status_code on $url..."

  output_result=$(curl --connect-timeout 5 --max-time 10 --insecure --silent --output /dev/null -w "%{http_code}" "$url")

  if [[ "$output_result" == "$status_code" ]]; then
    echo "Test passed!"
  else
    echo "Error! Returned status code $output_result. Test failed!"
    exit 1
  fi
}

test_redirects_to() {
  is_true "$DEBUG" && echo "Executing test_redirects_to()"

  local 'url' 'redirects_to'

  # Arguments handling
  while (( ${#} > 0 )); do
    case "${1}" in
      ( '--url='* ) url="${1#*=}" ;;
      ( '--redirects-to='* ) redirects_to="${1#*=}" ;;
    esac
    shift
  done

  echo "Expecting for $url to redirect to $redirects_to..."

  output_result=$(curl --connect-timeout 5 --max-time 10 --location --insecure --silent --output /dev/null -w "%{url_effective}" "$url")

  if [[ "$output_result" == "$redirects_to" ]]; then
    echo "Test passed!"
  else
    echo "Error! URL redirected to $output_result. Test failed!"
    exit 1
  fi
}

test_css_selector() {
  is_true "$DEBUG" && echo "Executing test_css_selector()"

  local 'url' 'css_selector'

  # Arguments handling
  while (( ${#} > 0 )); do
    case "${1}" in
      ( '--url='* ) url="${1#*=}" ;;
      ( '--css-selector='* ) css_selector="${1#*=}" ;;
    esac
    shift
  done

  echo "Expecting css selector ($css_selector) to match element on $url."

  output_result=$(curl --connect-timeout 5 --max-time 10 --insecure --silent "$url" | htmlq "$css_selector")

  # If selection returns value, pass
  if [[ -n "$output_result" ]]; then
    echo "Test passed!"
  else
    echo "Error! Unable to find the element. Test failed!"
    exit 1
  fi
}

test_text() {
  is_true "$DEBUG" && echo "Executing test_text()"

  local 'url' 'css_selector' 'text'

  # Arguments handling
  while (( ${#} > 0 )); do
    case "${1}" in
      ( '--url='* ) url="${1#*=}" ;;
      ( '--css-selector='* ) css_selector="${1#*=}" ;;
      ( '--text='* ) text="${1#*=}" ;;
    esac
    shift
  done

  echo "Expecting css selector ($css_selector) to match text ($text) on $url."

  output_result=$(curl --connect-timeout 5 --max-time 10 --insecure --silent "$url" | htmlq --text "$css_selector")

  # If selection returns value, pass
  if [[ "$output_result" == "$text" ]]; then
    echo "Test passed!"
  else
  	if [[ -n "$output_result" ]]; then
  		truncated_output_result="$(echo "$output_result" | head -c 40)..."
			echo "Error! Unable to match text. Text received ($truncated_output_result). Test failed!"
			exit 1
		else
			echo "Error! Unable to find the element. Test failed!"
			exit 1
		fi
  fi
}

##############
### Script ###
##############

start_timer

# Validate
if [[ -z "$URL" ]]; then
  echo "Error! URL is required."
  exit 1
fi

# Test
# - If no tests passed, request to check the URL for status code 200
if [[ -z "$STATUS_CODE" ]] && [[ -z "$REDIRECTS_TO" ]] && [[ -z "$CSS_SELECTOR" ]]; then
	STATUS_CODE=200
fi

# - Check status code
if [[ -n "$STATUS_CODE" ]]; then
	test_status_code --url="$URL" --status-code="$STATUS_CODE"
fi

# Checks redirects
if [[ -n "$REDIRECTS_TO" ]]; then
  test_redirects_to --url="$URL" --redirects-to="$REDIRECTS_TO"
fi

# Check html elements
if [[ -n "$TEXT" ]]; then
	# If text is provided, require css selector
	if [[ -z "$CSS_SELECTOR" ]]; then
		echo "Error! --text requires --css-selector."
		exit 1
	fi
	test_text --url="$URL" --css-selector="$CSS_SELECTOR" --text="$TEXT"
elif [[ -n "$CSS_SELECTOR" ]]; then
	# Else, check css selector if it's provided
	test_css_selector --url="$URL" --css-selector="$CSS_SELECTOR"
fi

show_timer