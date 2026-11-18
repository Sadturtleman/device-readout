#include <winrt/Windows.Foundation.h>
#include <cstdint>
#pragma comment(lib, "windowsapp.lib")

// Supply an actual Windows IReference<UInt64>, rather than a fixture vtable,
// to corroborate the collector's value getter against the OS projection ABI.
extern "C" int32_t readout_fixture_box_uint64(uint64_t value, void **output) {
    *output = nullptr;
    try {
        auto boxed = winrt::box_value(value).as<winrt::Windows::Foundation::IReference<uint64_t>>();
        *output = winrt::detach_abi(boxed);
        return 0;
    } catch (...) { return winrt::to_hresult(); }
}
