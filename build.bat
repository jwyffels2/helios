
pushd "%~dp0"
call .\build_neorv32.bat

podman build -t helios-build -f ./build.dockerfile .

podman run --rm -v "%CD% :/workspace" -w /workspace helios-build ./build_hal_fw.sh

popd
