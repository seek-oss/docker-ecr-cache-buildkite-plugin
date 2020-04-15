# Docker ECR Cache Buildkite Plugin

[![GitHub Release](https://img.shields.io/github/release/seek-oss/docker-ecr-cache-buildkite-plugin.svg)](https://github.com/seek-oss/docker-ecr-cache-buildkite-plugin/releases)

A [Buildkite plugin](https://buildkite.com/docs/agent/v3/plugins) to cache
Docker images in Amazon ECR.

This allows you to define a Dockerfile for your build-time dependencies without
worrying about the time it takes to build the image. It allows you to re-use
entire Docker images without worrying about layer caching, and/or pruning layers
as changes are made to your containers.

An ECR repository to store the built Docker image will be created for you, if
one doesn't already exist.

## Example

### Basic usage

```dockerfile
FROM bash

RUN echo "my expensive build step"
```

```yaml
steps:
  - command: 'echo wow'
    plugins:
      - seek-oss/docker-ecr-cache#v1.6.0
      - docker#v3.3.0
```

### Caching npm packages

This plugin can be used to effectively cache `node_modules` between builds
without worrying about Docker layer cache invalidation. You do this by hinting
when the image should be re-built.

```dockerfile
FROM node:10-alpine

WORKDIR /workdir

COPY package.json package-lock.json /workdir

# this step downloads the internet
RUN npm install
```

```yaml
steps:
  - command: 'npm test'
    plugins:
      - seek-oss/docker-ecr-cache#v1.6.0:
          cache-on:
            - package-lock.json
      - docker#v3.3.0:
          volumes:
            - /workdir/node_modules
```

The `cache-on` property also supports Bash globbing with `globstar`:

```yaml
steps:
  - command: 'npm test'
    plugins:
      - seek-oss/docker-ecr-cache#v1.6.0:
          cache-on:
            - '**/package.json' # monorepo with multiple manifest files
            - yarn.lock
      - docker#v3.0.1:
          volumes:
            - /workdir/node_modules
```

### Using another Dockerfile

It's possible to specify the Dockerfile to use by:

```yaml
steps:
  - command: 'echo wow'
    plugins:
      - seek-oss/docker-ecr-cache#v1.6.0:
          dockerfile: my-dockerfile
      - docker#v3.3.0
```

The subdirectory containing the Dockerfile is the path used for the build's context.

### Specifying a target step

A [multi-stage Docker build] can be used to reduce an application container to
just its runtime dependencies. However, this stripped down container may not
have the environment necessary for running CI commands such as tests or linting.
Instead, the `target` property can be used to specify an intermediate build
stage to run commands against:

[multi-stage docker build]: https://docs.docker.com/develop/develop-images/multistage-build/

```yaml
steps:
  - command: 'cargo test'
    plugins:
      - seek-oss/docker-ecr-cache#v1.6.0:
          target: build-deps
      - docker#v3.3.0
```

### Specifying build args

[Build-time variables] are supported, either with an explicit value, or without
one to propagate an environment variable from the pipeline step:

[build-time variables]: https://docs.docker.com/engine/reference/commandline/build/#set-build-time-variables---build-arg

```dockerfile
FROM bash

ARG ARG_1
ARG ARG_2

RUN echo "${ARG_1}"
RUN echo "${ARG_2}"
```

```yaml
steps:
  - command: 'echo amaze'
    env:
      ARG_1: wow
    plugins:
      - seek-oss/docker-ecr-cache#v1.6.0:
          build-args:
            - ARG_1
            - ARG_2=such
      - docker#v3.3.0
```

Additional `docker build` arguments be passed via the `additional-build-args` setting:

```yaml
steps:
  - command: 'echo amaze'
    env:
      ARG_1: wow
    plugins:
      - seek-oss/docker-ecr-cache#v1.6.0:
          additional-build-args: '--ssh= default=\$SSH_AUTH_SOCK'
      - docker#v3.3.0
```

### Specifying an ECR repository name

The plugin pushes and pulls Docker images to and from an ECR repository named
`build-cache/${BUILDKITE_ORGANIZATION_SLUG}/${BUILDKITE_PIPELINE_SLUG}`. You can
optionally use a custom repository name:

```yaml
steps:
  - command: 'echo wow'
    plugins:
      - seek-oss/docker-ecr-cache#v1.6.0:
          ecr-name: my-unique-repository-name
          ecr-tags: 
            Key: Value
            Key2: Value2
      - docker#v3.3.0
```

### Changing the max cache time

By default images are kept in ECR for up to 30 days. This can be changed by specifying a `max-age-days` parameter:

```yaml
steps:
  - command: 'echo wow'
    plugins:
      - seek-oss/docker-ecr-cache#v1.6.0:
          max-age-days: 7
      - docker#v3.3.0
```

## Design

The plugin derives a checksum from:

- The argument names and values specified in the `build-args` property
- The files specified in the `cache-on` and `dockerfile` properties

This checksum is used as the Docker image tag to find and pull an existing
cached image from ECR, or to build and push a new image for subsequent builds to
use.

The plugin handles the creation of a dedicated ECR repository for the pipeline
it runs in. To save on [ECR storage costs] and give images a chance to update/patch, a [lifecycle policy] is
automatically applied to expire images after 30 days (configurable via `max-age-days`).

[ecr storage costs]: https://aws.amazon.com/ecr/pricing/
[lifecycle policy]: https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html

## Tests

To run the tests of this plugin, run

```
docker-compose run --rm tests
```

## License

MIT (see [LICENSE](LICENSE))
