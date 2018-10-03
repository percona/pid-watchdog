#!/usr/bin/env bats

load helper

@test "start/stop" {
    local CONFIG="service-start-stop"
    prepare_service "${CONFIG}" "
        main:
            initrd_path: ${BATS_TEST_DIRNAME}/sandbox
            pid_path: /tmp
    "

    ./service sleep-120 start
    cat <<-EOF > "${BATS_TMPDIR}/${CONFIG}-etalon.yaml"
		main:
		  initrd_path: ${BATS_TEST_DIRNAME}/sandbox
		  interval: 15s
		  kill_interval: 4s
		  pid_file: pid-watchdog.pid
		  pid_path: /tmp
		sleep-120:
		  pid_file: /tmp/sleep-120.pid
		  start_command: ${BATS_TEST_DIRNAME}/sandbox/sleep-120
		    start
		  stop_command: ${BATS_TEST_DIRNAME}/sandbox/sleep-120
		    stop
	EOF
    run diff -u "${BATS_TMPDIR}/${CONFIG}-etalon.yaml" "${BATS_TMPDIR}/${CONFIG}.yaml"
    echo "${output}" >&2
    [[ "${status}" -eq 0 ]]

    sleep 1
    APP1_PID="$(cat /tmp/sleep-120.pid)"
    run kill -0 "${APP1_PID}"
    echo "${output}" >&2
    [[ "${status}" -eq 0 ]]

    ./service sleep-120 stop
    cat <<-EOF > "${BATS_TMPDIR}/${CONFIG}-etalon.yaml"
		main:
		  initrd_path: ${BATS_TEST_DIRNAME}/sandbox
		  interval: 15s
		  kill_interval: 4s
		  pid_file: pid-watchdog.pid
		  pid_path: /tmp
	EOF
    run diff -u "${BATS_TMPDIR}/${CONFIG}-etalon.yaml" "${BATS_TMPDIR}/${CONFIG}.yaml"
    echo "${output}" >&2
    [[ "${status}" -eq 0 ]]

    sleep 1
    APP1_PID="$(cat /tmp/sleep-120.pid)"
    run kill -0 "${APP1_PID}"
    echo "${output}" >&2
    [[ "${status}" -ne 0 ]]
}
