get_tag_ttl_rules() {
  local result='{}'
  local base_var='BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_TAG_TTL_'

  validate_tag_ttl_env_vars

  while IFS='=' read -r name value ; do
    if [[ ! $name =~ ^${base_var} ]]; then
      continue
    fi

    if [[ $name =~ ^${base_var}([0-9]+)_PREFIX$ ]]; then
      local idx="${BASH_REMATCH[1]}"
      local ttl_var="${base_var}${idx}_TTL"
      local ttl="${!ttl_var:-}"

      result=$(echo "$result" | jq --arg p "${value}" --argjson ttl "${ttl}" '.[$p] = $ttl')
      continue
    fi

    if [[ $name =~ ^${base_var}[0-9]+_TTL$ ]]; then
      continue
    fi
  done < <(env | sort)

  echo "$result"
}