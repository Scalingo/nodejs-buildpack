#!/usr/bin/env bash

calculate_concurrency() {
	local available="${1}"
	local web_memory="${2}"

	echo $(( available / web_memory ))
}

validate_concurrency() {
	local concurrency="${1}"
	local ret=0

	if (( concurrency < 1 )); then
		concurrency=1
	elif (( concurrency > 200 )); then
		# Ex: This will happen on Dokku on DO
		concurrency=1
		ret=1
	fi

	echo "${concurrency}"
	return "${ret}"
}

log_concurrency() {
	echo "Detected ${MEMORY_AVAILABLE} MB available memory, ${WEB_MEMORY} MB limit per process (WEB_MEMORY)"
	echo "Recommending WEB_CONCURRENCY=${WEB_CONCURRENCY}"
}

detect_memory() {
	local default="${1}"

	local memory_limit_in_bytes
	local memory_limit_file_cgroupv1
	local memory_limit_file_cgroupv2
	local cgroup_root="${WEB_CONCURRENCY_CGROUP_ROOT:-/sys/fs/cgroup}"

	# cgroup v1 - reports the memory limit in memory/memory.limit_in_bytes
	memory_limit_file_cgroupv1="${cgroup_root}/memory/memory.limit_in_bytes"

	# cgroups v2 - reports the memory limit in memory.max
	memory_limit_file="${cgroup_root}/memory.max"

	if [[ -f "${memory_limit_file_cgroupv2}" ]]; then
		memory_limit_in_bytes="$( cat "${memory_limit_file_cgroupv2}" )"

		if [[ "${memory_limit_in_bytes}" == 'max' ]]; then
			unset memory_limit_in_bytes
		fi

	elif [[ -f "${memory_limit_file_cgroupv1}" ]]; then
		memory_limit_in_bytes="$( cat "${memory_limit_file_cgroupv1}" )"

		# Ignore values above 1TiB RAM, since when using cgroups v1 the limits file reports a
		# bogus value of thousands of TiB RAM when there is no container memory limit set.
		if (( memory_limit_in_bytes > 1099511627776 )); then
			unset memory_limit_in_bytes
		fi
	fi

	if [[ -n "${memory_limit_in_bytes}" ]]; then
		local memory_limit_in_mb=$(( memory_limit_in_bytes / 1048576 ))

		echo "${memory_limit_in_mb}"
	else
		echo "${default}"
	fi
}

bound_memory() {
	local detected="${1}"
	# Memory is bound to the maximum memory of known dyno types: ~126 GB
	local max_detected_memory=129024

	if (( detected > max_detected_memory )); then
		echo "${max_detected_memory}"
	else
		echo "${detected}"
	fi
}

default_web_memory() {
	local available_memory="${1}"

	# Allow more memory per process on memory heavy dyno types.
	if (( available_memory > 16384 )); then
		echo 2048
	else
		echo 512
	fi
}

warn_web_concurrency() {
	echo "Could not determine a reasonable value for WEB_CONCURRENCY.
This is likely due to running the buildpack on a non-compatible platform.

WEB_CONCURRENCY has been set to ${1}. Please review whether this value is
appropriate for your application.
"
}

DETECTED=$(detect_memory 512)
export MEMORY_AVAILABLE=${MEMORY_AVAILABLE-"$( bound_memory "${DETECTED}" )"}
export WEB_MEMORY=${WEB_MEMORY-"$(default_web_memory "${MEMORY_AVAILABLE}" )"}

# Calculate/validate WEB_CONCURRENCY if not already set
if [ -z "${WEB_CONCURRENCY}" ]; then
	calculated_concurrency="$( calculate_concurrency "${MEMORY_AVAILABLE}" "${WEB_MEMORY}" )"

	if ! validated_concurrency="$( validate_concurrency "${calculated_concurrency}" )"; then
		warn_web_concurrency "${validated_concurrency}"
	fi

	export WEB_CONCURRENCY="${validated_concurrency}"
	export WEB_CONCURRENCY_SET_BY="scalingo/nodejs"
fi

if [[ "${LOG_CONCURRENCY+isset}" && "${LOG_CONCURRENCY}" == "true" ]]; then
	log_concurrency
fi
