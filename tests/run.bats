#!/usr/bin/env bats

# export AWS_STUB_DEBUG=/dev/tty
# export DOCKER_STUB_DEBUG=/dev/tty

load "$BATS_PATH/load.bash"

pre_command_hook="$PWD/hooks/pre-command"

@test "Applies lifecycle policy to existing repositories" {
  export BUILDKITE_ORGANIZATION_SLUG="example-org"
  export BUILDKITE_PIPELINE_SLUG="example-pipeline"
  local expected_repository_name="build-cache/example-org/example-pipeline"

  stub aws \
    "ecr get-login --no-include-email : echo docker login -u AWS -p 1234 https://1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].registryId : echo looked up repository" \
    "ecr put-lifecycle-policy * : echo put lifecycle policy" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].repositoryUri : echo https://1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com"

  stub docker \
    "login -u AWS -p 1234 https://1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com : echo logging in to docker" \
    "pull : echo pulled image"

  stub sha1sum \
    "Dockerfile : echo 'sha1sum(Dockerfile)'" \
    ": echo sha1sum" \
    ": echo sha1sum" \
    ": echo sha1sum"

  run "${pre_command_hook}"

  assert_success
  assert_output --partial "logging in to docker"
  assert_output --partial "pulled image"
  assert_output --partial "looked up repository"
  assert_output --partial "put lifecycle policy"

  unstub aws
  unstub docker
  unstub sha1sum
}

@test "Builds new images with tags" {
  export BUILDKITE_ORGANIZATION_SLUG="example-org"
  export BUILDKITE_PIPELINE_SLUG="example-pipeline"
  local expected_repository_name="build-cache/example-org/example-pipeline"
  local repository_uri="1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com/${expected_repository_name}"

  stub aws \
    "ecr get-login --no-include-email : echo docker login -u AWS -p 1234 https://1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].registryId : echo looked up repository" \
    "ecr put-lifecycle-policy * : echo put lifecycle policy" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].repositoryUri : echo ${repository_uri}"

  stub docker \
    "login -u AWS -p 1234 https://1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com : echo logging in to docker" \
    "pull : echo not found && false" \
    "build * : echo building docker image" \
    "tag ${repository_uri}:deadbee ${repository_uri}:latest : echo tagged latest" \
    "push ${repository_uri}:deadbee : echo pushed deadbeef" \
    "push ${repository_uri}:latest : echo pushed latest"

  stub sha1sum \
    "Dockerfile : echo 'sha1sum(Dockerfile)'" \
    ": echo sha1sum" \
    ": echo sha1sum" \
    ": echo deadbeef"

  run "${pre_command_hook}"

  assert_success
  assert_output --partial "logging in to docker"
  assert_output --partial "looked up repository"
  assert_output --partial "building docker image"
  assert_output --partial "put lifecycle policy"
  assert_output --partial "tagged latest"
  assert_output --partial "pushed deadbeef"
  assert_output --partial "pushed latest"

  unstub aws
  unstub docker
  unstub sha1sum
}
