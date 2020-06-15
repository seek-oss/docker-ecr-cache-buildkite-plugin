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

