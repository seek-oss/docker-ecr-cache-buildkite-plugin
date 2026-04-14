#!/usr/bin/env bats

# export AWS_STUB_DEBUG=/dev/tty
# export DOCKER_STUB_DEBUG=/dev/tty

load "$BATS_PLUGIN_PATH/load.bash"
load "$PWD/hooks/lib/stdlib.bash"
load "$PWD/hooks/lib/ecr-registry-provider.bash"

pre_command_hook="$PWD/hooks/pre-command"

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
