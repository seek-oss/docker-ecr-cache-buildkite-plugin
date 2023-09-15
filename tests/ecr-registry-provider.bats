#!/usr/bin/env bats

export AWS_STUB_DEBUG=/dev/tty
export DOCKER_STUB_DEBUG=/dev/tty

load "$BATS_PLUGIN_PATH/load.bash"
load "$PWD/hooks/lib/stdlib.bash"
load "$PWD/hooks/lib/ecr-registry-provider.bash"

pre_command_hook="$PWD/hooks/pre-command"

@test "ECR: Applies lifecycle policy to existing repositories" {
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
    "ecr put-lifecycle-policy --repository-name build-cache/example-org/example-pipeline --lifecycle-policy-text \* : echo put lifecycle policy" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].repositoryUri : echo https://1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com" 
    
  stub docker \
    "login --username AWS --password-stdin 1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com : echo logging in to docker" \
    "pull https://1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com:sha1sum : echo pulled image"

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
  assert_output --partial "tag existing resource"
  assert_output --partial "put lifecycle policy"

  unstub aws
  unstub docker
  unstub sha1sum
}

@test "ECR: Builds new images with tags" {
  export AWS_DEFAULT_REGION="ap-southeast-2"
  export BUILDKITE_ORGANIZATION_SLUG="example-org"
  export BUILDKITE_PIPELINE_SLUG="example-pipeline"
  local expected_repository_name="build-cache/example-org/example-pipeline"
  local repository_uri="1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com/${expected_repository_name}"

  stub aws \
    "sts get-caller-identity --query Account --output text : echo 1234567891012" \
    "ecr get-login-password --region ap-southeast-2 : echo secure-ecr-password" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].registryId : echo looked up repository" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].repositoryArn : echo arn:aws:ecr:ap-southeast-2:1234567891012:repository/${expected_repository_name}" \
    "ecr tag-resource --resource-arn arn:aws:ecr:ap-southeast-2:1234567891012:repository/build-cache/example-org/example-pipeline --cli-input-json \* : echo tag existing resource" \
    "ecr put-lifecycle-policy --repository-name build-cache/example-org/example-pipeline --lifecycle-policy-text \* : echo put lifecycle policy" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].repositoryUri : echo ${repository_uri}" \

  stub docker \
    "login --username AWS --password-stdin 1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com : echo logging in to docker" \
    "pull 1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com/build-cache/example-org/example-pipeline:deadbee : echo not found && false" \
    "build --file=Dockerfile --tag=1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com/build-cache/example-org/example-pipeline:deadbee . : echo building docker image" \
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
  assert_output --partial "tag existing resource"
  assert_output --partial "put lifecycle policy"
  assert_output --partial "tagged latest"
  assert_output --partial "pushed deadbeef"
  assert_output --partial "pushed latest"

  unstub aws
  unstub docker
  unstub sha1sum
}

@test "ECR: Uses correct region when region not specified and AWS_DEFAULT_REGION not set" {
  export BUILDKITE_ORGANIZATION_SLUG="example-org"
  export BUILDKITE_PIPELINE_SLUG="example-pipeline"
  local expected_repository_name="build-cache/example-org/example-pipeline"
  local repository_uri="1234567891012.dkr.ecr.eu-west-1.amazonaws.com/${expected_repository_name}"

  stub aws \
    "sts get-caller-identity --query Account --output text : echo 1234567891012" \
    "ecr get-login-password --region eu-west-1 : echo secure-ecr-password" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].registryId : echo looked up repository" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].repositoryArn : echo arn:aws:ecr:eu-west-1:1234567891012:repository/${expected_repository_name}" \
    "ecr tag-resource --resource-arn arn:aws:ecr:eu-west-1:1234567891012:repository/build-cache/example-org/example-pipeline --cli-input-json \* : echo tag existing resource" \
    "ecr put-lifecycle-policy --repository-name build-cache/example-org/example-pipeline --lifecycle-policy-text \* : echo put lifecycle policy" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].repositoryUri : echo ${repository_uri}" \

  stub docker \
    "login --username AWS --password-stdin 1234567891012.dkr.ecr.eu-west-1.amazonaws.com : echo logging in to docker" \
    "pull 1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com/build-cache/example-org/example-pipeline:deadbee : echo not found && false" \
    "build --file=Dockerfile --tag=1234567891012.dkr.ecr.eu-west-1.amazonaws.com/build-cache/example-org/example-pipeline:deadbee . : echo building docker image" \
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
  assert_output --partial "tag existing resource"
  assert_output --partial "put lifecycle policy"
  assert_output --partial "tagged latest"
  assert_output --partial "pushed deadbeef"
  assert_output --partial "pushed latest"

  unstub aws
  unstub docker
  unstub sha1sum
}

@test "ECR: Uses correct region when region is specified" {
  export AWS_DEFAULT_REGION="ap-southeast-2"
  export BUILDKITE_PLUGIN_DOCKER_ECR_CACHE_REGION="ap-southeast-1"
  export BUILDKITE_ORGANIZATION_SLUG="example-org"
  export BUILDKITE_PIPELINE_SLUG="example-pipeline"
  local expected_repository_name="build-cache/example-org/example-pipeline"
  local repository_uri="1234567891012.dkr.ecr.ap-southeast-1.amazonaws.com/${expected_repository_name}"

  stub aws \
    "sts get-caller-identity --query Account --output text : echo 1234567891012" \
    "ecr get-login-password --region ap-southeast-1 : echo secure-ecr-password" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].registryId : echo looked up repository" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].repositoryArn : echo arn:aws:ecr:ap-southeast-1:1234567891012:repository/${expected_repository_name}" \
    "ecr tag-resource --resource-arn arn:aws:ecr:ap-southeast-2:1234567891012:repository/build-cache/example-org/example-pipeline --cli-input-json \* : echo tag existing resource" \
    "ecr put-lifecycle-policy --repository-name build-cache/example-org/example-pipeline --lifecycle-policy-text \* : echo put lifecycle policy" \
    "ecr describe-repositories --repository-names ${expected_repository_name} --output text --query repositories[0].repositoryUri : echo ${repository_uri}" \

  stub docker \
    "login --username AWS --password-stdin 1234567891012.dkr.ecr.ap-southeast-1.amazonaws.com : echo logging in to docker" \
    "pull 1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com/build-cache/example-org/example-pipeline:deadbee : echo not found && false" \
    "build --file=Dockerfile --tag=1234567891012.dkr.ecr.ap-southeast-2.amazonaws.com/build-cache/example-org/example-pipeline:deadbee . : echo building docker image" \
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
  assert_output --partial "tag existing resource"
  assert_output --partial "put lifecycle policy"
  assert_output --partial "tagged latest"
  assert_output --partial "pushed deadbeef"
  assert_output --partial "pushed latest"

  unstub aws
  unstub docker
  unstub sha1sum
}