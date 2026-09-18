#!/usr/bin/env bash
# Shared helpers for the codegraph-shell fixture.

helper_one() {
  printf 'one\n'
}

function helper_two {
  helper_one
}

one_liner() { printf 'inline\n'; }
