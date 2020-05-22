login() {
  # Currently assume the use of docker-credential-gcr to manage AuthN transparently.
  echo "TODO"
}

configure_registry_for_image_if_necessary() {
  # GCR does not have a concept of a repository for images within a registry like ECR does.
  echo ""
}

get_registry_url() {
  if [[ -z "${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_GCP_PROJECT:-}" ]]; then
    log_fatal "gcp-project in plugin settings must have a value." 34
  fi
  if [[ -z "${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGISTRY_BASE_NAME:-}" ]]; then
    echo "registry-base-name had no value, defaulting to gcr.io"
    BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGISTRY_BASE_NAME="gcr.io"
  fi
  step_part="${BUILDKITE_STEP_KEY:-}"
  if [[ -z "${step_part:-}" ]]; then
    echo "Your step has no \`key\`, using its label instead. If you change the name of your step, you will get a cache miss."
    step_part="${BUILDKITE_LABEL}"
  fi
  echo "${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGISTRY_BASE_NAME}/${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_GCP_PROJECT}/build-cache/${BUILDKITE_ORGANIZATION_SLUG}/${BUILDKITE_PIPELINE_SLUG}/${step_part}"
}
