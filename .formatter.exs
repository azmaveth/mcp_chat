# Used by "mix format"
#
# NOTE: The Elixir formatter does not provide an option to disable underscore
# insertion in numeric literals. It will always format numbers like 1000000
# as 1_000_000 for readability. This can cause issues in tests that assert
# exact numeric values. We handle this by:
# 1. Disabling the Credo.Check.Readability.LargeNumbers check
# 2. Using arithmetic expressions in tests to avoid literal numeric values
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  line_length: 120,
  import_deps: []
]
