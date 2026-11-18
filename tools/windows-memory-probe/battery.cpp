#include <windows.h>
#include <winrt/Windows.Devices.Power.h>
#include <winrt/Windows.System.Power.h>
#include <winrt/Windows.Foundation.h>
#include <cstdint>
#pragma comment(lib, "windowsapp.lib")

struct BatteryProbe { int32_t status,mask,rate,design,full,remaining,state;uint32_t time; };
// Independent SDK projection; no handwritten production ABI or collector helpers.
extern "C" __declspec(dllexport) BatteryProbe readout_probe_battery(void) {
    BatteryProbe value={};
    try {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
        struct Apartment {~Apartment(){winrt::uninit_apartment();}} apartment;
        auto battery=winrt::Windows::Devices::Power::Battery::AggregateBattery();
        auto report=battery.GetReport();
        value.state=static_cast<int32_t>(report.Status());value.mask=16;
        if(auto v=report.ChargeRateInMilliwatts()) {value.mask|=1;value.rate=v.Value();}
        if(auto v=report.DesignCapacityInMilliwattHours()) {value.mask|=2;value.design=v.Value();}
        if(auto v=report.FullChargeCapacityInMilliwattHours()) {value.mask|=4;value.full=v.Value();}
        if(auto v=report.RemainingCapacityInMilliwattHours()) {value.mask|=8;value.remaining=v.Value();}
        SYSTEM_POWER_STATUS power={};
        if(GetSystemPowerStatus(&power) && power.ACLineStatus!=1 &&
            !(power.BatteryFlag!=255 && (power.BatteryFlag&128)) && power.BatteryLifeTime!=UINT32_MAX) {
            value.mask|=32;value.time=power.BatteryLifeTime;
        }
        auto token=battery.ReportUpdated([](auto const&,auto const&) {});
        battery.ReportUpdated(token);
    } catch (...) {value.status=-1;}
    return value;
}
