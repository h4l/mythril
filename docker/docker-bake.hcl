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

group "default" {
  targets = ["myth", "myth-smoke-test"]
}

target "locked-versions" {
  target = "locked-versions"
  output = ["type=local,dest=locked-versions"]
}

target "_base" {
  contexts = {
    mythril-src = "https://github.com/ConsenSys/mythril.git#v${MYTHRIL_VERSION}"
    blake2b-src = "https://github.com/ethereum/blake2b-py.git#v${BLAKE2B_VERSION}"
  }
  platforms = [
    "linux/amd64",
    "linux/arm64"
  ]
}

target "myth" {
  inherits = ["_base"]
  target = "myth"
  args = {
    INSTALLED_SOLC_VERSIONS = INSTALLED_SOLC_VERSIONS
  }
  tags = tags("myth")
}

target "myth-smoke-test" {
  inherits = ["myth"]
  target = "myth-smoke-test"
  output = ["type=local,dest=build/smoke-test"]
}
