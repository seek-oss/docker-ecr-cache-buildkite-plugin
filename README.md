# Docker ECR Cache

A [Buildkite plugin](https://buildkite.com/docs/agent/v3/plugins) to build and cache entire docker images in ECR.

This allows you to define a Dockerfile for your build-time dependencies without worrying about the time it
takes to build the image. It allows you to re-use entire docker images without worrying about layer caching, and/or pruning
layers as changes are made to your containers.

An ECR repository to store the built docker image will be created for you, if one doesn't already exist.

# Example

## Basic Usage

Dockerfile
```
FROM bash
RUN echo "my expensive build step"
```

```yml
steps:
  - command: 'echo wow'
    plugins:
      - seek-oss/docker-ecr-cache#v1.0.0
      - docker#v2.0.0
```

## Caching NPM Packages

This plugin can be used to effectively cache `node_modules` between builds without worrying abbout
docker layer cache invalidation. You do this by hinting when the image should be re-built.

Dockerfile
```
FROM node:8
WORKDIR /workdir
COPY package.json package-lock.json /workdir
# this step downloads the internet
RUN npm install
```

```yml
steps:
  - command: 'npm test'
    plugins:
      - seek-oss/docker-ecr-cache#v1.0.0:
          cache-on:
            - package-lock.json
      - docker#v2.0.0
```

## Using Another Dockerfile

It's possible to specify the Dockerfile to use by:

```yml
steps:
  - command: 'echo wow'
    plugins:
      - seek-oss/docker-ecr-cache#v1.0.0:
          dockerfile: my-dockerfile
      - docker#v2.0.0
```

# Tests

To run the tests of this plugin, run
```sh
docker-compose run --rm tests
```

# License

MIT (see [LICENSE](LICENSE))
