login() {
  echo "stubbed login"
}

configure_registry_for_image_if_necessary() {
  echo "stubbed configure_registry_for_image_if_necessary"
}

get_registry_url() {
  echo "pretend.host/path/segment/image"
}

# BATS/bats-mock does not allow stubbing a function, currently.
# So, override it to avoid needing to repeat all the stub'd sha1sum etc inside the end-to-end tests.
compute_tag() {
  echo "stubbed-computed-tag"
}
