require_gcp_project() {
  if [[ -z "${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_GCP_PROJECT:-}" ]]; then
    log_fatal "gcp-project in plugin settings must have a value." 34
  fi
}

get_gcr_registry_hostname() {
  if [[ -z "${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGISTRY_HOSTNAME:-}" ]]; then
    echoerr "registry-hostname had no value, defaulting to gcr.io"
    BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGISTRY_HOSTNAME="gcr.io"
  fi
  echo "${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGISTRY_HOSTNAME}"
}

get_gcr_image_name() {
  echo "${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_ECR_NAME:-"$(get_default_image_name)"}"
}

login() {
  local registry_hostname
  registry_hostname="$(get_gcr_registry_hostname)"

  gcloud auth configure-docker "${registry_hostname}" --quiet
}

configure_registry_for_image_if_necessary() {
  # GCR does not have a concept of a repository for images within a registry like ECR does.
  echo ""
}

get_registry_url() {
  local registry_hostname="${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGISTRY_HOSTNAME:-}"
  local image_name

  if [[ -z "${registry_hostname}" ]]; then
    echoerr "registry-hostname had no value, defaulting to gcr.io"
    registry_hostname="gcr.io"
  fi

  require_gcp_project
  image_name="$(get_gcr_image_name)"
  echo "${registry_hostname}/${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_GCP_PROJECT}/${image_name}"
}

image_exists() {
  # TODO - implement check for cache in GCR
  false
}
