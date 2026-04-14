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

# --- Integration tests ---

@test "tag-ttl: lifecycle policy is applied with default branch- rule" {
  export AWS_DEFAULT_REGION="ap-southeast-2"
  export BUILDKITE_ORGANIZATION_SLUG="example-org"
  export BUILDKITE_PIPELINE_SLUG="example-pipeline"
  local expected_repository_name="build-cache/example-org/example-pipeline"

  stub aws \
    "sts get-caller-identity --query Account --output text : echo 1234567891012" \
    "ecr get-login-password --region ap-southeast-2 : echo secure-ecr-password" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].registryId : echo looked up repository" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].repositoryArn : echo arn:aws:ecr:ap-southeast-2:1234567891012:repository/${expected_repository_name}" \
    "ecr tag-resource --resource-arn arn:aws:ecr:ap-southeast-2:1234567891012:repository/build-cache/example-org/example-pipeline --cli-input-json \* : echo tag existing resource" \
    "ecr put-lifecycle-policy --repository-name ${expected_repository_name} --lifecycle-policy-text \* : echo put lifecycle policy" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].repositoryUri : echo 1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com/${expected_repository_name}"

  stub docker \
    "login --username AWS --password-stdin 1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com : echo logging in to docker" \
    "pull 1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com/${expected_repository_name}:sha1sum : echo pulled image"

  stub sha1sum \
    "Dockerfile : echo 'sha1sum(Dockerfile)'" \
    ": echo sha1sum" \
    ": echo sha1sum" \
    ": echo sha1sum"

  run "${pre_command_hook}"

  assert_success
  assert_output --partial "put lifecycle policy"

  unstub aws
  unstub docker
  unstub sha1sum
}

@test "tag-ttl: lifecycle policy is applied with custom tag-ttl patterns" {
  export AWS_DEFAULT_REGION="ap-southeast-2"
  export BUILDKITE_ORGANIZATION_SLUG="example-org"
  export BUILDKITE_PIPELINE_SLUG="example-pipeline"
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_TAG_TTL_BRANCH_=1
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_TAG_TTL_STAGING_=7
  local expected_repository_name="build-cache/example-org/example-pipeline"

  stub aws \
    "sts get-caller-identity --query Account --output text : echo 1234567891012" \
    "ecr get-login-password --region ap-southeast-2 : echo secure-ecr-password" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].registryId : echo looked up repository" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].repositoryArn : echo arn:aws:ecr:ap-southeast-2:1234567891012:repository/${expected_repository_name}" \
    "ecr tag-resource --resource-arn arn:aws:ecr:ap-southeast-2:1234567891012:repository/build-cache/example-org/example-pipeline --cli-input-json \* : echo tag existing resource" \
    "ecr put-lifecycle-policy --repository-name ${expected_repository_name} --lifecycle-policy-text \* : echo put lifecycle policy" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].repositoryUri : echo 1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com/${expected_repository_name}"

  stub docker \
    "login --username AWS --password-stdin 1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com : echo logging in to docker" \
    "pull 1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com/${expected_repository_name}:sha1sum : echo pulled image"

  stub sha1sum \
    "Dockerfile : echo 'sha1sum(Dockerfile)'" \
    ": echo sha1sum" \
    ": echo sha1sum" \
    ": echo sha1sum"

  run "${pre_command_hook}"

  assert_success
  assert_output --partial "put lifecycle policy"

  unstub aws
  unstub docker
  unstub sha1sum
}
