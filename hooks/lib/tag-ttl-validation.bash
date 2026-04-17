validate_tag_ttl_env_vars() {
  local base_var='BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_TAG_TTL_'
  declare -A prefix_indices ttl_indices

  while IFS='=' read -r name value ; do
    if [[ ! $name =~ ^${base_var} ]]; then
      continue
    fi

    if [[ $name =~ ^${base_var}([0-9]+)_PREFIX$ ]]; then
      prefix_indices["${BASH_REMATCH[1]}"]=1
      continue
    fi

    if [[ $name =~ ^${base_var}([0-9]+)_TTL$ ]]; then
      ttl_indices["${BASH_REMATCH[1]}"]=1
      continue
    fi

    log_fatal "tag-ttl must be configured as an array of {prefix, ttl} entries; unsupported env var '${name}' detected" 1
  done < <(env | sort)

  for idx in "${!ttl_indices[@]}"; do
    if [[ -z "${prefix_indices[$idx]:-}" ]]; then
      log_fatal "tag-ttl entry ${idx} has TTL but no PREFIX; both ${base_var}${idx}_PREFIX and ${base_var}${idx}_TTL must be configured" 1
    fi
  done

  for idx in "${!prefix_indices[@]}"; do
    if [[ -z "${ttl_indices[$idx]:-}" ]]; then
      log_fatal "tag-ttl entry ${idx} has PREFIX but no TTL; both ${base_var}${idx}_PREFIX and ${base_var}${idx}_TTL must be configured" 1
    fi
  done

  while IFS='=' read -r name value ; do
    if [[ ! $name =~ ^${base_var} ]]; then
      continue
    fi

    if [[ $name =~ ^${base_var}([0-9]+)_PREFIX$ ]]; then
      if [[ -z "${value}" ]]; then
        log_fatal "tag-ttl prefix for env var '${name}' must be non-empty" 1
      fi
      continue
    fi

    if [[ $name =~ ^${base_var}([0-9]+)_TTL$ ]]; then
      local idx="${BASH_REMATCH[1]}"
      local prefix_var="${base_var}${idx}_PREFIX"
      local ttl="${!name:-}"

      if ! [[ "$ttl" =~ $POSITIVE_INTEGER_REGEX ]]; then
        log_fatal "tag-ttl explicit rule '${prefix_var}' must have matching positive integer TTL in '${name}', got: '${ttl}'" 1
      fi
      continue
    fi
  done < <(env | sort)
}