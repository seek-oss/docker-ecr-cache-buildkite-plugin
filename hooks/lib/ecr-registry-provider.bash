ECR_LIFECYCLE_MAX_TOTAL_RULES=10
POSITIVE_INTEGER_REGEX='^[1-9][0-9]*$'
ECR_LIFECYCLE_DEFAULT_RULES_JSON=$(cat <<'EOF'
[
  {
    "kind": "prefix",
    "prefix": "branch-",
    "ttl": 1
  },
  {
    "kind": "catch-all",
    "ttlFrom": "max-age-days",
    "defaultTtl": 30
  }
]
EOF
)

login() {
  local account_id
  local region

  account_id=$(aws sts get-caller-identity --query Account --output text)
  region=$(get_ecr_region)

  aws ecr get-login-password \
    --region "${region}" \
    | docker login \
    --username AWS \
    --password-stdin "${account_id}.dkr.ecr.${region}.amazonaws.com"
}

get_ecr_region() {
  echo "${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGION:-${AWS_DEFAULT_REGION:-eu-west-1}}"
}

get_registry_url() {
  local repository_name
  repository_name="$(get_ecr_repository_name)"
  aws ecr describe-repositories \
    --repository-names "${repository_name}" \
    --output text \
    --query 'repositories[0].repositoryUri'
}

ecr_exists() {
  local repository_name="${1}"
  aws ecr describe-repositories \
    --repository-names "${repository_name}" \
    --output text \
    --query 'repositories[0].registryId'
}

image_exists() {
  local repository_name="$(get_ecr_repository_name)"
  local image_tag="${1}"
  local image_meta="$(aws ecr list-images \
    --repository-name "${repository_name}" \
    --query "imageIds[?imageTag=='${image_tag}'].imageTag" \
    --output text)"
  
  if [ "$image_meta" == "$image_tag" ]; then
    true
  else
    false
  fi
}

get_ecr_arn() {
  local repository_name="${1}"
  aws ecr describe-repositories \
    --repository-names "${repository_name}" \
    --output text \
    --query 'repositories[0].repositoryArn'
}

get_ecr_tags() {
local result=$(cat <<EOF
{
    "tags": []
}
EOF
)
  while IFS='=' read -r name _ ; do
    if [[ $name =~ ^(BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_ECR_TAGS_) ]] ; then
      # Handle plain key=value, e.g
      # ecr-tags:
      #   KEY_NAME: 'key-value'
      key_name=$(echo "${name}" | sed 's/^BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_ECR_TAGS_//')
      key_value=$(env | grep "$name" | sed "s/^$name=//")
      result=$(echo $result | jq ".tags[.tags| length] |= . + {\"Key\": \"${key_name}\", \"Value\": \"${key_value}\"}")
    fi
  done < <(env | sort)

  echo $result
}

get_ecr_repository_name() {
  echo "${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_ECR_NAME:-"$(get_default_image_name)"}"
}

validate_tag_ttl_env_vars() {
  local base_var='BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_TAG_TTL_'
  declare -A prefix_indices ttl_indices

  # Collect indices of all PREFIX and TTL env vars
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

  # Ensure every TTL has a matching PREFIX
  for idx in "${!ttl_indices[@]}"; do
    if [[ -z "${prefix_indices[$idx]:-}" ]]; then
      log_fatal "tag-ttl entry ${idx} has TTL but no PREFIX; both TAG_TTL_${idx}_PREFIX and TAG_TTL_${idx}_TTL must be configured" 1
    fi
  done

  # Ensure every PREFIX has a matching TTL
  for idx in "${!prefix_indices[@]}"; do
    if [[ -z "${ttl_indices[$idx]:-}" ]]; then
      log_fatal "tag-ttl entry ${idx} has PREFIX but no TTL; both TAG_TTL_${idx}_PREFIX and TAG_TTL_${idx}_TTL must be configured" 1
    fi
  done

  # Validate each PREFIX is non-empty and each TTL is a positive integer
  while IFS='=' read -r name value ; do
    if [[ ! $name =~ ^${base_var} ]]; then
      continue
    fi

    if [[ $name =~ ^${base_var}([0-9]+)_PREFIX$ ]]; then
      local idx="${BASH_REMATCH[1]}"

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

build_lifecycle_policy() {
  local tag_ttl_rules="${1}"
  local max_age_days="${2}"

  if ! [[ "$max_age_days" =~ $POSITIVE_INTEGER_REGEX ]]; then
    log_fatal "max-age-days must be a positive integer, got: '${max_age_days}'" 1
  fi

  local default_rule_count
  default_rule_count=$(echo "$ECR_LIFECYCLE_DEFAULT_RULES_JSON" | jq 'length')
  local max_configurable_prefix_rules=$((ECR_LIFECYCLE_MAX_TOTAL_RULES - default_rule_count))

  local configurable_prefix_rule_count
  configurable_prefix_rule_count=$(echo "$tag_ttl_rules" | jq --argjson defaults "$ECR_LIFECYCLE_DEFAULT_RULES_JSON" '
    ([$defaults[] | select(.kind == "prefix") | .prefix]) as $default_prefixes
    | [keys[] as $k | select(($default_prefixes | index($k)) | not)]
    | length
  ')
  if [ "$configurable_prefix_rule_count" -gt "$max_configurable_prefix_rules" ]; then
    log_fatal "ECR lifecycle policies support at most ${max_configurable_prefix_rules} additional tag-ttl prefixes (${ECR_LIFECYCLE_MAX_TOTAL_RULES} total rules, including ${default_rule_count} default rules). Configured additional prefixes: ${configurable_prefix_rule_count}." 1
  fi

  local default_prefix_rules
  default_prefix_rules=$(echo "$ECR_LIFECYCLE_DEFAULT_RULES_JSON" | jq '
    [ .[] | select(.kind == "prefix") | {(.prefix): .ttl} ] | add // {}
  ')
  local effective_prefix_rules
  effective_prefix_rules=$(jq -n \
    --argjson defaults "$default_prefix_rules" \
    --argjson overrides "$tag_ttl_rules" \
    '$defaults + $overrides')

  local rules_json
  rules_json=$(echo "$effective_prefix_rules" | jq '
    to_entries
    | sort_by(-(.key | length))
    | to_entries
    | map({
        "rulePriority": (.key + 1),
        "description": ("Expire images with tag prefix " + .value.key + " older than " + (.value.value | tostring) + " days"),
        "selection": {
          "tagStatus": "tagged",
          "tagPrefixList": [.value.key],
          "countType": "sinceImagePushed",
          "countUnit": "days",
          "countNumber": .value.value
        },
        "action": {"type": "expire"}
      })
  ')

  local catch_all_ttl
  catch_all_ttl=$(echo "$ECR_LIFECYCLE_DEFAULT_RULES_JSON" | jq -r \
    --argjson max_age "$max_age_days" '
      (.[] | select(.kind == "catch-all")) as $r
      | if $r.ttlFrom == "max-age-days" then $max_age else $r.defaultTtl end
    ')

  local catch_all_priority
  catch_all_priority=$(echo "$rules_json" | jq 'length + 1')

  rules_json=$(echo "$rules_json" | jq \
    --argjson max_age "${catch_all_ttl}" \
    --argjson priority "${catch_all_priority}" \
    '. + [{
      "rulePriority": $priority,
      "description": ("Expire other images older than " + ($max_age | tostring) + " days"),
      "selection": {
        "tagStatus": "any",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": $max_age
      },
      "action": {"type": "expire"}
    }]')

  jq -n --argjson rules "${rules_json}" '{"rules": $rules}'
}

configure_registry_for_image_if_necessary() {
  local repository_name
  repository_name="$(get_ecr_repository_name)"
  local max_age_days="${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_MAX_AGE_DAYS:-30}"
  local tag_ttl_rules="$(get_tag_ttl_rules)"
  local ecr_tags="$(get_ecr_tags)"
  local num_tags=$(echo $ecr_tags | jq '.tags | length')

  if ! ecr_exists "${repository_name}"; then
    aws ecr create-repository --repository-name "${repository_name}" --cli-input-json "${ecr_tags}"
  else
    if [ "$num_tags" -gt 0 ]; then
      local ecr_arn=$(get_ecr_arn "${repository_name}")
      aws ecr tag-resource --resource-arn ${ecr_arn} --cli-input-json "${ecr_tags}"
    fi
  fi

  local policy_text=$(build_lifecycle_policy "${tag_ttl_rules}" "${max_age_days}")

  # Always set the lifecycle policy to update repositories automatically
  # created before PR #9.
  #
  # When using a custom repository with a restricted Buildkite role this might
  # not succeed. Ignore the error and let the build continue.
  aws ecr put-lifecycle-policy \
  --repository-name "${repository_name}" \
  --lifecycle-policy-text "${policy_text}" || true
}
