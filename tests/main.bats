#!/usr/bin/env bats

load helper

@test "smoke" {
    CONFIG=smoke
    start_pw "${CONFIG}" "
        main:
            interval: 2s
            pid_file: /tmp/pw-${CONFIG}.pid
    "
    sleep 3

    run kill -0 "$(cat /tmp/pw-${CONFIG}.pid)"
    echo "${output}" >&2
    [[ "${status}" -eq 0 ]]

    stop_pw "${CONFIG}"
}

@test "start/stop" {
    CONFIG=start-stop
    start_pw "${CONFIG}" "
        main:
            interval: 2s
            pid_file: /tmp/pw-${CONFIG}.pid
        sleep-120:
            pid_file: /tmp/sleep-120.pid
            start_command: ${BATS_TEST_DIRNAME}/sandbox/sleep-120 start
            stop_command: ${BATS_TEST_DIRNAME}/sandbox/sleep-120 stop
    "
    sleep 3

    APP1_PID="$(cat /tmp/sleep-120.pid)"
    run kill -0 "${APP1_PID}"
    echo "${output}" >&2
    [[ "${status}" -eq 0 ]]

    stop_pw "${CONFIG}"

    run kill -0 "${APP1_PID}"
    [[ "${status}" -ne 0 ]]
}

@test "continuing" {
    pushd "${BATS_TMPDIR}"
        ${BATS_TEST_DIRNAME}/sandbox/sleep-120 start
    popd
    APP1_PID="$(cat /tmp/sleep-120.pid)"
    run kill -0 "${APP1_PID}"
    echo "${output}" >&2
    [[ "${status}" -eq 0 ]]

    CONFIG=continuing
    start_pw "${CONFIG}" "
        main:
            interval: 2s
            pid_file: /tmp/pw-${CONFIG}.pid
        sleep-120:
            pid_file: /tmp/sleep-120.pid
            start_command: ${BATS_TEST_DIRNAME}/sandbox/sleep-120 start
            stop_command: ${BATS_TEST_DIRNAME}/sandbox/sleep-120 stop
    "
    sleep 3

    run kill -0 "${APP1_PID}"
    echo "${output}" >&2
    [[ "${status}" -eq 0 ]]

    stop_pw "${CONFIG}"

    run kill -0 "${APP1_PID}"
    [[ "${status}" -ne 0 ]]
}

@test "restarting" {
    CONFIG=restarting
    start_pw "${CONFIG}" "
        main:
            interval: 4s
            pid_file: /tmp/pw-${CONFIG}.pid
        sleep-2:
            pid_file: /tmp/sleep-2.pid
            start_command: ${BATS_TEST_DIRNAME}/sandbox/sleep-2 start
            stop_command: ${BATS_TEST_DIRNAME}/sandbox/sleep-2 stop
    "
    sleep 1
    APP1_PID="$(cat /tmp/sleep-2.pid)"
    run kill -0 "${APP1_PID}"
    [[ "${status}" -eq 0 ]]

    sleep 6
    APP1_PID="$(cat /tmp/sleep-2.pid)"
    run kill -0 "${APP1_PID}"
    [[ "${status}" -ne 0 ]]

    stop_pw "${CONFIG}"
}

@test "cron-rerun" {
    CONFIG1=cron-rerun1
    start_pw "${CONFIG1}" "
        main:
            pid_file: /tmp/pw-${CONFIG1}.pid
    "
    sleep 1

    CONFIG2=cron-rerun2
    start_pw "${CONFIG2}" "
        main:
            pid_file: /tmp/pw-${CONFIG1}.pid
    "
    sleep 1
    run diff -u "${BATS_TEST_DIRNAME}/logs/${CONFIG2}.log" "${BATS_TMPDIR}/${CONFIG2}.log"
    echo "${output}" >&2
    [[ "${status}" -eq 0 ]]

    run kill -0 "$(cat /tmp/pw-${CONFIG1}.pid)"
    echo "${output}" >&2
    [[ "${status}" -eq 0 ]]

    stop_pw "${CONFIG1}"
}

@test "config-changes" {
    CONFIG=config-changes
    start_pw "${CONFIG}" "
        main:
            interval: 2s
            pid_file: /tmp/pw-${CONFIG}.pid
    "
    sleep 1
    echo "
        sleep-120:
            pid_file: /tmp/sleep-120.pid
            start_command: ${BATS_TEST_DIRNAME}/sandbox/sleep-120 start
            stop_command: ${BATS_TEST_DIRNAME}/sandbox/sleep-120 stop
    " >> ${BATS_TMPDIR}/${CONFIG}.yaml
    sleep 3

    APP1_PID="$(cat /tmp/sleep-120.pid)"
    run kill -0 "${APP1_PID}"
    echo "${output}" >&2
    [[ "${status}" -eq 0 ]]

    stop_pw "${CONFIG}"

    run kill -0 "${APP1_PID}"
    [[ "${status}" -ne 0 ]]
}

@test "nohup" {
    CONFIG=nohup
    start_pw "${CONFIG}" "
        main:
            interval: 2s
            pid_file: /tmp/pw-${CONFIG}.pid
        nohup:
            pid_file: /tmp/nohup.pid
            start_command: ${BATS_TEST_DIRNAME}/sandbox/nohup start
            stop_command: ${BATS_TEST_DIRNAME}/sandbox/nohup stop
    "
    sleep 3
    APP1_PID="$(cat /tmp/nohup.pid)"
    run kill -0 "${APP1_PID}"
    [[ "${status}" -eq 0 ]]

    stop_pw "${CONFIG}"

    APP1_PID="$(cat /tmp/nohup.pid)"
    run kill -0 "${APP1_PID}"
    [[ "${status}" -ne 0 ]]
}
