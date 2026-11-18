#include <windows.h>
#include <winrt/Windows.Devices.Power.h>
#include <winrt/Windows.System.Power.h>
#include <winrt/Windows.Foundation.h>
#include <cstdint>
#include <setupapi.h>
#include <winioctl.h>
#include <poclass.h>
#include <vector>
#pragma comment(lib, "windowsapp.lib")
#pragma comment(lib, "setupapi.lib")

// Independent present-pack count through the documented device protocol.
extern "C" __declspec(dllexport) int64_t readout_probe_battery_pack_count(void) {
    const GUID batteryClass={0x72631e54,0x78a4,0x11d0,{0xbc,0xf7,0x00,0xaa,0x00,0xb7,0xb3,0x2a}};
    HDEVINFO set=SetupDiGetClassDevsW(&batteryClass,nullptr,nullptr,DIGCF_PRESENT|DIGCF_DEVICEINTERFACE);
    if(set==INVALID_HANDLE_VALUE) return -static_cast<int64_t>(GetLastError());
    DWORD failure=0;int64_t count=0;
    for(DWORD index=0;;index++) {
        SP_DEVICE_INTERFACE_DATA item={};item.cbSize=sizeof(item);
        if(!SetupDiEnumDeviceInterfaces(set,nullptr,&batteryClass,index,&item)) {failure=GetLastError();if(failure==ERROR_NO_MORE_ITEMS) failure=0;break;}
        DWORD bytes=0;SetupDiGetDeviceInterfaceDetailW(set,&item,nullptr,0,&bytes,nullptr);
        if(GetLastError()!=ERROR_INSUFFICIENT_BUFFER || bytes<6 || bytes>65536) {failure=ERROR_INVALID_DATA;break;}
        std::vector<unsigned char> buffer(bytes);auto detail=reinterpret_cast<SP_DEVICE_INTERFACE_DETAIL_DATA_W*>(buffer.data());detail->cbSize=sizeof(*detail);
        if(!SetupDiGetDeviceInterfaceDetailW(set,&item,detail,bytes,nullptr,nullptr)) {failure=GetLastError();break;}
        HANDLE device=CreateFileW(detail->DevicePath,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
        if(device==INVALID_HANDLE_VALUE) {failure=GetLastError();break;}
        ULONG wait=0,tag=0,written=0;
        if(!DeviceIoControl(device,IOCTL_BATTERY_QUERY_TAG,&wait,sizeof(wait),&tag,sizeof(tag),&written,nullptr)) failure=GetLastError();
        else if(written!=sizeof(tag)) failure=ERROR_INVALID_DATA;
        else if(tag) ++count;
        if(!CloseHandle(device) && !failure) failure=GetLastError();
        if(failure) break;
    }
    if(!SetupDiDestroyDeviceInfoList(set) && !failure) failure=GetLastError();
    return failure?-static_cast<int64_t>(failure):count;
}

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
