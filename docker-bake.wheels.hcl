group "wheels" {
  targets = ["z3-solver-wheel-build", "blake2b-wheel-build", "mythril-wheel-build"]
}

target "z3-solver-wheel-build" {
  inherits = ["_base"]
  target = "z3-solver-wheel-build"
    tags = ["python-cross1"]
}

target "blake2b-wheel-build" {
  inherits = ["_base"]
  target = "blake2b-wheel-build"
  tags = ["python-cross-blake2b"]
}

target "mythril-wheel-build" {
  inherits = ["_base"]
  target = "mythril-wheel-build"
  tags = ["python-cross-mythril"]
}
