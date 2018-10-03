#!/bin/bash

set -o errexit
set -o xtrace

ROOT_DIR=$(pwd -P)

pushd ${ROOT_DIR} >/dev/null
    go test \
        -coverpkg="github.com/percona/pid-watchdog/..." \
        -c -tags testrunmain -o ./pid-watchdog.test \
        .
popd >/dev/null

cd ${ROOT_DIR}/tests/sandbox
exec ${ROOT_DIR}/pid-watchdog.test \
    -test.run "^TestRunMain$" \
    -test.coverprofile=coverage.txt
