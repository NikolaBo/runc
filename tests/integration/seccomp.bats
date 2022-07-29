#!/usr/bin/env bats

load helpers

function setup() {
	setup_busybox
}

function teardown() {
	teardown_bundle
}

@test "runc run [seccomp -ENOSYS handling]" {
	TEST_NAME="seccomp_syscall_test1"

	# Compile the test binary and update the config to run it.
	gcc -static -o rootfs/seccomp_test "${TESTDATA}/${TEST_NAME}.c"
	update_config ".linux.seccomp = $(<"${TESTDATA}/${TEST_NAME}.json")"
	update_config '.process.args = ["/seccomp_test"]'

	runc run test_busybox
	[ "$status" -eq 0 ]
}

@test "runc run [seccomp defaultErrnoRet=ENXIO]" {
	TEST_NAME="seccomp_syscall_test2"

	# Compile the test binary and update the config to run it.
	gcc -static -o rootfs/seccomp_test2 "${TESTDATA}/${TEST_NAME}.c"
	update_config ".linux.seccomp = $(<"${TESTDATA}/${TEST_NAME}.json")"
	update_config '.process.args = ["/seccomp_test2"]'

	runc run test_busybox
	[ "$status" -eq 0 ]
}

# TODO:
# - Test other actions like SCMP_ACT_TRAP, SCMP_ACT_TRACE, SCMP_ACT_LOG.
# - Test args (index, value, valueTwo, etc).

@test "runc run [seccomp] (SCMP_ACT_ERRNO default)" {
	update_config '   .process.args = ["/bin/sh", "-c", "mkdir /dev/shm/foo"]
			| .process.noNewPrivileges = false
			| .linux.seccomp = {
				"defaultAction":"SCMP_ACT_ALLOW",
				"architectures":["SCMP_ARCH_X86","SCMP_ARCH_X32","SCMP_ARCH_X86_64","SCMP_ARCH_AARCH64","SCMP_ARCH_ARM"],
				"syscalls":[{"names":["mkdir","mkdirat"], "action":"SCMP_ACT_ERRNO"}]
			}'

	runc run test_busybox
	[ "$status" -ne 0 ]
	[[ "$output" == *"mkdir:"*"/dev/shm/foo"*"Operation not permitted"* ]]
}

@test "runc run [seccomp] (SCMP_ACT_ERRNO explicit errno)" {
	update_config '   .process.args = ["/bin/sh", "-c", "mkdir /dev/shm/foo"]
			| .process.noNewPrivileges = false
			| .linux.seccomp = {
				"defaultAction":"SCMP_ACT_ALLOW",
				"architectures":["SCMP_ARCH_X86","SCMP_ARCH_X32","SCMP_ARCH_X86_64","SCMP_ARCH_AARCH64","SCMP_ARCH_ARM"],
				"syscalls":[{"names":["mkdir","mkdirat"], "action":"SCMP_ACT_ERRNO", "errnoRet": 100}]
			}'

	runc run test_busybox
	[ "$status" -ne 0 ]
	[[ "$output" == *"Network is down"* ]]
}

@test "runc run [seccomp] (SECCOMP_FILTER_FLAG_*)" {
	# Linux 4.14: SECCOMP_FILTER_FLAG_LOG
	# Linux 4.17: SECCOMP_FILTER_FLAG_SPEC_ALLOW
	requires_kernel 4.17
	SECCOMP_FILTER_FLAGS=(
		'' # no flag
		'"SECCOMP_FILTER_FLAG_LOG"'
		'"SECCOMP_FILTER_FLAG_SPEC_ALLOW"'
		'"SECCOMP_FILTER_FLAG_TSYNC"'
		'"SECCOMP_FILTER_FLAG_LOG","SECCOMP_FILTER_FLAG_SPEC_ALLOW"'
		'"SECCOMP_FILTER_FLAG_LOG","SECCOMP_FILTER_FLAG_TSYNC"'
		'"SECCOMP_FILTER_FLAG_SPEC_ALLOW","SECCOMP_FILTER_FLAG_TSYNC"'
		'"SECCOMP_FILTER_FLAG_LOG","SECCOMP_FILTER_FLAG_SPEC_ALLOW","SECCOMP_FILTER_FLAG_TSYNC"'
	)
	for flags in "${SECCOMP_FILTER_FLAGS[@]}"; do
		update_config '   .process.args = ["/bin/sh", "-c", "mkdir /dev/shm/foo"]
				| .process.noNewPrivileges = false
				| .linux.seccomp = {
					"defaultAction":"SCMP_ACT_ALLOW",
					"architectures":["SCMP_ARCH_X86","SCMP_ARCH_X32","SCMP_ARCH_X86_64","SCMP_ARCH_AARCH64","SCMP_ARCH_ARM"],
					"flags":['"${flags}"'],
					"syscalls":[{"names":["mkdir"], "action":"SCMP_ACT_ERRNO"}]
				}'

		# This test checks that the flags are accepted without errors but does
		# not check they are effectively applied
		runc run test_busybox
		[ "$status" -ne 0 ]
		[[ "$output" == *"mkdir:"*"/dev/shm/foo"*"Operation not permitted"* ]]
	done
}

@test "runc run [seccomp] (SCMP_ACT_KILL)" {
	update_config '  .process.args = ["/bin/sh", "-c", "mkdir /dev/shm/foo"]
			| .process.noNewPrivileges = false
			| .linux.seccomp = {
				"defaultAction":"SCMP_ACT_ALLOW",
				"architectures":["SCMP_ARCH_X86","SCMP_ARCH_X32","SCMP_ARCH_X86_64","SCMP_ARCH_AARCH64","SCMP_ARCH_ARM"],
				"syscalls":[{"names":["mkdir","mkdirat"], "action":"SCMP_ACT_KILL"}]
			}'

	runc run test_busybox
	[ "$status" -ne 0 ]
}

# check that a startContainer hook is run with the seccomp filters applied
@test "runc run [seccomp] (startContainer hook)" {
	update_config '   .process.args = ["/bin/true"]
			| .linux.seccomp = {
				"defaultAction":"SCMP_ACT_ALLOW",
				"architectures":["SCMP_ARCH_X86","SCMP_ARCH_X32","SCMP_ARCH_X86_64","SCMP_ARCH_AARCH64","SCMP_ARCH_ARM"],
				"syscalls":[{"names":["mkdir","mkdirat"], "action":"SCMP_ACT_KILL"}]
			}
			| .hooks = {
				"startContainer": [ {
						"path": "/bin/sh",
						"args": ["sh", "-c", "mkdir /dev/shm/foo"]
				} ]
			}'

	runc run test_busybox
	[ "$status" -ne 0 ]
	[[ "$output" == *"error running hook"* ]]
	[[ "$output" == *"bad system call"* ]]
}
