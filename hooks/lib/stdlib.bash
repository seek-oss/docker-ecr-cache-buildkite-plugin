echoerr() {
  echo "$@" 1>&2;
}

log_fatal() {
  echoerr "In $(pwd)"
  echoerr "${@}"
  # use the last argument as the exit code
  exit_code="${*: -1}"
  if [[ "${exit_code}" =~ ^[0-9]+$ ]]; then
    exit "${exit_code}"
  fi
  exit 1
}

read_build_args() {
  read_list_property 'BUILD_ARGS'
  for arg in ${result[@]+"${result[@]}"}; do
    build_args+=("--build-arg=${arg}")
  done
}

# read a plugin property of type [array, string] into a Bash array. Buildkite
# exposes a string value at BUILDKITE_PLUGIN_{NAME}_{KEY}, and array values at
# BUILDKITE_PLUGIN_{NAME}_{KEY}_{IDX}.
read_list_property() {
  local base_name="BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_${1}"

  result=()

  if [[ -n ${!base_name:-} ]]; then
    result+=("${!base_name}")
  fi

  while IFS='=' read -r item_name _; do
    if [[ ${item_name} =~ ^(${base_name}_[0-9]+) ]]; then
      result+=("${!item_name}")
    fi
  done < <(env | sort)
}

get_default_image_name() {
  echo "build-cache/${BUILDKITE_ORGANIZATION_SLUG}/${BUILDKITE_PIPELINE_SLUG}"
}

compute_tag() {
  local docker_file="$1"
  local sums

  echoerr '--- Computing tag'

  echoerr 'DOCKERFILE'
  echoerr "+ ${docker_file}:${target:-"<target>"}"
  # Inline Dockerfile might be saved under a different name each time,
  # only content matters
  sums="$(sha1sum < "${docker_file}")"
  sums+="$(echo "${target}" | sha1sum)"

  echoerr 'ARCHITECTURE'
  echoerr "+ $(uname -m)"
  sums+="$(uname -m | sha1sum)"

  echoerr 'BUILD_ARGS'
  read_list_property 'BUILD_ARGS'
  for arg in ${result[@]+"${result[@]}"}; do
    echoerr "+ ${arg}"

    # include underlying environment variable after echo
    if [[ ${arg} != *=* ]]; then
      arg+="=${!arg:-}"
    fi

    sums+="$(echo "${arg}" | sha1sum)"
  done

  # expand ** in cache-on properties
  shopt -s globstar

  echoerr 'CACHE_ON'
  read_list_property 'CACHE_ON'
  for glob in ${result[@]+"${result[@]}"}; do
    echoerr "${glob}"
    for file in ${glob}; do
      echoerr "+ ${file}"
      sums+="$(sha1sum "${file}")"
    done
  done

  echo "${sums}" | sha1sum | cut -c-7
}
