#include <winrt/Windows.Networking.Connectivity.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <cstdint>
#pragma comment(lib, "windowsapp.lib")

// Independent Windows SDK C++/WinRT projection, not the collector's ABI code.
extern "C" __declspec(dllexport) uint64_t readout_probe_connectivity(void) {
    try {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
        struct Apartment { ~Apartment() { winrt::uninit_apartment(); } } apartment;
        using winrt::Windows::Networking::Connectivity::NetworkInformation;
        auto profile = NetworkInformation::GetInternetConnectionProfile();
        uint64_t value = 0;
        if (profile) {
            auto level = static_cast<uint32_t>(profile.GetNetworkConnectivityLevel());
            auto cost = static_cast<uint32_t>(profile.GetConnectionCost().NetworkCostType());
            if (level > 255 || cost > 255) return UINT64_MAX;
            value = 1 | (uint64_t(level) << 8) | (uint64_t(cost) << 16);
        }
        auto token = NetworkInformation::NetworkStatusChanged([](auto const&) {});
        NetworkInformation::NetworkStatusChanged(token);
        return value;
    } catch (...) { return UINT64_MAX; }
}

struct PerformanceProbe { int32_t status, present; double inbound, outbound; };
extern "C" __declspec(dllexport) uint64_t readout_probe_wifi(void) {
    try {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
        struct Apartment { ~Apartment() { winrt::uninit_apartment(); } } apartment;
        using namespace winrt::Windows::Networking::Connectivity;
        uint64_t count=0;
        for(auto const& profile:NetworkInformation::GetConnectionProfiles())
            if(profile.IsWlanConnectionProfile() && profile.GetNetworkConnectivityLevel()!=NetworkConnectivityLevel::None) ++count;
        auto preferred=NetworkInformation::GetInternetConnectionProfile();
        const bool current=preferred && preferred.IsWlanConnectionProfile() && preferred.GetNetworkConnectivityLevel()!=NetworkConnectivityLevel::None;
        return count | (uint64_t(current)<<32);
    } catch (...) { return UINT64_MAX; }
}
extern "C" __declspec(dllexport) PerformanceProbe readout_probe_network_performance(void) {
    PerformanceProbe result = {};
    try {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
        struct Apartment { ~Apartment() { winrt::uninit_apartment(); } } apartment;
        auto profile = winrt::Windows::Networking::Connectivity::NetworkInformation::GetInternetConnectionProfile();
        if (profile) {
            auto plan = profile.GetDataPlanStatus();
            if (plan) {
                auto inbound = plan.InboundBitsPerSecond();
                auto outbound = plan.OutboundBitsPerSecond();
                if (inbound) { result.present |= 1; result.inbound = static_cast<double>(inbound.Value()); }
                if (outbound) { result.present |= 2; result.outbound = static_cast<double>(outbound.Value()); }
            }
        }
    } catch (...) { result.status = -1; }
    return result;
}
