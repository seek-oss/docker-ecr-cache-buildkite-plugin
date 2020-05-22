log_fatal() {
  echo "${@}"
  # use the last argument as the exit code
  exit_code="${*: -1}"
  if [[ "${exit_code}" =~ ^[\d]+$ ]]; then
    exit "${exit_code}"
  fi
  exit 1
}