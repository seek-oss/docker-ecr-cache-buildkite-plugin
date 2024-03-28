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

read_secrets() {
  read_list_property 'SECRETS'
  for arg in ${result[@]+"${result[@]}"}; do
    secrets_args+=("--secret")
    if [[ "${arg}" =~ ^id= ]]; then
      # Assume this is a full argument like id=123,src=path/to/file
      secrets_args+=("${arg}")
    else
      # Assume this is environment variable shorthand like SECRET_ENV
      secrets_args+=("id=${arg},env=${arg}")
    fi
  done
}

read_secrets_with_output() {
  read_secrets

  echo "${secrets_args[@]}"
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
  sums="$(cd ${docker_file_dir}; sha1sum $(basename ${docker_file}))"
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
      if [[ "${file}" == *.json#* ]]; then
        # Extract the file path and keys from the pattern
        file_path="${file%%#*}"
        keys=${file#*#}

        # Read the JSON file and calculate sha1sum only for the specified keys
        value=$(jq -r "${keys}" "${file_path}")
        sums+="$(echo -n "${value}" | sha1sum)"
      else
        # Calculate sha1sum for the whole file
        sums+="$(sha1sum "${file}")"
      fi
    done
  done

  echo "${sums}" | sha1sum | cut -c-7
}
