#!/usr/bin/env bats

load "$BATS_PATH/load.bash"

# export DOCKER_STUB_DEBUG=/dev/tty

pre_command_hook="$PWD/hooks/pre-command"

@test "Fails hard if bad registry-provider" {
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGISTRY_PROVIDER="utter-fantasy"

  run "${pre_command_hook}"

  assert_failure
  assert_line --partial "Failed to source registry-provider."
}

@test "Skips build if pull succeeds" {
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGISTRY_PROVIDER="stub"
  local repository_uri="pretend.host/path/segment/image"

  stub docker \
    "pull * : true"

  run "${pre_command_hook}"

  assert_success
  assert_line "--- Pulling image"

  unstub docker
}

@test "Exits 1 if docker build fails" {
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGISTRY_PROVIDER="stub"

  stub docker \
    "pull * : false" \
    "build * : exit 242"

  run "${pre_command_hook}"

  assert_failure
  assert_line "--- Pulling image"
  assert_line "--- Building image"
  refute_line --partial "--- Pushing tag"

  unstub docker
}

@test "Tags and pushes computed tag and latest if build succeeds" {
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGISTRY_PROVIDER="stub"
  local repository_uri="pretend.host/path/segment/image"

  stub docker \
    "pull * : false" \
    "build * : echo building docker image" \
    "tag ${repository_uri}:stubbed-computed-tag ${repository_uri}:latest : echo tagged latest" \
    "push ${repository_uri}:stubbed-computed-tag : echo pushed stubbed-computed-tag" \
    "push ${repository_uri}:latest : echo pushed latest"
  run "${pre_command_hook}"

  assert_success
  assert_line "--- Pulling image"
  assert_line "--- Building image"
  assert_line "--- Pushing tag stubbed-computed-tag"
  assert_line "--- Pushing tag latest"

  unstub docker
}

@test "Tags and pushes with inline Dockerfile" {
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGISTRY_PROVIDER="stub"
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_DOCKERFILE_INLINE="FROM stub"
  local repository_uri="pretend.host/path/segment/image"

  one_time_mktemp=$(mktemp)

  stub mktemp \
    "echo $one_time_mktemp"

  stub docker \
    "pull * : false" \
    "build --file=$one_time_mktemp * : echo building docker image" \
    "tag ${repository_uri}:stubbed-computed-tag ${repository_uri}:latest : echo tagged latest" \
    "push ${repository_uri}:stubbed-computed-tag : echo pushed stubbed-computed-tag" \
    "push ${repository_uri}:latest : echo pushed latest"
  run "${pre_command_hook}"

  assert_success
  assert_line "--- Pulling image"
  assert_line "--- Building image"
  assert_line "--- Pushing tag stubbed-computed-tag"
  assert_line "--- Pushing tag latest"

  assert_equal "FROM stub" "$(cat $one_time_mktemp)"

  unstub mktemp
  unstub docker
}
