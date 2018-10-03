compile() {
    pushd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null
    if [ ! -f "${BATS_TMPDIR}/pid-watchdog.test" ]; then
        go build -o "${BATS_TMPDIR}/pid-watchdog.test" ..
        echo go test \
            -c \
            -tags testrunmain \
            -o "${BATS_TMPDIR}/pid-watchdog.test" \
            -coverpkg="github.com/percona/pid-watchdog/..." \
            ..
        ln -s "${BATS_TMPDIR}/pid-watchdog.test" "${BATS_TMPDIR}/service"
    fi
    popd >/dev/null
}

prepare_service() {
    local CONFIG=$1
    local CONTENT=$2
    export PID_WATCHER_CONFIG=${CONFIG}.yaml

    compile

    cd ${BATS_TMPDIR}
    echo "${CONTENT}" > ${PID_WATCHER_CONFIG}
}

start_pw() {
    local CONFIG=$1
    local CONTENT=$2
    export TESTS_MODE=1
    export PID_WATCHER_CONFIG=${CONFIG}.yaml

    compile

    cd ${BATS_TMPDIR}
    echo "${CONTENT}" > ${PID_WATCHER_CONFIG}

    ./pid-watchdog.test ${PID_WATCHER_CONFIG} 2>&1 \
        | tee ${CONFIG}.log &
}

stop_pw() {
    export CONFIG=$1
    local PID="$(cat /tmp/pw-${CONFIG}.pid)"

    kill "${PID}"
    while sleep 0.25; do
        kill -0 "${PID}" || break
    done

    run diff -u "${BATS_TEST_DIRNAME}/logs/${CONFIG}.log" "${BATS_TMPDIR}/${CONFIG}.log"
    echo "${output}" >&2
    [[ "${status}" -eq 0 ]]
}

teardown() {
    rm -rf \
        "${BATS_TMPDIR}/pid-watchdog.test" \
        "${BATS_TMPDIR}/service"
    for pid_file in $(ls ${BATS_TMPDIR}/*.pid /tmp/*.pid); do
        kill -9 "$(cat ${pid_file} || :)" || :
        rm -rf "${pid_file}" || :
    done
}
