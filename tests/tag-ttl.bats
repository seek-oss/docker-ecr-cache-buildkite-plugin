#!/usr/bin/env bats

# export AWS_STUB_DEBUG=/dev/tty
# export DOCKER_STUB_DEBUG=/dev/tty

load "$BATS_PLUGIN_PATH/load.bash"
load "$PWD/hooks/lib/stdlib.bash"
load "$PWD/hooks/lib/ecr-registry-provider.bash"

# --- Unit tests for get_tag_ttl_rules ---

@test "tag-ttl: default branch- rule TTL is 1 when no tag-ttl config set" {
  result="$(get_tag_ttl_rules)"

  run jq -r '."branch-"' <<< "$result"
  assert_output "1"
}

@test "tag-ttl: default branch- rule is the only entry when no tag-ttl config set" {
  result="$(get_tag_ttl_rules)"

  run jq -r 'keys | length' <<< "$result"
  assert_output "1"
}

@test "tag-ttl: explicit branch- TTL overrides the default of 1" {
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_TAG_TTL_BRANCH_=5

  result="$(get_tag_ttl_rules)"

  run jq -r '."branch-"' <<< "$result"
  assert_output "5"
}

@test "tag-ttl: explicit branch- TTL does not produce duplicate branch- entries" {
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_TAG_TTL_BRANCH_=5

  result="$(get_tag_ttl_rules)"

  run jq -r '[keys[] | select(. == "branch-")] | length' <<< "$result"
  assert_output "1"
}

@test "tag-ttl: multiple patterns each produce their own entry" {
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_TAG_TTL_BRANCH_=1
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_TAG_TTL_STAGING_=7
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_TAG_TTL_RELEASE_=90

  result="$(get_tag_ttl_rules)"

  run jq -r '."branch-"' <<< "$result"
  assert_output "1"
  run jq -r '."staging-"' <<< "$result"
  assert_output "7"
  run jq -r '."release-"' <<< "$result"
  assert_output "90"
}

@test "tag-ttl: custom pattern without branch- still includes the default branch- rule" {
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_TAG_TTL_STAGING_=7

  result="$(get_tag_ttl_rules)"

  run jq -r '."branch-"' <<< "$result"
  assert_output "1"
  run jq -r '."staging-"' <<< "$result"
  assert_output "7"
}

@test "tag-ttl: underscore in env var name is converted to hyphen in pattern" {
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_TAG_TTL_FEATURE_FLAG_=3

  result="$(get_tag_ttl_rules)"

  run jq -r '."feature-flag-"' <<< "$result"
  assert_output "3"
}

@test "tag-ttl: longer prefixes sort before shorter ones to prevent shadowing" {
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_TAG_TTL_BRANCH_=1
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_TAG_TTL_BRANCH_FEATURE_=3

  result="$(get_tag_ttl_rules)"

  # branch-feature- is longer and must appear first in sort_by(-length) order
  run jq -r 'keys | sort_by(-length) | .[0]' <<< "$result"
  assert_output "branch-feature-"

  run jq -r 'keys | sort_by(-length) | .[1]' <<< "$result"
  assert_output "branch-"
}

@test "tag-ttl: rejects non-numeric TTL value" {
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_TAG_TTL_BRANCH_="notanumber"

  run get_tag_ttl_rules

  assert_failure
  assert_output --partial "must be a positive integer"
}

# --- build_lifecycle_policy tests ---

@test "build_lifecycle_policy: default branch- rule produces correct tagPrefixList and countNumber" {
  local rules='{"branch-": 1}'

  result="$(build_lifecycle_policy "$rules" 30)"

  # branch- rule
  run jq -r '.rules[0].selection.tagPrefixList[0]' <<< "$result"
  assert_output "branch-"

  run jq -r '.rules[0].selection.countNumber' <<< "$result"
  assert_output "1"

  run jq -r '.rules[0].selection.tagStatus' <<< "$result"
  assert_output "tagged"

  run jq -r '.rules[0].rulePriority' <<< "$result"
  assert_output "1"
}

@test "build_lifecycle_policy: catch-all rule uses max-age-days with tagStatus any" {
  local rules='{"branch-": 1}'

  result="$(build_lifecycle_policy "$rules" 30)"

  run jq -r '.rules[1].selection.tagStatus' <<< "$result"
  assert_output "any"

  run jq -r '.rules[1].selection.countNumber' <<< "$result"
  assert_output "30"

  run jq -r '.rules[1].rulePriority' <<< "$result"
  assert_output "2"
}

@test "build_lifecycle_policy: multiple patterns produce correct rule count and ordering" {
  local rules='{"branch-": 1, "staging-": 7}'

  result="$(build_lifecycle_policy "$rules" 30)"

  # staging- is longer, gets priority 1
  run jq -r '.rules[0].selection.tagPrefixList[0]' <<< "$result"
  assert_output "staging-"

  run jq -r '.rules[0].selection.countNumber' <<< "$result"
  assert_output "7"

  # branch- is shorter, gets priority 2
  run jq -r '.rules[1].selection.tagPrefixList[0]' <<< "$result"
  assert_output "branch-"

  run jq -r '.rules[1].selection.countNumber' <<< "$result"
  assert_output "1"

  # catch-all gets priority 3
  run jq -r '.rules[2].selection.tagStatus' <<< "$result"
  assert_output "any"

  run jq -r '.rules | length' <<< "$result"
  assert_output "3"
}

@test "build_lifecycle_policy: more specific longer prefix gets lower rulePriority value and is evaluated first" {
  local rules='{"branch-": 1, "branch-feature-": 3}'

  result="$(build_lifecycle_policy "$rules" 30)"

  run jq -r '.rules[0].selection.tagPrefixList[0]' <<< "$result"
  assert_output "branch-feature-"

  run jq -r '.rules[0].rulePriority' <<< "$result"
  assert_output "1"

  run jq -r '.rules[1].selection.tagPrefixList[0]' <<< "$result"
  assert_output "branch-"

  run jq -r '.rules[1].rulePriority' <<< "$result"
  assert_output "2"
}

@test "build_lifecycle_policy: output is valid JSON" {
  local rules='{"branch-": 1}'

  run build_lifecycle_policy "$rules" 30

  assert_success
  # jq will fail if output is not valid JSON
  run jq '.' <<< "$output"
  assert_success
}

@test "build_lifecycle_policy: fails fast when tag-ttl prefix count exceeds ECR rule limit" {
  local rules='{"p01-":1,"p02-":2,"p03-":3,"p04-":4,"p05-":5,"p06-":6,"p07-":7,"p08-":8,"p09-":9,"p10-":10}'

  run build_lifecycle_policy "$rules" 30

  assert_failure
  assert_output --partial "support at most 9 tag-ttl prefixes"
}
