#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"
load "$PWD/hooks/lib/stdlib.bash"
load "$PWD/hooks/lib/gcr-registry-provider.bash"

@test "GCR: Can login" {
  run login

  assert_success
  assert_output --partial "Plugin currently assumes"
}

@test "GCR: Can configure registry for image if necessary" {
  # Currently a no-op for GCR.
  run configure_registry_for_image_if_necessary

  assert_success
  assert_output ""
}

@test "GCR: get_registry_url fail when no gcp-project" {
  run get_registry_url

  assert_failure
  assert_output --partial "gcp-project"
}

@test "GCR: get_registry_url uses defaults when no registry-hostname or ecr-name" {
  export BUILDKITE_ORGANIZATION_SLUG="example-org"
  export BUILDKITE_PIPELINE_SLUG="example-pipeline"
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_GCP_PROJECT="rusty-beaver-23452"

  run get_registry_url

  assert_success
  assert_line "gcr.io/rusty-beaver-23452/build-cache/example-org/example-pipeline"
}

@test "GCR: get_registry_url uses overrides when supplied" {
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_GCP_PROJECT="rusty-beaver-23452"
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGISTRY_HOSTNAME="eu.gcr.io"
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_ECR_NAME="my-dam"

  run get_registry_url

  assert_success
  assert_line "eu.gcr.io/rusty-beaver-23452/my-dam"
}
