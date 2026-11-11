// Generated from the common DeviceReadout schema.
#nullable enable
using System.Collections.Immutable;
namespace DeviceReadout;

public enum FormFactor { Phone, Tablet, Laptop, Desktop, Television, Watch, Automotive, Headset }
public enum OsFamily { Android, IOS, IPadOS, Windows, MacOS, Linux, ChromeOS }
public enum Architecture { X86, X64, Arm32, Arm64, RiscV32, RiscV64, Wasm32, Wasm64 }
public enum Abi { ArmeabiV7a, Arm64V8a, X86, X86_64 }
public enum HourCycle { H11, H12, H23, H24 }
public enum Weekday { Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday }
public enum MeasurementSystem { Metric, US, UK }
public enum WindowsIdentitySource { Tpm, Uefi, Registry }
public enum DisplayState { On, Off, Doze, DozeSuspended, OnSuspended }
public enum DisplayOrientation { PortraitPrimary, PortraitSecondary, LandscapePrimary, LandscapeSecondary }
public enum ColorGamut { Srgb, DisplayP3, Rec2020 }
public enum HdrFormat { Hdr10, Hdr10Plus, DolbyVision, Hlg }
public enum PowerSource { Battery, External, Ups }
public enum AndroidThermalState { None, Light, Moderate, Severe, Critical, Emergency, Shutdown }
public enum AppleThermalState { Nominal, Fair, Serious, Critical }
public enum BatteryState { Charging, Discharging, Full, NotCharging, Idle }
public enum BatteryHealth { Good, Overheated, Cold, Dead, OverVoltage, UnspecifiedFailure }
public enum ConnectionState { Connected, Disconnected, Connecting, Disconnecting, Suspended, ConnectionRequired }
public enum NetworkTransport { Wifi, Cellular, Ethernet, Bluetooth, Vpn, Usb, WifiAware, Lowpan, Thread, Satellite }
public enum EffectiveConnectionType { Slow2G, Type2G, Type3G, Type4G }
public enum NetworkInterfaceType { Ethernet, Wifi, Cellular, Bluetooth, Loopback, Tunnel, Ppp, Bridge }
public enum NetworkOperationalState { Up, Down, Testing, Dormant, NotPresent, LowerLayerDown }
public enum WifiSecurity { Open, Wep, Psk, Eap, Sae, Owe, WapiPsk, WapiCert, EapWpa3Enterprise, EapWpa3Enterprise192Bit, PasspointR1R2, PasspointR3, Dpp }
public enum RadioTechnology { Gsm, Gprs, Edge, Cdma, Cdma1x, Evdo0, EvdoA, EvdoB, Ehrpd, Umts, Hsdpa, Hsupa, Hspa, HspaPlus, Iden, TdScdma, Lte, LteCa, Nr, NrNsa, NrSa, Iwlan }
public enum StorageCategory { IndexedDB, Caches, ServiceWorker, FileSystem, LocalStorage, SessionStorage }
public enum SensorReportingMode { Continuous, OnChange, OneShot, SpecialTrigger }
public enum SensorKind { Accelerometer, LinearAcceleration, Gravity, Gyroscope, Magnetometer, RelativeOrientation, AbsoluteOrientation, Illuminance, Pressure, AmbientTemperature, RelativeHumidity, ProximityNear, ProximityDistance, RelativeAltitude, HingeAngle, StepCountSinceBoot, StepDetected, SignificantMotion, HumanPresence }
public enum EntityKind { DeviceInfo, Os, Runtime, Cpu, CpuCore, Ram, ProcessMemory, Locale, TimeZone, AndroidBuild, AndroidIdentity, AppleVendorIdentity, WindowsPublisherIdentity, MacPlatformIdentity, HardwareSerial, TelephonyIdentity, Display, Viewport, Power, Battery, NetworkPath, NetworkPerformance, NetworkInterface, WifiConnection, CellularSubscription, StorageVolume, OriginStorage, Accelerometer, LinearAcceleration, Gravity, Gyroscope, Magnetometer, RelativeOrientation, AbsoluteOrientation, Illuminance, Pressure, AmbientTemperature, RelativeHumidity, ProximityNear, ProximityDistance, RelativeAltitude, HingeAngle, StepCountSinceBoot, StepDetected, SignificantMotion, HumanPresence }

public sealed record DeviceInfoSnapshot : DeviceSnapshot
{
    /// <summary>제조사</summary>
    public string? Manufacturer { get; init; }
    /// <summary>브랜드</summary>
    public string? Brand { get; init; }
    /// <summary>플랫폼의 모델 코드</summary>
    public string? ModelCode { get; init; }
    /// <summary>사용자에게 표시할 모델 이름</summary>
    public string? ModelName { get; init; }
    /// <summary>OS가 공개하는 기기 이름</summary>
    public string? DeviceName { get; init; }
    /// <summary>휴대전화·태블릿·노트북 등 기기 형태</summary>
    public FormFactor? FormFactor { get; init; }
    /// <summary>제품 식별 이름</summary>
    public string? Product { get; init; }
    /// <summary>보드 식별 이름</summary>
    public string? Board { get; init; }
}

public sealed record OsSnapshot : DeviceSnapshot
{
    /// <summary>운영체제 계열</summary>
    public OsFamily? Family { get; init; }
    /// <summary>운영체제 이름</summary>
    public string? Name { get; init; }
    /// <summary>운영체제 버전</summary>
    public string? Version { get; init; }
    /// <summary>운영체제 빌드</summary>
    public string? Build { get; init; }
    /// <summary>커널 이름</summary>
    public string? KernelName { get; init; }
    /// <summary>커널 버전</summary>
    public string? KernelVersion { get; init; }
}

public sealed record RuntimeSnapshot : DeviceSnapshot
{
    /// <summary>호스트 시스템 아키텍처</summary>
    public Architecture? HostArchitecture { get; init; }
    /// <summary>현재 프로세스 아키텍처</summary>
    public Architecture? ProcessArchitecture { get; init; }
    /// <summary>현재 프로세스 비트 수</summary>
    public int? ProcessBitness { get; init; }
    /// <summary>플랫폼이 공개하는 지원 ABI 집합</summary>
    public ImmutableHashSet<Abi>? SupportedAbis { get; init; }
}

public sealed record CpuSnapshot : DeviceSnapshot
{
    /// <summary>CPU 모델</summary>
    public string? Model { get; init; }
    /// <summary>CPU 제조사</summary>
    public string? Manufacturer { get; init; }
    /// <summary>SoC 모델</summary>
    public string? SocModel { get; init; }
    /// <summary>SoC 제조사</summary>
    public string? SocManufacturer { get; init; }
    /// <summary>전체 논리 프로세서 수</summary>
    public int? LogicalProcessorCount { get; init; }
    /// <summary>현재 실행 환경에 제공되는 논리 프로세서 수</summary>
    public int? AvailableLogicalProcessorCount { get; init; }
    /// <summary>물리 코어 수</summary>
    public int? PhysicalCoreCount { get; init; }
    /// <summary>프로세서 패키지 수</summary>
    public int? ProcessorPackageCount { get; init; }
}

public sealed record CpuCoreSnapshot : DeviceSnapshot
{
    /// <summary>논리 프로세서 인덱스</summary>
    public int? LogicalIndex { get; init; }
    /// <summary>소속 물리 코어 인덱스</summary>
    public int? CoreIndex { get; init; }
    /// <summary>소속 프로세서 패키지 인덱스</summary>
    public int? PackageIndex { get; init; }
    /// <summary>OS에서 사용 가능한 온라인 상태</summary>
    public bool? Online { get; init; }
    /// <summary>현재 클록 주파수</summary>
    public double? CurrentClockHz { get; init; }
    /// <summary>플랫폼이 보고하는 최대 클록 주파수</summary>
    public double? MaximumClockHz { get; init; }
}

public sealed record RamSnapshot : DeviceSnapshot
{
    /// <summary>설치된 물리 RAM 용량</summary>
    public ulong? PhysicalBytes { get; init; }
    /// <summary>커널이 접근 가능한 RAM 용량</summary>
    public ulong? KernelAccessibleBytes { get; init; }
    /// <summary>플랫폼이 외부에 공개하는 표기용 RAM 용량</summary>
    public ulong? AdvertisedBytes { get; init; }
    /// <summary>OS 정의상 사용 가능한 메모리</summary>
    public ulong? AvailableBytes { get; init; }
    /// <summary>OS 정의상 비어 있는 메모리</summary>
    public ulong? FreeBytes { get; init; }
    /// <summary>OS가 보고하는 메모리 부족 상태</summary>
    public bool? LowMemory { get; init; }
    /// <summary>OS가 공개하는 메모리 부족 기준 용량</summary>
    public ulong? LowMemoryThresholdBytes { get; init; }
}

public sealed record ProcessMemorySnapshot : DeviceSnapshot
{
    /// <summary>현재 앱이 추가로 할당할 수 있다고 플랫폼이 보고하는 메모리</summary>
    public ulong? AllocationRemainingBytes { get; init; }
}

public sealed record LocaleSnapshot : DeviceSnapshot
{
    /// <summary>현재 유효한 언어 태그</summary>
    public string? CurrentLanguageTag { get; init; }
    /// <summary>선호 언어 태그. 원래 우선순위 보존</summary>
    public ImmutableArray<string>? PreferredLanguageTags { get; init; }
    /// <summary>시스템 언어 태그 목록</summary>
    public ImmutableArray<string>? SystemLanguageTags { get; init; }
    /// <summary>앱에 적용된 언어 태그 목록</summary>
    public ImmutableArray<string>? AppLanguageTags { get; init; }
    /// <summary>로케일 지역 코드</summary>
    public string? RegionCode { get; init; }
    /// <summary>문자 체계 코드</summary>
    public string? ScriptCode { get; init; }
    /// <summary>달력 체계 식별자</summary>
    public string? Calendar { get; init; }
    /// <summary>숫자 표기 체계 식별자</summary>
    public string? NumberingSystem { get; init; }
    /// <summary>시간 표기 주기</summary>
    public HourCycle? HourCycle { get; init; }
    /// <summary>한 주의 첫 요일</summary>
    public Weekday? FirstWeekday { get; init; }
    /// <summary>도량형 체계</summary>
    public MeasurementSystem? MeasurementSystem { get; init; }
}

public sealed record TimeZoneSnapshot : DeviceSnapshot
{
    /// <summary>IANA 시간대 식별자</summary>
    public string? IanaId { get; init; }
    /// <summary>Windows 시간대 식별자</summary>
    public string? WindowsId { get; init; }
    /// <summary>수집 시점의 UTC 오프셋 초</summary>
    public int? UtcOffsetSeconds { get; init; }
    /// <summary>수집 시점의 서머타임 적용 여부</summary>
    public bool? DaylightSavingTime { get; init; }
}

public sealed record AndroidBuildSnapshot : DeviceSnapshot
{
    /// <summary>Android API 수준</summary>
    public int? ApiLevel { get; init; }
    /// <summary>플랫폼이 공개하는 보안 패치 날짜</summary>
    public string? SecurityPatch { get; init; }
    /// <summary>빌드 ID</summary>
    public string? BuildId { get; init; }
    /// <summary>표시용 빌드 문자열</summary>
    public string? BuildDisplay { get; init; }
    /// <summary>OS 빌드를 식별하는 fingerprint</summary>
    public string? BuildFingerprint { get; init; }
    /// <summary>빌드 유형</summary>
    public string? BuildType { get; init; }
    /// <summary>빌드 태그</summary>
    public ImmutableArray<string>? BuildTags { get; init; }
    /// <summary>부트로더 버전</summary>
    public string? BootloaderVersion { get; init; }
}

public sealed record AndroidIdentitySnapshot : DeviceSnapshot
{
    /// <summary>플랫폼이 제공하는 ANDROID_ID</summary>
    public string? AndroidId { get; init; }
}

public sealed record AppleVendorIdentitySnapshot : DeviceSnapshot
{
    /// <summary>vendor 범위의 식별자</summary>
    public string? VendorId { get; init; }
}

public sealed record WindowsPublisherIdentitySnapshot : DeviceSnapshot
{
    /// <summary>publisher 범위의 시스템 식별자</summary>
    public string? PublisherId { get; init; }
    /// <summary>식별자 생성에 사용된 플랫폼 소스</summary>
    public WindowsIdentitySource? Source { get; init; }
}

public sealed record MacPlatformIdentitySnapshot : DeviceSnapshot
{
    /// <summary>플랫폼 UUID</summary>
    public string? PlatformUuid { get; init; }
}

public sealed record HardwareSerialSnapshot : DeviceSnapshot
{
    /// <summary>플랫폼이 허용해 공개하는 하드웨어 일련번호</summary>
    public string? Serial { get; init; }
}

public sealed record TelephonyIdentitySnapshot : DeviceSnapshot
{
    /// <summary>접근이 허용된 IMEI</summary>
    public string? Imei { get; init; }
    /// <summary>접근이 허용된 MEID</summary>
    public string? Meid { get; init; }
}

public sealed record DisplaySnapshot : DeviceSnapshot
{
    /// <summary>화면 표시 이름</summary>
    public string? Label { get; init; }
    /// <summary>기본 화면 여부</summary>
    public bool? Primary { get; init; }
    /// <summary>내장 화면 여부</summary>
    public bool? Internal { get; init; }
    /// <summary>화면의 전원·표시 상태</summary>
    public DisplayState? State { get; init; }
    /// <summary>화면의 논리 좌표 영역</summary>
    public Rect? LogicalBounds { get; init; }
    /// <summary>사용 가능한 작업 영역</summary>
    public Rect? WorkAreaBounds { get; init; }
    /// <summary>픽셀 크기</summary>
    public Size<int>? PixelSize { get; init; }
    /// <summary>물리 크기 mm</summary>
    public Size<double>? PhysicalSizeMillimeters { get; init; }
    /// <summary>화면 방향</summary>
    public DisplayOrientation? Orientation { get; init; }
    /// <summary>기준 방향에 대한 회전 각도</summary>
    public double? RotationDegrees { get; init; }
    /// <summary>논리 단위와 픽셀 사이 배율</summary>
    public double? ScaleFactor { get; init; }
    /// <summary>인치당 픽셀 밀도</summary>
    public double? DensityDpi { get; init; }
    /// <summary>현재 화면 모드</summary>
    public DisplayMode? CurrentMode { get; init; }
    /// <summary>지원 화면 모드 목록</summary>
    public ImmutableArray<DisplayMode>? SupportedModes { get; init; }
    /// <summary>플랫폼이 공개하는 최대 주사율</summary>
    public double? MaximumRefreshRateHz { get; init; }
    /// <summary>플랫폼이 보고하는 색 깊이</summary>
    public int? ColorDepthBits { get; init; }
    /// <summary>플랫폼이 보고하는 화면 색역</summary>
    public ColorGamut? ColorGamut { get; init; }
    /// <summary>지원 HDR 형식 집합</summary>
    public ImmutableHashSet<HdrFormat>? HdrFormats { get; init; }
    /// <summary>밝기 0–1</summary>
    public double? Brightness { get; init; }
}

public sealed record ViewportSnapshot : DeviceSnapshot
{
    /// <summary>레이아웃 뷰포트 크기</summary>
    public Size<double>? Size { get; init; }
    /// <summary>현재 보이는 뷰포트 크기</summary>
    public Size<double>? VisualViewportSize { get; init; }
    /// <summary>시각 뷰포트 확대 배율</summary>
    public double? VisualViewportScale { get; init; }
    /// <summary>안전 영역 여백</summary>
    public Insets? SafeAreaInsets { get; init; }
    /// <summary>텍스트 확대 배율</summary>
    public double? TextScaleFactor { get; init; }
}

public sealed record PowerSnapshot : DeviceSnapshot
{
    /// <summary>전원 공급원</summary>
    public PowerSource? PowerSource { get; init; }
    /// <summary>절전 모드 적용 여부</summary>
    public bool? PowerSaveMode { get; init; }
    /// <summary>플랫폼별 열 상태 타입의 합집합</summary>
    public ThermalState? ThermalState { get; init; }
}

public sealed record BatterySnapshot : DeviceSnapshot
{
    /// <summary>배터리 존재 여부</summary>
    public bool? Present { get; init; }
    /// <summary>충전 잔량 비율 0–1</summary>
    public double? Level { get; init; }
    /// <summary>충전 중 여부</summary>
    public bool? Charging { get; init; }
    /// <summary>충전·방전 등 상태</summary>
    public BatteryState? State { get; init; }
    /// <summary>완충까지 남은 시간</summary>
    public TimeSpan? TimeToFull { get; init; }
    /// <summary>소진까지 남은 시간</summary>
    public TimeSpan? TimeToEmpty { get; init; }
    /// <summary>전압 mV</summary>
    public double? VoltageMillivolts { get; init; }
    /// <summary>현재 전류 μA</summary>
    public double? CurrentMicroamps { get; init; }
    /// <summary>평균 전류 μA</summary>
    public double? AverageCurrentMicroamps { get; init; }
    /// <summary>충전·방전 전력 mW</summary>
    public double? ChargeRateMilliwatts { get; init; }
    /// <summary>배터리 온도 °C</summary>
    public double? TemperatureCelsius { get; init; }
    /// <summary>전하량 μAh</summary>
    public long? ChargeCounterMicroampHours { get; init; }
    /// <summary>남은 에너지 mWh</summary>
    public double? RemainingEnergyMilliwattHours { get; init; }
    /// <summary>현재 완충 용량 mWh</summary>
    public double? FullChargeEnergyMilliwattHours { get; init; }
    /// <summary>설계 용량 mWh</summary>
    public double? DesignEnergyMilliwattHours { get; init; }
    /// <summary>배터리 기술·화학 종류</summary>
    public string? Technology { get; init; }
    /// <summary>플랫폼이 보고하는 상태·고장 종류</summary>
    public BatteryHealth? Health { get; init; }
    /// <summary>충전 사이클 수</summary>
    public long? CycleCount { get; init; }
}

public sealed record NetworkPathSnapshot : DeviceSnapshot
{
    /// <summary>로컬 연결 경로 상태</summary>
    public ConnectionState? ConnectionState { get; init; }
    /// <summary>경로에 사용되는 전송 수단 집합</summary>
    public ImmutableHashSet<NetworkTransport>? Transports { get; init; }
    /// <summary>사용량 제한·종량제 네트워크 여부</summary>
    public bool? Metered { get; init; }
    /// <summary>플랫폼이 비용이 큰 경로로 분류하는지 여부</summary>
    public bool? Expensive { get; init; }
    /// <summary>플랫폼의 제한된 데이터 모드 여부</summary>
    public bool? Constrained { get; init; }
    /// <summary>사용자의 데이터 절약 선호</summary>
    public bool? SaveData { get; init; }
    /// <summary>경로의 IPv4 지원 여부</summary>
    public bool? SupportsIpv4 { get; init; }
    /// <summary>경로의 IPv6 지원 여부</summary>
    public bool? SupportsIpv6 { get; init; }
    /// <summary>경로의 DNS 지원 여부</summary>
    public bool? SupportsDns { get; init; }
    /// <summary>OS가 보고하는 인터넷 검증 상태</summary>
    public bool? InternetValidated { get; init; }
    /// <summary>OS가 보고하는 captive portal 상태</summary>
    public bool? CaptivePortal { get; init; }
}

public sealed record NetworkPerformanceSnapshot : DeviceSnapshot
{
    /// <summary>하향 전송 속도 bit/s</summary>
    public double? DownlinkBps { get; init; }
    /// <summary>상향 전송 속도 bit/s</summary>
    public double? UplinkBps { get; init; }
    /// <summary>왕복 시간</summary>
    public TimeSpan? RoundTripTime { get; init; }
    /// <summary>플랫폼의 네트워크 성능 분류</summary>
    public EffectiveConnectionType? EffectiveType { get; init; }
    /// <summary>브라우저가 보고하는 온라인 상태</summary>
    public bool? BrowserOnline { get; init; }
}

public sealed record NetworkInterfaceSnapshot : DeviceSnapshot
{
    /// <summary>인터페이스 이름</summary>
    public string? Name { get; init; }
    /// <summary>인터페이스 종류</summary>
    public NetworkInterfaceType? InterfaceType { get; init; }
    /// <summary>인터페이스 동작 상태</summary>
    public NetworkOperationalState? OperationalState { get; init; }
    /// <summary>플랫폼이 허용해 공개하는 하드웨어 주소</summary>
    public string? HardwareAddress { get; init; }
    /// <summary>인터페이스 IP 주소 정보</summary>
    public ImmutableArray<IpAddressInfo>? IpAddresses { get; init; }
    /// <summary>DNS 서버 주소 목록</summary>
    public ImmutableArray<string>? DnsServers { get; init; }
    /// <summary>게이트웨이 주소 목록</summary>
    public ImmutableArray<string>? Gateways { get; init; }
    /// <summary>경로 정보 목록</summary>
    public ImmutableArray<NetworkRoute>? Routes { get; init; }
    /// <summary>MTU byte 크기</summary>
    public ulong? MtuBytes { get; init; }
}

public sealed record WifiConnectionSnapshot : DeviceSnapshot
{
    /// <summary>현재 연결 SSID</summary>
    public string? Ssid { get; init; }
    /// <summary>현재 연결 BSSID</summary>
    public string? Bssid { get; init; }
    /// <summary>현재 연결에서 선택된 인증 방식</summary>
    public WifiSecurity? Security { get; init; }
    /// <summary>수신 신호 세기 dBm</summary>
    public double? RssiDbm { get; init; }
    /// <summary>현재 연결 주파수 Hz</summary>
    public double? FrequencyHz { get; init; }
    /// <summary>수신 링크 속도 bit/s</summary>
    public double? ReceiveLinkSpeedBps { get; init; }
    /// <summary>송신 링크 속도 bit/s</summary>
    public double? TransmitLinkSpeedBps { get; init; }
}

public sealed record CellularSubscriptionSnapshot : DeviceSnapshot
{
    /// <summary>슬롯 인덱스</summary>
    public int? SlotIndex { get; init; }
    /// <summary>통신사 이름</summary>
    public string? CarrierName { get; init; }
    /// <summary>플랫폼이 보고하는 국가 코드</summary>
    public string? CountryCode { get; init; }
    /// <summary>MCC. 앞자리 0을 보존하는 문자열</summary>
    public string? MobileCountryCode { get; init; }
    /// <summary>MNC. 앞자리 0을 보존하는 문자열</summary>
    public string? MobileNetworkCode { get; init; }
    /// <summary>현재 데이터 연결의 무선 기술</summary>
    public RadioTechnology? RadioTechnology { get; init; }
    /// <summary>로밍 여부</summary>
    public bool? Roaming { get; init; }
}

public sealed record StorageVolumeSnapshot : DeviceSnapshot
{
    /// <summary>볼륨 이름</summary>
    public string? Name { get; init; }
    /// <summary>파일 시스템</summary>
    public string? FileSystem { get; init; }
    /// <summary>볼륨 전체 용량</summary>
    public ulong? TotalBytes { get; init; }
    /// <summary>볼륨의 빈 공간</summary>
    public ulong? FreeBytes { get; init; }
    /// <summary>현재 호출자가 사용할 수 있는 여유 공간</summary>
    public ulong? AvailableToCallerBytes { get; init; }
    /// <summary>할당량 등 호출자 제한을 반영한 전체 용량</summary>
    public ulong? TotalBytesForCaller { get; init; }
    /// <summary>읽기 전용 여부</summary>
    public bool? ReadOnly { get; init; }
    /// <summary>이동식 여부</summary>
    public bool? Removable { get; init; }
    /// <summary>암호화 여부</summary>
    public bool? Encrypted { get; init; }
    /// <summary>이름의 대소문자 구분 여부</summary>
    public bool? CaseSensitive { get; init; }
    /// <summary>플랫폼이 중요한 용도에 제공하는 가용량</summary>
    public ulong? AvailableForImportantUsageBytes { get; init; }
    /// <summary>플랫폼이 기회적 용도에 제공하는 가용량</summary>
    public ulong? AvailableForOpportunisticUsageBytes { get; init; }
    /// <summary>플랫폼이 할당 가능하다고 보고하는 용량</summary>
    public ulong? AllocatableBytes { get; init; }
}

public sealed record OriginStorageSnapshot : DeviceSnapshot
{
    /// <summary>origin 저장 한도</summary>
    public ulong? QuotaBytes { get; init; }
    /// <summary>origin 사용량</summary>
    public ulong? UsageBytes { get; init; }
    /// <summary>플랫폼이 공개하는 저장 유형별 사용량</summary>
    public ImmutableDictionary<StorageCategory, ulong>? UsageByCategory { get; init; }
    /// <summary>영구 저장 권한·상태</summary>
    public bool? Persistent { get; init; }
}

public sealed record AccelerometerSnapshot : DeviceSnapshot
{
    /// <summary>중력을 포함한 가속도</summary>
    public Vector3? Value { get; init; }
}

public sealed record LinearAccelerationSnapshot : DeviceSnapshot
{
    /// <summary>중력을 제외한 가속도</summary>
    public Vector3? Value { get; init; }
}

public sealed record GravitySnapshot : DeviceSnapshot
{
    /// <summary>중력 벡터</summary>
    public Vector3? Value { get; init; }
}

public sealed record GyroscopeSnapshot : DeviceSnapshot
{
    /// <summary>각속도</summary>
    public Vector3? Value { get; init; }
}

public sealed record MagnetometerSnapshot : DeviceSnapshot
{
    /// <summary>자기장</summary>
    public Vector3? Value { get; init; }
}

public sealed record RelativeOrientationSnapshot : DeviceSnapshot
{
    /// <summary>수집 세션의 상대 기준에 대한 자세</summary>
    public Quaternion? Value { get; init; }
}

public sealed record AbsoluteOrientationSnapshot : DeviceSnapshot
{
    /// <summary>동쪽·자기북·위쪽 기준에 대한 자세</summary>
    public Quaternion? Value { get; init; }
}

public sealed record IlluminanceSnapshot : DeviceSnapshot
{
    /// <summary>조도</summary>
    public double? Value { get; init; }
}

public sealed record PressureSnapshot : DeviceSnapshot
{
    /// <summary>기압</summary>
    public double? Value { get; init; }
}

public sealed record AmbientTemperatureSnapshot : DeviceSnapshot
{
    /// <summary>주변 온도</summary>
    public double? Value { get; init; }
}

public sealed record RelativeHumiditySnapshot : DeviceSnapshot
{
    /// <summary>상대 습도</summary>
    public double? Value { get; init; }
}

public sealed record ProximityNearSnapshot : DeviceSnapshot
{
    /// <summary>근접 상태</summary>
    public bool? Value { get; init; }
}

public sealed record ProximityDistanceSnapshot : DeviceSnapshot
{
    /// <summary>근접 대상까지의 거리</summary>
    public double? Value { get; init; }
}

public sealed record RelativeAltitudeSnapshot : DeviceSnapshot
{
    /// <summary>수집 세션의 기준점 대비 상대 고도</summary>
    public double? Value { get; init; }
}

public sealed record HingeAngleSnapshot : DeviceSnapshot
{
    /// <summary>힌지 각도</summary>
    public double? Value { get; init; }
}

public sealed record StepCountSinceBootSnapshot : DeviceSnapshot
{
    /// <summary>부팅 기준 누적 걸음 수</summary>
    public long? Value { get; init; }
}

public sealed record StepDetectedSnapshot : DeviceSnapshot
{
    /// <summary>걸음 발생. false 초기 이벤트는 없음</summary>
    public bool? Value { get; init; }
}

public sealed record SignificantMotionSnapshot : DeviceSnapshot
{
    /// <summary>큰 움직임 발생. false 초기 이벤트는 없음</summary>
    public bool? Value { get; init; }
}

public sealed record HumanPresenceSnapshot : DeviceSnapshot
{
    /// <summary>사람 존재 여부</summary>
    public bool? Value { get; init; }
}

public sealed record SensorDescription : DeviceSnapshot
{
    /// <summary>센서 종류</summary>
    public SensorKind? Kind { get; init; }
    /// <summary>센서 이름</summary>
    public string? Name { get; init; }
    /// <summary>제조사</summary>
    public string? Vendor { get; init; }
    /// <summary>플랫폼이 보고하는 센서 버전</summary>
    public string? Version { get; init; }
    /// <summary>원본 센서의 보고 모드</summary>
    public SensorReportingMode? ReportingMode { get; init; }
    /// <summary>지원되는 최소 수집 간격</summary>
    public TimeSpan? MinimumInterval { get; init; }
    /// <summary>지원되는 최대 수집 간격</summary>
    public TimeSpan? MaximumInterval { get; init; }
    /// <summary>해당 센서 측정 단위의 최대 범위</summary>
    public double? MaximumRange { get; init; }
    /// <summary>해당 센서 측정 단위의 분해능</summary>
    public double? Resolution { get; init; }
    /// <summary>플랫폼이 보고하는 전류 소비 mA</summary>
    public double? PowerMilliamps { get; init; }
    /// <summary>플랫폼이 공개하는 FIFO 샘플 수용량</summary>
    public int? FifoCapacity { get; init; }
}

public static class Entities
{
    public static Entity<DeviceInfoSnapshot> DeviceInfo { get; } = new(EntityKind.DeviceInfo, false, EntityMode.State);
    public static Entity<OsSnapshot> Os { get; } = new(EntityKind.Os, false, EntityMode.State);
    public static Entity<RuntimeSnapshot> Runtime { get; } = new(EntityKind.Runtime, false, EntityMode.State);
    public static Entity<CpuSnapshot> Cpu { get; } = new(EntityKind.Cpu, false, EntityMode.State);
    public static Entity<CpuCoreSnapshot> CpuCore { get; } = new(EntityKind.CpuCore, true, EntityMode.State);
    public static Entity<RamSnapshot> Ram { get; } = new(EntityKind.Ram, false, EntityMode.State);
    public static Entity<ProcessMemorySnapshot> ProcessMemory { get; } = new(EntityKind.ProcessMemory, false, EntityMode.State);
    public static Entity<LocaleSnapshot> Locale { get; } = new(EntityKind.Locale, false, EntityMode.State);
    public static Entity<TimeZoneSnapshot> TimeZone { get; } = new(EntityKind.TimeZone, false, EntityMode.State);
    public static Entity<AndroidBuildSnapshot> AndroidBuild { get; } = new(EntityKind.AndroidBuild, false, EntityMode.State);
    public static Entity<AndroidIdentitySnapshot> AndroidIdentity { get; } = new(EntityKind.AndroidIdentity, false, EntityMode.State);
    public static Entity<AppleVendorIdentitySnapshot> AppleVendorIdentity { get; } = new(EntityKind.AppleVendorIdentity, false, EntityMode.State);
    public static Entity<WindowsPublisherIdentitySnapshot> WindowsPublisherIdentity { get; } = new(EntityKind.WindowsPublisherIdentity, false, EntityMode.State);
    public static Entity<MacPlatformIdentitySnapshot> MacPlatformIdentity { get; } = new(EntityKind.MacPlatformIdentity, false, EntityMode.State);
    public static Entity<HardwareSerialSnapshot> HardwareSerial { get; } = new(EntityKind.HardwareSerial, false, EntityMode.State);
    public static Entity<TelephonyIdentitySnapshot> TelephonyIdentity { get; } = new(EntityKind.TelephonyIdentity, true, EntityMode.State);
    public static Entity<DisplaySnapshot> Display { get; } = new(EntityKind.Display, true, EntityMode.State);
    public static Entity<ViewportSnapshot> Viewport { get; } = new(EntityKind.Viewport, true, EntityMode.State);
    public static Entity<PowerSnapshot> Power { get; } = new(EntityKind.Power, false, EntityMode.State);
    public static Entity<BatterySnapshot> Battery { get; } = new(EntityKind.Battery, true, EntityMode.State);
    public static Entity<NetworkPathSnapshot> NetworkPath { get; } = new(EntityKind.NetworkPath, false, EntityMode.State);
    public static Entity<NetworkPerformanceSnapshot> NetworkPerformance { get; } = new(EntityKind.NetworkPerformance, false, EntityMode.State);
    public static Entity<NetworkInterfaceSnapshot> NetworkInterface { get; } = new(EntityKind.NetworkInterface, true, EntityMode.State);
    public static Entity<WifiConnectionSnapshot> WifiConnection { get; } = new(EntityKind.WifiConnection, true, EntityMode.State);
    public static Entity<CellularSubscriptionSnapshot> CellularSubscription { get; } = new(EntityKind.CellularSubscription, true, EntityMode.State);
    public static Entity<StorageVolumeSnapshot> StorageVolume { get; } = new(EntityKind.StorageVolume, true, EntityMode.State);
    public static Entity<OriginStorageSnapshot> OriginStorage { get; } = new(EntityKind.OriginStorage, false, EntityMode.State);
    public static Entity<AccelerometerSnapshot> Accelerometer { get; } = new(EntityKind.Accelerometer, true, EntityMode.Sample);
    public static Entity<LinearAccelerationSnapshot> LinearAcceleration { get; } = new(EntityKind.LinearAcceleration, true, EntityMode.Sample);
    public static Entity<GravitySnapshot> Gravity { get; } = new(EntityKind.Gravity, true, EntityMode.Sample);
    public static Entity<GyroscopeSnapshot> Gyroscope { get; } = new(EntityKind.Gyroscope, true, EntityMode.Sample);
    public static Entity<MagnetometerSnapshot> Magnetometer { get; } = new(EntityKind.Magnetometer, true, EntityMode.Sample);
    public static Entity<RelativeOrientationSnapshot> RelativeOrientation { get; } = new(EntityKind.RelativeOrientation, true, EntityMode.Sample);
    public static Entity<AbsoluteOrientationSnapshot> AbsoluteOrientation { get; } = new(EntityKind.AbsoluteOrientation, true, EntityMode.Sample);
    public static Entity<IlluminanceSnapshot> Illuminance { get; } = new(EntityKind.Illuminance, true, EntityMode.Sample);
    public static Entity<PressureSnapshot> Pressure { get; } = new(EntityKind.Pressure, true, EntityMode.Sample);
    public static Entity<AmbientTemperatureSnapshot> AmbientTemperature { get; } = new(EntityKind.AmbientTemperature, true, EntityMode.Sample);
    public static Entity<RelativeHumiditySnapshot> RelativeHumidity { get; } = new(EntityKind.RelativeHumidity, true, EntityMode.Sample);
    public static Entity<ProximityNearSnapshot> ProximityNear { get; } = new(EntityKind.ProximityNear, true, EntityMode.Sample);
    public static Entity<ProximityDistanceSnapshot> ProximityDistance { get; } = new(EntityKind.ProximityDistance, true, EntityMode.Sample);
    public static Entity<RelativeAltitudeSnapshot> RelativeAltitude { get; } = new(EntityKind.RelativeAltitude, true, EntityMode.Sample);
    public static Entity<HingeAngleSnapshot> HingeAngle { get; } = new(EntityKind.HingeAngle, true, EntityMode.Sample);
    public static Entity<StepCountSinceBootSnapshot> StepCountSinceBoot { get; } = new(EntityKind.StepCountSinceBoot, true, EntityMode.Sample);
    public static Entity<StepDetectedSnapshot> StepDetected { get; } = new(EntityKind.StepDetected, true, EntityMode.Event);
    public static Entity<SignificantMotionSnapshot> SignificantMotion { get; } = new(EntityKind.SignificantMotion, true, EntityMode.Event);
    public static Entity<HumanPresenceSnapshot> HumanPresence { get; } = new(EntityKind.HumanPresence, true, EntityMode.Sample);
}

[System.Text.Json.Serialization.JsonSerializable(typeof(DeviceInfoSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(OsSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(RuntimeSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(CpuSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(CpuCoreSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(RamSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(ProcessMemorySnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(LocaleSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(TimeZoneSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(AndroidBuildSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(AndroidIdentitySnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(AppleVendorIdentitySnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(WindowsPublisherIdentitySnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(MacPlatformIdentitySnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(HardwareSerialSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(TelephonyIdentitySnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(DisplaySnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(ViewportSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(PowerSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(BatterySnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(NetworkPathSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(NetworkPerformanceSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(NetworkInterfaceSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(WifiConnectionSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(CellularSubscriptionSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(StorageVolumeSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(OriginStorageSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(AccelerometerSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(LinearAccelerationSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(GravitySnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(GyroscopeSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(MagnetometerSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(RelativeOrientationSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(AbsoluteOrientationSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(IlluminanceSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(PressureSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(AmbientTemperatureSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(RelativeHumiditySnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(ProximityNearSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(ProximityDistanceSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(RelativeAltitudeSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(HingeAngleSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(StepCountSinceBootSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(StepDetectedSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(SignificantMotionSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(HumanPresenceSnapshot))]
[System.Text.Json.Serialization.JsonSerializable(typeof(SensorDescription))]
internal partial class ModelJsonContext : System.Text.Json.Serialization.JsonSerializerContext { }

internal static partial class SnapshotRules
{
    internal static DeviceSnapshot Normalize(DeviceSnapshot value) => value switch {
        DeviceInfoSnapshot snapshot => snapshot with {FormFactor = SnapshotRules.KnownEnum(snapshot.FormFactor)},
        OsSnapshot snapshot => snapshot with {Family = SnapshotRules.KnownEnum(snapshot.Family)},
        RuntimeSnapshot snapshot => snapshot with {HostArchitecture = SnapshotRules.KnownEnum(snapshot.HostArchitecture), ProcessArchitecture = SnapshotRules.KnownEnum(snapshot.ProcessArchitecture), SupportedAbis = SnapshotRules.EnumSet(snapshot.SupportedAbis)},
        CpuSnapshot snapshot => snapshot with {},
        CpuCoreSnapshot snapshot => snapshot with {CurrentClockHz = SnapshotRules.Finite(snapshot.CurrentClockHz), MaximumClockHz = SnapshotRules.Finite(snapshot.MaximumClockHz)},
        RamSnapshot snapshot => snapshot with {},
        ProcessMemorySnapshot snapshot => snapshot with {},
        LocaleSnapshot snapshot => snapshot with {PreferredLanguageTags = SnapshotRules.Strings(snapshot.PreferredLanguageTags), SystemLanguageTags = SnapshotRules.Strings(snapshot.SystemLanguageTags), AppLanguageTags = SnapshotRules.Strings(snapshot.AppLanguageTags), HourCycle = SnapshotRules.KnownEnum(snapshot.HourCycle), FirstWeekday = SnapshotRules.KnownEnum(snapshot.FirstWeekday), MeasurementSystem = SnapshotRules.KnownEnum(snapshot.MeasurementSystem)},
        TimeZoneSnapshot snapshot => snapshot with {},
        AndroidBuildSnapshot snapshot => snapshot with {BuildTags = SnapshotRules.Strings(snapshot.BuildTags)},
        AndroidIdentitySnapshot snapshot => snapshot with {},
        AppleVendorIdentitySnapshot snapshot => snapshot with {},
        WindowsPublisherIdentitySnapshot snapshot => snapshot with {Source = SnapshotRules.KnownEnum(snapshot.Source)},
        MacPlatformIdentitySnapshot snapshot => snapshot with {},
        HardwareSerialSnapshot snapshot => snapshot with {},
        TelephonyIdentitySnapshot snapshot => snapshot with {},
        DisplaySnapshot snapshot => snapshot with {State = SnapshotRules.KnownEnum(snapshot.State), LogicalBounds = SnapshotRules.Rectangle(snapshot.LogicalBounds), WorkAreaBounds = SnapshotRules.Rectangle(snapshot.WorkAreaBounds), PhysicalSizeMillimeters = SnapshotRules.Size(snapshot.PhysicalSizeMillimeters), Orientation = SnapshotRules.KnownEnum(snapshot.Orientation), RotationDegrees = SnapshotRules.Finite(snapshot.RotationDegrees), ScaleFactor = SnapshotRules.Finite(snapshot.ScaleFactor), DensityDpi = SnapshotRules.Finite(snapshot.DensityDpi), SupportedModes = SnapshotRules.DisplayModes(snapshot.SupportedModes), MaximumRefreshRateHz = SnapshotRules.Finite(snapshot.MaximumRefreshRateHz), ColorGamut = SnapshotRules.KnownEnum(snapshot.ColorGamut), HdrFormats = SnapshotRules.EnumSet(snapshot.HdrFormats), Brightness = SnapshotRules.Ratio(snapshot.Brightness)},
        ViewportSnapshot snapshot => snapshot with {Size = SnapshotRules.Size(snapshot.Size), VisualViewportSize = SnapshotRules.Size(snapshot.VisualViewportSize), VisualViewportScale = SnapshotRules.Finite(snapshot.VisualViewportScale), SafeAreaInsets = SnapshotRules.Edges(snapshot.SafeAreaInsets), TextScaleFactor = SnapshotRules.Finite(snapshot.TextScaleFactor)},
        PowerSnapshot snapshot => snapshot with {PowerSource = SnapshotRules.KnownEnum(snapshot.PowerSource), ThermalState = SnapshotRules.Thermal(snapshot.ThermalState)},
        BatterySnapshot snapshot => snapshot with {Level = SnapshotRules.Ratio(snapshot.Level), State = SnapshotRules.KnownEnum(snapshot.State), TimeToFull = SnapshotRules.Duration(snapshot.TimeToFull), TimeToEmpty = SnapshotRules.Duration(snapshot.TimeToEmpty), VoltageMillivolts = SnapshotRules.Finite(snapshot.VoltageMillivolts), CurrentMicroamps = SnapshotRules.Finite(snapshot.CurrentMicroamps), AverageCurrentMicroamps = SnapshotRules.Finite(snapshot.AverageCurrentMicroamps), ChargeRateMilliwatts = SnapshotRules.Finite(snapshot.ChargeRateMilliwatts), TemperatureCelsius = SnapshotRules.Finite(snapshot.TemperatureCelsius), RemainingEnergyMilliwattHours = SnapshotRules.Finite(snapshot.RemainingEnergyMilliwattHours), FullChargeEnergyMilliwattHours = SnapshotRules.Finite(snapshot.FullChargeEnergyMilliwattHours), DesignEnergyMilliwattHours = SnapshotRules.Finite(snapshot.DesignEnergyMilliwattHours), Health = SnapshotRules.KnownEnum(snapshot.Health)},
        NetworkPathSnapshot snapshot => snapshot with {ConnectionState = SnapshotRules.KnownEnum(snapshot.ConnectionState), Transports = SnapshotRules.EnumSet(snapshot.Transports)},
        NetworkPerformanceSnapshot snapshot => snapshot with {DownlinkBps = SnapshotRules.Finite(snapshot.DownlinkBps), UplinkBps = SnapshotRules.Finite(snapshot.UplinkBps), RoundTripTime = SnapshotRules.Duration(snapshot.RoundTripTime), EffectiveType = SnapshotRules.KnownEnum(snapshot.EffectiveType)},
        NetworkInterfaceSnapshot snapshot => snapshot with {InterfaceType = SnapshotRules.KnownEnum(snapshot.InterfaceType), OperationalState = SnapshotRules.KnownEnum(snapshot.OperationalState), IpAddresses = SnapshotRules.Addresses(snapshot.IpAddresses), DnsServers = SnapshotRules.Strings(snapshot.DnsServers), Gateways = SnapshotRules.Strings(snapshot.Gateways), Routes = SnapshotRules.Routes(snapshot.Routes)},
        WifiConnectionSnapshot snapshot => snapshot with {Security = SnapshotRules.KnownEnum(snapshot.Security), RssiDbm = SnapshotRules.Finite(snapshot.RssiDbm), FrequencyHz = SnapshotRules.Finite(snapshot.FrequencyHz), ReceiveLinkSpeedBps = SnapshotRules.Finite(snapshot.ReceiveLinkSpeedBps), TransmitLinkSpeedBps = SnapshotRules.Finite(snapshot.TransmitLinkSpeedBps)},
        CellularSubscriptionSnapshot snapshot => snapshot with {RadioTechnology = SnapshotRules.KnownEnum(snapshot.RadioTechnology)},
        StorageVolumeSnapshot snapshot => snapshot with {},
        OriginStorageSnapshot snapshot => snapshot with {UsageByCategory = SnapshotRules.EnumMap(snapshot.UsageByCategory)},
        AccelerometerSnapshot snapshot => snapshot with {Value = SnapshotRules.Vector(snapshot.Value)},
        LinearAccelerationSnapshot snapshot => snapshot with {Value = SnapshotRules.Vector(snapshot.Value)},
        GravitySnapshot snapshot => snapshot with {Value = SnapshotRules.Vector(snapshot.Value)},
        GyroscopeSnapshot snapshot => snapshot with {Value = SnapshotRules.Vector(snapshot.Value)},
        MagnetometerSnapshot snapshot => snapshot with {Value = SnapshotRules.Vector(snapshot.Value)},
        RelativeOrientationSnapshot snapshot => snapshot with {Value = SnapshotRules.Rotation(snapshot.Value)},
        AbsoluteOrientationSnapshot snapshot => snapshot with {Value = SnapshotRules.Rotation(snapshot.Value)},
        IlluminanceSnapshot snapshot => snapshot with {Value = SnapshotRules.Finite(snapshot.Value)},
        PressureSnapshot snapshot => snapshot with {Value = SnapshotRules.Finite(snapshot.Value)},
        AmbientTemperatureSnapshot snapshot => snapshot with {Value = SnapshotRules.Finite(snapshot.Value)},
        RelativeHumiditySnapshot snapshot => snapshot with {Value = SnapshotRules.Ratio(snapshot.Value)},
        ProximityNearSnapshot snapshot => snapshot with {},
        ProximityDistanceSnapshot snapshot => snapshot with {Value = SnapshotRules.Finite(snapshot.Value)},
        RelativeAltitudeSnapshot snapshot => snapshot with {Value = SnapshotRules.Finite(snapshot.Value)},
        HingeAngleSnapshot snapshot => snapshot with {Value = SnapshotRules.Finite(snapshot.Value)},
        StepCountSinceBootSnapshot snapshot => snapshot with {},
        StepDetectedSnapshot snapshot => snapshot with {},
        SignificantMotionSnapshot snapshot => snapshot with {},
        HumanPresenceSnapshot snapshot => snapshot with {},
        SensorDescription snapshot => snapshot with {Kind = SnapshotRules.KnownEnum(snapshot.Kind), ReportingMode = SnapshotRules.KnownEnum(snapshot.ReportingMode), MinimumInterval = SnapshotRules.Duration(snapshot.MinimumInterval), MaximumInterval = SnapshotRules.Duration(snapshot.MaximumInterval), MaximumRange = SnapshotRules.Finite(snapshot.MaximumRange), Resolution = SnapshotRules.Finite(snapshot.Resolution), PowerMilliamps = SnapshotRules.Finite(snapshot.PowerMilliamps)},
        _ => throw new DeviceReadoutException(ErrorCode.ReadFailed, "Unrecognized snapshot type.")
    };
}
