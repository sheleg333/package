#!/usr/bin/env bash

source /multibuild/manylinux_utils.sh
source /opt/rh/gcc-toolset-12/enable # GCC-11 is the hightest GCC version compatible with NVCC < 12

function usage() {
    echo "Usage: $0 [--gpu GPU-VERSION]"
    echo
    echo -e "--gpu {none cuda-11.8 cuda-12.1 cuda-12.2}"
    echo -e "\tSpecify the GPU version (CUDA/ROCm) in the TVM (default: none)."
}

function in_array() {
    KEY=$1
    ARRAY=$2
    for e in ${ARRAY[*]}; do
        if [[ "$e" == "$1" ]]; then
            return 0
        fi
    done
    return 1
}

function build_mlc_ai_wheel() {
    python_dir=$1
    PYTHON_BIN="${python_dir}/bin/python"

    cd "${TVM_PYTHON_DIR}" && \
        ${PYTHON_BIN} setup.py bdist_wheel
}

function audit_mlc_ai_wheel() {
    python_version_str=$1

    cd "${TVM_PYTHON_DIR}" && \
      mkdir -p repaired_wheel && \
      auditwheel repair ${AUDITWHEEL_OPTS} dist/*cp${python_version_str}*.whl
}

TVM_PYTHON_DIR="/workspace/tvm/python"
PYTHON_VERSIONS_CPU=("3.10" "3.11")
PYTHON_VERSIONS_GPU=("3.10" "3.11")
GPU_OPTIONS=("none" "cuda-11.8" "cuda-12.1" "cuda-12.2")
GPU="none"

while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
        --gpu)
            GPU=$2
            shift
            shift
            ;;
        -h|--help)
            usage
            exit -1
            ;;
        *) # unknown option
            echo "Unknown argument: $arg"
            echo
            usage
            exit -1
            ;;
    esac
done

if ! in_array "${GPU}" "${GPU_OPTIONS[*]}" ; then
    echo "Invalid GPU option: ${GPU}"
    echo
    echo 'GPU version can only be {"none", "cuda-11.8" "cuda-12.1" "cuda-12.1"}'
    exit -1
fi

if [[ ${GPU} == "none" ]]; then
    echo "Building TVM for CPU only"
    PYTHON_VERSIONS=${PYTHON_VERSIONS_CPU[*]}
else
    echo "Building TVM with GPU ${GPU}"
    PYTHON_VERSIONS=${PYTHON_VERSIONS_GPU[*]}
fi

AUDITWHEEL_OPTS="--plat ${AUDITWHEEL_PLAT} -w repaired_wheels/"
if [[ ${GPU} == "rocm" ]]; then
    AUDITWHEEL_OPTS="--exclude libamdhip64 --exclude libhsa-runtime64 ${AUDITWHEEL_OPTS}"
elif [[ ${GPU} != "none" ]]; then
    AUDITWHEEL_OPTS="--exclude libcuda --exclude libcudart --exclude libnvrtc ${AUDITWHEEL_OPTS}"
fi

cd /workspace/tvm
echo set\(USE_LLVM \"llvm-config --ignore-libllvm --link-static\"\) >> config.cmake
echo set\(HIDE_PRIVATE_SYMBOLS ON\) >> config.cmake
echo set\(USE_RPC ON\) >> config.cmake
echo set\(CMAKE_CUDA_ARCHITECTURES "89"\) >> config.cmake
echo set\(CUDA_ARCHITECTURES "89"\) >> config.cmake

# remove debug
echo set\(USE_LIBBACKTRACE OFF \) >> config.cmake
echo set\(USE_GRAPH_EXECUTOR OFF \) >> config.cmake
echo set\(USE_PROFILER OFF \) >> config.cmake
echo set\(USE_RELAY_DEBUG OFF \) >> config.cmake

if [[ ${GPU} == "rocm" ]]; then
    echo set\(USE_ROCM ON\) >> config.cmake
elif [[ ${GPU} == "none" ]]; then
    echo set\(USE_VULKAN ON\) >> config.cmake
elif [[ ${GPU} != "none" ]]; then
    echo set\(USE_CUDA ON\) >> config.cmake
    echo set\(USE_CUTLASS ON\) >> config.cmake
    echo set\(USE_VULKAN OFF\) >> config.cmake
fi

# compile the tvm
git config --global --add safe.directory /workspace/tvm
mkdir -p build
cd build
cmake ..
make -j$(nproc)

UNICODE_WIDTH=32  # Dummy value, irrelevant for Python 3

# Not all manylinux Docker images will have all Python versions,
# so check the existing python versions before generating packages
for python_version in ${PYTHON_VERSIONS[*]}
do
    echo "> Looking for Python ${python_version}."

    # Remove the . in version string, e.g. "3.8" turns into "38"
    python_version_str="$(echo "${python_version}" | sed -r 's/\.//g')"
    cpython_dir="/opt/conda/envs/py${python_version_str}/"

    # For compatibility in environments where Conda is not installed,
    # revert back to previous method of locating cpython_dir.
    if ! [ -d "${cpython_dir}" ]; then
      cpython_dir=$(cpython_path "${python_version}" "${UNICODE_WIDTH}" 2> /dev/null)
    fi

    if [ -d "${cpython_dir}" ]; then
      echo "Generating package for Python ${python_version}."
      build_mlc_ai_wheel ${cpython_dir}

      echo "Running auditwheel on package for Python ${python_version}"
      audit_mlc_ai_wheel ${python_version_str}
    else
      echo "Python ${python_version} not found. Skipping.";
    fi

done
