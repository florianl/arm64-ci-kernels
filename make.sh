#!/bin/bash

set -eu
set -o pipefail

readonly script_dir="$(cd "$(dirname "$0")"; pwd)"
readonly build_dir="${script_dir}/build"
readonly n="${NPROC:-$(nproc)}"

mkdir -p "${build_dir}"

fetch_and_configure() {
	local kernel_version="$1"
	local src_dir="$2"
	local archive="${build_dir}/linux-${kernel_version}.tar.xz"

	test -e "${archive}" || curl --fail -L "https://cdn.kernel.org/pub/linux/kernel/v${kernel_version%%.*}.x/linux-${kernel_version}.tar.xz" -o "${archive}"
	test -d "${src_dir}" || tar --xz -xf "${archive}" -C "${build_dir}"

	cd "${src_dir}"
	if [[ ! -f custom.config || "${script_dir}/config" -nt custom.config ]]; then
		echo "Configuring ${kernel_version}"
		make ARCH=arm64 KCONFIG_CONFIG=custom.config defconfig
		tee -a < "${script_dir}/config" custom.config
		make ARCH=arm64 allnoconfig KCONFIG_ALLCONFIG=custom.config
	fi
}

readonly kernel_versions=(
	"4.19.227"
	"5.4.176"
)

for kernel_version in "${kernel_versions[@]}"; do
	src_dir="${build_dir}/linux-${kernel_version}"

	if [[ -f "linux-${kernel_version}.arm64" ]]; then
		echo "Skipping ${kernel_version}, it already exist"
	else
		fetch_and_configure "$kernel_version" "$src_dir"
		cd "$src_dir"
		make clean
		taskset -c "0-$(($n - 1))" make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$n" Image

		cp "arch/arm64/boot/Image" "${script_dir}/linux-${kernel_version}.arm64"
	fi

	continue
done

