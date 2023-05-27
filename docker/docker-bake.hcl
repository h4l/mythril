variable "TAG_PREFIX" {
  default = ""
}

variable "MYTHRIL_VERSION" {
  default = "0.23.22"
}

variable "BLAKE2B_VERSION" {
  default = "0.2.0"
}

variable "INSTALLED_SOLC_VERSIONS" {
  default = "0.8.20"
}

variable "BASE_IMAGE_PYTHON" {
  default = "python:3.9-slim"
}

variable "BASE_IMAGE_DEBIAN" {
  default = "debian:bullseye"
}

variable "CI" {
  default = false
}

variable "GITHUB_RUN_ID" {
  default = ""
}

variable "GITHUB_RUN_NUMBER" {
  default = ""
}

variable "GITHUB_RUN_ATTEMPT" {
  default = ""
}

variable "GITHUB_REPOSITORY" {
  default = ""
}

variable "GITHUB_SHA" {
  default = ""
}

function "build_id" {
  params = []
  result = regex(
    "^build\\.\\d+\\.\\d+\\.\\d+$",
    "build.${GITHUB_RUN_ID}.${GITHUB_RUN_NUMBER}.${GITHUB_RUN_ATTEMPT}"
  )
}

function "build_time" {
  params = []
  result = "date.${formatdate("YY.MM.DD", timestamp())}"
}

function "tag_versions" {
  params = []
  result = CI ? [
    // Assume we're always publishing a build of the most recent myth version,
    // so :latest is reasonable.
    "latest",
    "${MYTHRIL_VERSION}",
    "${MYTHRIL_VERSION}-${build_id()}",
    "${MYTHRIL_VERSION}-${build_time()}"
  ] : ["${MYTHRIL_VERSION}-dev"]
}

function "tags" {
  params = [name]
  result = formatlist(
    "${join("/", compact([TAG_PREFIX, name]))}:%s",
    tag_versions()
  )
}

function "labels" {
  params = []
  result = merge(
    {
      "org.opencontainers.image.created" = timestamp(),
      "org.opencontainers.image.title" = "mythril",
      "org.opencontainers.image.description" = "Security analysis tool for EVM bytecode",
      "org.opencontainers.image.version" = "${MYTHRIL_VERSION}"
    },
    CI ? {
      "org.opencontainers.image.source" = "https://github.com/${GITHUB_REPOSITORY}",
      "org.opencontainers.image.revision" = GITHUB_SHA
    } : {}
  )
}

function "image_index_annotations" {
  params = []
  // https://github.com/moby/buildkit/blob/master/docs/annotations.md
  result = formatlist("annotation-index.%s=%s", keys(labels()), values(labels()))
}

target "_base" {
  args = {
    BASE_IMAGE_DEBIAN = BASE_IMAGE_DEBIAN
    BASE_IMAGE_PYTHON = BASE_IMAGE_PYTHON
  }
}

group "default" {
  targets = ["myth", "myth-smoke-test"]
}

target "locked-versions" {
  inherits = ["_base"]
  target = "locked-versions"
  output = ["type=local,dest=locked-versions"]
}

target "_myth_base" {
  inherits = ["_base"]
  contexts = {
    mythril-src = "https://github.com/ConsenSys/mythril.git#v${MYTHRIL_VERSION}"
    blake2b-src = "https://github.com/ethereum/blake2b-py.git#v${BLAKE2B_VERSION}"
  }
  platforms = [
    "linux/amd64",
    "linux/arm64"
  ]
  labels = labels()
}

target "myth" {
  inherits = ["_myth_base"]
  target = "myth"
  args = {
    INSTALLED_SOLC_VERSIONS = INSTALLED_SOLC_VERSIONS
  }
  tags = tags("myth")
  output = [join(",", flatten([["type=image"], image_index_annotations()]))]
}

target "myth-smoke-test" {
  inherits = ["myth"]
  target = "myth-smoke-test"
  output = ["type=local,dest=build/smoke-test"]
}
