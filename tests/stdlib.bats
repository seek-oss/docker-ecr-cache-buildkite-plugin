#!/usr/bin/env bats

# export UNAME_STUB_DEBUG=/dev/tty
# export SHA1SUM_STUB_DEBUG=/dev/tty

load "$BATS_PATH/load.bash"
load "$PWD/hooks/lib/stdlib.bash"

pre_command_hook="$PWD/hooks/pre-command"

@test "Can read build-args from array" {
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_BUILD_ARGS_1="foo=1"
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_BUILD_ARGS_2="bar=2"

  run read_build_args

  assert_success
  # cannot assert, here, because function does not emit output, and populates build_args var in outer scope.
  # coverage happens via later tests of compute_tag.
}

@test "Can read secrets from array" {
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_SECRETS_1="FOO"
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_SECRETS_2="id=1,env=BAR"
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_SECRETS_3="id=2,src=path/to/secret.txt"

  run read_secrets_with_output

  assert_success
  assert_output "--secret id=FOO,env=FOO --secret id=1,env=BAR --secret id=2,src=path/to/secret.txt"
}

@test "Can get default image name" {
  export BUILDKITE_ORGANIZATION_SLUG="example-org"
  export BUILDKITE_PIPELINE_SLUG="example-pipeline"

  run get_default_image_name

  assert_success
  assert_output "build-cache/example-org/example-pipeline"
}

@test "Can compute image tag, no target, no build-args, no cache-on" {
  # TODO: this var leaks in via pre-command. Fix at some point by adding a function arg.
  target=""

  stub uname \
    "-m : echo my-architecture" \
    "-m : echo my-architecture"
  stub sha1sum \
    "pretend-dockerfile : echo sha1sum(pretend-dockerfile)" \
    ": echo sha1sum(target: <target>)" \
    ": echo sha1sum(my-architecture)" \
    ": echo sha1sum(hashes so far)"

  run compute_tag "pretend-dockerfile"

  assert_success
  assert_line "--- Computing tag"
  assert_line "DOCKERFILE"
  assert_line "+ pretend-dockerfile:<target>"
  assert_line "ARCHITECTURE"
  assert_line "+ my-architecture"
  assert_line "BUILD_ARGS"
  assert_line "CACHE_ON"

  unstub uname
  unstub sha1sum
}

@test "Can compute image tag, with target" {
  # this var leaks in via pre-command
  target="my-multi-stage-container"

  stub uname \
    "-m : echo my-architecture" \
    "-m : echo my-architecture"
  stub sha1sum \
    "pretend-dockerfile : echo sha1sum(pretend-dockerfile)" \
    ": echo sha1sum(target: my-multi-stage-container)" \
    ": echo sha1sum(uname: my-architecture)" \
    ": echo sha1sum(hashes so far)"

  run compute_tag "pretend-dockerfile"

  assert_success
  assert_line "--- Computing tag"
  assert_line "DOCKERFILE"
  assert_line "+ pretend-dockerfile:my-multi-stage-container"
  assert_line "ARCHITECTURE"
  assert_line "+ my-architecture"
  assert_line "BUILD_ARGS"
  assert_line "CACHE_ON"

  unstub uname
  unstub sha1sum
}

@test "Can compute image tag, with target, build-args" {
  # this var leaks in via pre-command
  target="my-multi-stage-container"
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_BUILD_ARGS_1="foo=1"

  stub uname \
    "-m : echo my-architecture" \
    "-m : echo my-architecture"
  stub sha1sum \
    "pretend-dockerfile : echo sha1sum(pretend-dockerfile)" \
    ": echo sha1sum(target: my-multi-stage-container)" \
    ": echo sha1sum(uname: my-architecture)" \
    ": echo sha1sum(build-arg: foo=1)" \
    ": echo sha1sum(hashes so far)"

  run compute_tag "pretend-dockerfile"

  assert_success
  assert_line "--- Computing tag"
  assert_line "DOCKERFILE"
  assert_line "+ pretend-dockerfile:my-multi-stage-container"
  assert_line "ARCHITECTURE"
  assert_line "+ my-architecture"
  assert_line "BUILD_ARGS"
  assert_line "+ foo=1"
  assert_line "CACHE_ON"

  unstub uname
  unstub sha1sum
}

@test "Can compute image tag, with target, build-args, cache-on" {
  # this var leaks in via pre-command
  target="my-multi-stage-container"
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_BUILD_ARGS_1="foo=1"
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_CACHE_ON_1="amazing-content.txt"

  stub uname \
    "-m : echo my-architecture" \
    "-m : echo my-architecture"
  stub sha1sum \
    "pretend-dockerfile : echo sha1sum(pretend-dockerfile)" \
    ": echo sha1sum(target: my-multi-stage-container)" \
    ": echo sha1sum(uname: my-architecture)" \
    ": echo sha1sum(build-arg: foo=1)" \
    "amazing-content.txt : echo sha1sum(cache-on: amazing-content.txt)" \
    ": echo sha1sum(hashes so far)"

  run compute_tag "pretend-dockerfile"

  assert_success
  assert_line "--- Computing tag"
  assert_line "DOCKERFILE"
  assert_line "+ pretend-dockerfile:my-multi-stage-container"
  assert_line "ARCHITECTURE"
  assert_line "+ my-architecture"
  assert_line "BUILD_ARGS"
  assert_line "+ foo=1"
  assert_line "CACHE_ON"

  unstub uname
  unstub sha1sum
}
