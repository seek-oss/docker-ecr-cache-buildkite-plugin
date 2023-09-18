login() {
  # Currently assume the use of docker-credential-gcr to manage AuthN transparently.
  echo "Plugin currently assumes that docker-credential-gcr is on PATH and configured. See https://github.com/GoogleCloudPlatform/docker-credential-gcr#configuration-and-usage if later docker pull/push fail."
}

configure_registry_for_image_if_necessary() {
  # GCR does not have a concept of a repository for images within a registry like ECR does.
  echo ""
}

get_registry_url() {
  if [[ -z "${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_GCP_PROJECT:-}" ]]; then
    log_fatal "gcp-project in plugin settings must have a value." 34
  fi
  if [[ -z "${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGISTRY_HOSTNAME:-}" ]]; then
    echoerr "registry-hostname had no value, defaulting to gcr.io"
    BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGISTRY_HOSTNAME="gcr.io"
  fi
  echo "${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGISTRY_HOSTNAME}/${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_GCP_PROJECT}/${BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_ECR_NAME:-"$(get_default_image_name)"}"
}

image_exists() {
  # TODO - implement check for cache in GCR
  false
}
