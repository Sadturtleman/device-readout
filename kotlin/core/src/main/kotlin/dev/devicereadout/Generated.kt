// Generated from the shared DeviceReadout schema.
package dev.devicereadout

import java.time.Instant
import kotlin.time.Duration

enum class FormFactor { Phone, Tablet, Laptop, Desktop, Television, Watch, Automotive, Headset }
enum class OsFamily { Android, IOS, IPadOS, Windows, MacOS, Linux, ChromeOS }
enum class Architecture { X86, X64, Arm32, Arm64, RiscV32, RiscV64, Wasm32, Wasm64 }
enum class Abi { ArmeabiV7a, Arm64V8a, X86, X86_64 }
enum class HourCycle { H11, H12, H23, H24 }
enum class Weekday { Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday }
enum class MeasurementSystem { Metric, US, UK }
enum class WindowsIdentitySource { Tpm, Uefi, Registry }
enum class DisplayState { On, Off, Doze, DozeSuspended, OnSuspended }
enum class DisplayOrientation { PortraitPrimary, PortraitSecondary, LandscapePrimary, LandscapeSecondary }
enum class ColorGamut { Srgb, DisplayP3, Rec2020 }
enum class HdrFormat { Hdr10, Hdr10Plus, DolbyVision, Hlg }
enum class PowerSource { Battery, External, Ups }
enum class AndroidThermalState : ThermalState { None, Light, Moderate, Severe, Critical, Emergency, Shutdown }
enum class AppleThermalState : ThermalState { Nominal, Fair, Serious, Critical }
enum class BatteryState { Charging, Discharging, Full, NotCharging, Idle }
enum class BatteryHealth { Good, Overheated, Cold, Dead, OverVoltage, UnspecifiedFailure }
enum class ConnectionState { Connected, Disconnected, Connecting, Disconnecting, Suspended, ConnectionRequired }
enum class NetworkTransport { Wifi, Cellular, Ethernet, Bluetooth, Vpn, Usb, WifiAware, Lowpan, Thread, Satellite }
enum class EffectiveConnectionType { Slow2G, Type2G, Type3G, Type4G }
enum class NetworkInterfaceType { Ethernet, Wifi, Cellular, Bluetooth, Loopback, Tunnel, Ppp, Bridge }
enum class NetworkOperationalState { Up, Down, Testing, Dormant, NotPresent, LowerLayerDown }
enum class WifiSecurity { Open, Wep, Psk, Eap, Sae, Owe, WapiPsk, WapiCert, EapWpa3Enterprise, EapWpa3Enterprise192Bit, PasspointR1R2, PasspointR3, Dpp }
enum class RadioTechnology { Gsm, Gprs, Edge, Cdma, Cdma1x, Evdo0, EvdoA, EvdoB, Ehrpd, Umts, Hsdpa, Hsupa, Hspa, HspaPlus, Iden, TdScdma, Lte, LteCa, Nr, NrNsa, NrSa, Iwlan }
enum class StorageCategory { IndexedDB, Caches, ServiceWorker, FileSystem, LocalStorage, SessionStorage }
enum class SensorReportingMode { Continuous, OnChange, OneShot, SpecialTrigger }
enum class SensorKind { Accelerometer, LinearAcceleration, Gravity, Gyroscope, Magnetometer, RelativeOrientation, AbsoluteOrientation, Illuminance, Pressure, AmbientTemperature, RelativeHumidity, ProximityNear, ProximityDistance, RelativeAltitude, HingeAngle, StepCountSinceBoot, StepDetected, SignificantMotion, HumanPresence }
enum class EntityKind { DeviceInfo, Os, Runtime, Cpu, CpuCore, Ram, ProcessMemory, Locale, TimeZone, AndroidBuild, AndroidIdentity, AppleVendorIdentity, WindowsPublisherIdentity, MacPlatformIdentity, HardwareSerial, TelephonyIdentity, Display, Viewport, Power, Battery, NetworkPath, NetworkPerformance, NetworkInterface, WifiConnection, CellularSubscription, StorageVolume, OriginStorage, Accelerometer, LinearAcceleration, Gravity, Gyroscope, Magnetometer, RelativeOrientation, AbsoluteOrientation, Illuminance, Pressure, AmbientTemperature, RelativeHumidity, ProximityNear, ProximityDistance, RelativeAltitude, HingeAngle, StepCountSinceBoot, StepDetected, SignificantMotion, HumanPresence }
sealed interface ThermalState

data class DeviceInfoSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 제조사 */
    val manufacturer: String? = null,
    /** 브랜드 */
    val brand: String? = null,
    /** 플랫폼의 모델 코드 */
    val modelCode: String? = null,
    /** 사용자에게 표시할 모델 이름 */
    val modelName: String? = null,
    /** OS가 공개하는 기기 이름 */
    val deviceName: String? = null,
    /** 휴대전화·태블릿·노트북 등 기기 형태 */
    val formFactor: FormFactor? = null,
    /** 제품 식별 이름 */
    val product: String? = null,
    /** 보드 식별 이름 */
    val board: String? = null,
) : DeviceSnapshot
val DeviceInfoEntity = Entity<DeviceInfoSnapshot>(EntityKind.DeviceInfo, false, EntityMode.State, DeviceInfoSnapshot::class.java)

data class OsSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 운영체제 계열 */
    val family: OsFamily? = null,
    /** 운영체제 이름 */
    val name: String? = null,
    /** 운영체제 버전 */
    val version: String? = null,
    /** 운영체제 빌드 */
    val build: String? = null,
    /** 커널 이름 */
    val kernelName: String? = null,
    /** 커널 버전 */
    val kernelVersion: String? = null,
) : DeviceSnapshot
val OsEntity = Entity<OsSnapshot>(EntityKind.Os, false, EntityMode.State, OsSnapshot::class.java)

data class RuntimeSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 호스트 시스템 아키텍처 */
    val hostArchitecture: Architecture? = null,
    /** 현재 프로세스 아키텍처 */
    val processArchitecture: Architecture? = null,
    /** 현재 프로세스 비트 수 */
    val processBitness: Int? = null,
    /** 플랫폼이 공개하는 지원 ABI 집합 */
    val supportedAbis: Set<Abi>? = null,
) : DeviceSnapshot
val RuntimeEntity = Entity<RuntimeSnapshot>(EntityKind.Runtime, false, EntityMode.State, RuntimeSnapshot::class.java)

data class CpuSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** CPU 모델 */
    val model: String? = null,
    /** CPU 제조사 */
    val manufacturer: String? = null,
    /** SoC 모델 */
    val socModel: String? = null,
    /** SoC 제조사 */
    val socManufacturer: String? = null,
    /** 전체 논리 프로세서 수 */
    val logicalProcessorCount: Int? = null,
    /** 현재 실행 환경에 제공되는 논리 프로세서 수 */
    val availableLogicalProcessorCount: Int? = null,
    /** 물리 코어 수 */
    val physicalCoreCount: Int? = null,
    /** 프로세서 패키지 수 */
    val processorPackageCount: Int? = null,
) : DeviceSnapshot
val CpuEntity = Entity<CpuSnapshot>(EntityKind.Cpu, false, EntityMode.State, CpuSnapshot::class.java)

data class CpuCoreSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 논리 프로세서 인덱스 */
    val logicalIndex: Int? = null,
    /** 소속 물리 코어 인덱스 */
    val coreIndex: Int? = null,
    /** 소속 프로세서 패키지 인덱스 */
    val packageIndex: Int? = null,
    /** OS에서 사용 가능한 온라인 상태 */
    val online: Boolean? = null,
    /** 현재 클록 주파수 */
    val currentClockHz: Double? = null,
    /** 플랫폼이 보고하는 최대 클록 주파수 */
    val maximumClockHz: Double? = null,
) : DeviceSnapshot
val CpuCoreEntity = Entity<CpuCoreSnapshot>(EntityKind.CpuCore, true, EntityMode.State, CpuCoreSnapshot::class.java)

data class RamSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 설치된 물리 RAM 용량 */
    val physicalBytes: ULong? = null,
    /** 커널이 접근 가능한 RAM 용량 */
    val kernelAccessibleBytes: ULong? = null,
    /** 플랫폼이 외부에 공개하는 표기용 RAM 용량 */
    val advertisedBytes: ULong? = null,
    /** OS 정의상 사용 가능한 메모리 */
    val availableBytes: ULong? = null,
    /** OS 정의상 비어 있는 메모리 */
    val freeBytes: ULong? = null,
    /** OS가 보고하는 메모리 부족 상태 */
    val lowMemory: Boolean? = null,
    /** OS가 공개하는 메모리 부족 기준 용량 */
    val lowMemoryThresholdBytes: ULong? = null,
) : DeviceSnapshot
val RamEntity = Entity<RamSnapshot>(EntityKind.Ram, false, EntityMode.State, RamSnapshot::class.java)

data class ProcessMemorySnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 현재 앱이 추가로 할당할 수 있다고 플랫폼이 보고하는 메모리 */
    val allocationRemainingBytes: ULong? = null,
) : DeviceSnapshot
val ProcessMemoryEntity = Entity<ProcessMemorySnapshot>(EntityKind.ProcessMemory, false, EntityMode.State, ProcessMemorySnapshot::class.java)

data class LocaleSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 현재 유효한 언어 태그 */
    val currentLanguageTag: String? = null,
    /** 선호 언어 태그. 원래 우선순위 보존 */
    val preferredLanguageTags: List<String>? = null,
    /** 시스템 언어 태그 목록 */
    val systemLanguageTags: List<String>? = null,
    /** 앱에 적용된 언어 태그 목록 */
    val appLanguageTags: List<String>? = null,
    /** 로케일 지역 코드 */
    val regionCode: String? = null,
    /** 문자 체계 코드 */
    val scriptCode: String? = null,
    /** 달력 체계 식별자 */
    val calendar: String? = null,
    /** 숫자 표기 체계 식별자 */
    val numberingSystem: String? = null,
    /** 시간 표기 주기 */
    val hourCycle: HourCycle? = null,
    /** 한 주의 첫 요일 */
    val firstWeekday: Weekday? = null,
    /** 도량형 체계 */
    val measurementSystem: MeasurementSystem? = null,
) : DeviceSnapshot
val LocaleEntity = Entity<LocaleSnapshot>(EntityKind.Locale, false, EntityMode.State, LocaleSnapshot::class.java)

data class TimeZoneSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** IANA 시간대 식별자 */
    val ianaId: String? = null,
    /** Windows 시간대 식별자 */
    val windowsId: String? = null,
    /** 수집 시점의 UTC 오프셋 초 */
    val utcOffsetSeconds: Int? = null,
    /** 수집 시점의 서머타임 적용 여부 */
    val daylightSavingTime: Boolean? = null,
) : DeviceSnapshot
val TimeZoneEntity = Entity<TimeZoneSnapshot>(EntityKind.TimeZone, false, EntityMode.State, TimeZoneSnapshot::class.java)

data class AndroidBuildSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** Android API 수준 */
    val apiLevel: Int? = null,
    /** 플랫폼이 공개하는 보안 패치 날짜 */
    val securityPatch: String? = null,
    /** 빌드 ID */
    val buildId: String? = null,
    /** 표시용 빌드 문자열 */
    val buildDisplay: String? = null,
    /** OS 빌드를 식별하는 fingerprint */
    val buildFingerprint: String? = null,
    /** 빌드 유형 */
    val buildType: String? = null,
    /** 빌드 태그 */
    val buildTags: List<String>? = null,
    /** 부트로더 버전 */
    val bootloaderVersion: String? = null,
) : DeviceSnapshot
val AndroidBuildEntity = Entity<AndroidBuildSnapshot>(EntityKind.AndroidBuild, false, EntityMode.State, AndroidBuildSnapshot::class.java)

data class AndroidIdentitySnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 플랫폼이 제공하는 ANDROID_ID */
    val androidId: String? = null,
) : DeviceSnapshot
val AndroidIdentityEntity = Entity<AndroidIdentitySnapshot>(EntityKind.AndroidIdentity, false, EntityMode.State, AndroidIdentitySnapshot::class.java)

data class AppleVendorIdentitySnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** vendor 범위의 식별자 */
    val vendorId: String? = null,
) : DeviceSnapshot
val AppleVendorIdentityEntity = Entity<AppleVendorIdentitySnapshot>(EntityKind.AppleVendorIdentity, false, EntityMode.State, AppleVendorIdentitySnapshot::class.java)

data class WindowsPublisherIdentitySnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** publisher 범위의 시스템 식별자 */
    val publisherId: String? = null,
    /** 식별자 생성에 사용된 플랫폼 소스 */
    val source: WindowsIdentitySource? = null,
) : DeviceSnapshot
val WindowsPublisherIdentityEntity = Entity<WindowsPublisherIdentitySnapshot>(EntityKind.WindowsPublisherIdentity, false, EntityMode.State, WindowsPublisherIdentitySnapshot::class.java)

data class MacPlatformIdentitySnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 플랫폼 UUID */
    val platformUuid: String? = null,
) : DeviceSnapshot
val MacPlatformIdentityEntity = Entity<MacPlatformIdentitySnapshot>(EntityKind.MacPlatformIdentity, false, EntityMode.State, MacPlatformIdentitySnapshot::class.java)

data class HardwareSerialSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 플랫폼이 허용해 공개하는 하드웨어 일련번호 */
    val serial: String? = null,
) : DeviceSnapshot
val HardwareSerialEntity = Entity<HardwareSerialSnapshot>(EntityKind.HardwareSerial, false, EntityMode.State, HardwareSerialSnapshot::class.java)

data class TelephonyIdentitySnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 접근이 허용된 IMEI */
    val imei: String? = null,
    /** 접근이 허용된 MEID */
    val meid: String? = null,
) : DeviceSnapshot
val TelephonyIdentityEntity = Entity<TelephonyIdentitySnapshot>(EntityKind.TelephonyIdentity, true, EntityMode.State, TelephonyIdentitySnapshot::class.java)

data class DisplaySnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 화면 표시 이름 */
    val label: String? = null,
    /** 기본 화면 여부 */
    val primary: Boolean? = null,
    /** 내장 화면 여부 */
    val internal: Boolean? = null,
    /** 화면의 전원·표시 상태 */
    val state: DisplayState? = null,
    /** 화면의 논리 좌표 영역 */
    val logicalBounds: Rect? = null,
    /** 사용 가능한 작업 영역 */
    val workAreaBounds: Rect? = null,
    /** 픽셀 크기 */
    val pixelSize: Size<Int>? = null,
    /** 물리 크기 mm */
    val physicalSizeMillimeters: Size<Double>? = null,
    /** 화면 방향 */
    val orientation: DisplayOrientation? = null,
    /** 기준 방향에 대한 회전 각도 */
    val rotationDegrees: Double? = null,
    /** 논리 단위와 픽셀 사이 배율 */
    val scaleFactor: Double? = null,
    /** 인치당 픽셀 밀도 */
    val densityDpi: Double? = null,
    /** 현재 화면 모드 */
    val currentMode: DisplayMode? = null,
    /** 지원 화면 모드 목록 */
    val supportedModes: List<DisplayMode>? = null,
    /** 플랫폼이 공개하는 최대 주사율 */
    val maximumRefreshRateHz: Double? = null,
    /** 플랫폼이 보고하는 색 깊이 */
    val colorDepthBits: Int? = null,
    /** 플랫폼이 보고하는 화면 색역 */
    val colorGamut: ColorGamut? = null,
    /** 지원 HDR 형식 집합 */
    val hdrFormats: Set<HdrFormat>? = null,
    /** 밝기 0–1 */
    val brightness: Double? = null,
) : DeviceSnapshot
val DisplayEntity = Entity<DisplaySnapshot>(EntityKind.Display, true, EntityMode.State, DisplaySnapshot::class.java)

data class ViewportSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 레이아웃 뷰포트 크기 */
    val size: Size<Double>? = null,
    /** 현재 보이는 뷰포트 크기 */
    val visualViewportSize: Size<Double>? = null,
    /** 시각 뷰포트 확대 배율 */
    val visualViewportScale: Double? = null,
    /** 안전 영역 여백 */
    val safeAreaInsets: Insets? = null,
    /** 텍스트 확대 배율 */
    val textScaleFactor: Double? = null,
) : DeviceSnapshot
val ViewportEntity = Entity<ViewportSnapshot>(EntityKind.Viewport, true, EntityMode.State, ViewportSnapshot::class.java)

data class PowerSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 전원 공급원 */
    val powerSource: PowerSource? = null,
    /** 절전 모드 적용 여부 */
    val powerSaveMode: Boolean? = null,
    /** 플랫폼별 열 상태 타입의 합집합 */
    val thermalState: ThermalState? = null,
) : DeviceSnapshot
val PowerEntity = Entity<PowerSnapshot>(EntityKind.Power, false, EntityMode.State, PowerSnapshot::class.java)

data class BatterySnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 배터리 존재 여부 */
    val present: Boolean? = null,
    /** 충전 잔량 비율 0–1 */
    val level: Double? = null,
    /** 충전 중 여부 */
    val charging: Boolean? = null,
    /** 충전·방전 등 상태 */
    val state: BatteryState? = null,
    /** 완충까지 남은 시간 */
    val timeToFull: Duration? = null,
    /** 소진까지 남은 시간 */
    val timeToEmpty: Duration? = null,
    /** 전압 mV */
    val voltageMillivolts: Double? = null,
    /** 현재 전류 μA */
    val currentMicroamps: Double? = null,
    /** 평균 전류 μA */
    val averageCurrentMicroamps: Double? = null,
    /** 충전·방전 전력 mW */
    val chargeRateMilliwatts: Double? = null,
    /** 배터리 온도 °C */
    val temperatureCelsius: Double? = null,
    /** 전하량 μAh */
    val chargeCounterMicroampHours: Long? = null,
    /** 남은 에너지 mWh */
    val remainingEnergyMilliwattHours: Double? = null,
    /** 현재 완충 용량 mWh */
    val fullChargeEnergyMilliwattHours: Double? = null,
    /** 설계 용량 mWh */
    val designEnergyMilliwattHours: Double? = null,
    /** 배터리 기술·화학 종류 */
    val technology: String? = null,
    /** 플랫폼이 보고하는 상태·고장 종류 */
    val health: BatteryHealth? = null,
    /** 충전 사이클 수 */
    val cycleCount: Long? = null,
) : DeviceSnapshot
val BatteryEntity = Entity<BatterySnapshot>(EntityKind.Battery, true, EntityMode.State, BatterySnapshot::class.java)

data class NetworkPathSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 로컬 연결 경로 상태 */
    val connectionState: ConnectionState? = null,
    /** 경로에 사용되는 전송 수단 집합 */
    val transports: Set<NetworkTransport>? = null,
    /** 사용량 제한·종량제 네트워크 여부 */
    val metered: Boolean? = null,
    /** 플랫폼이 비용이 큰 경로로 분류하는지 여부 */
    val expensive: Boolean? = null,
    /** 플랫폼의 제한된 데이터 모드 여부 */
    val constrained: Boolean? = null,
    /** 사용자의 데이터 절약 선호 */
    val saveData: Boolean? = null,
    /** 경로의 IPv4 지원 여부 */
    val supportsIpv4: Boolean? = null,
    /** 경로의 IPv6 지원 여부 */
    val supportsIpv6: Boolean? = null,
    /** 경로의 DNS 지원 여부 */
    val supportsDns: Boolean? = null,
    /** OS가 보고하는 인터넷 검증 상태 */
    val internetValidated: Boolean? = null,
    /** OS가 보고하는 captive portal 상태 */
    val captivePortal: Boolean? = null,
) : DeviceSnapshot
val NetworkPathEntity = Entity<NetworkPathSnapshot>(EntityKind.NetworkPath, false, EntityMode.State, NetworkPathSnapshot::class.java)

data class NetworkPerformanceSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 하향 전송 속도 bit/s */
    val downlinkBps: Double? = null,
    /** 상향 전송 속도 bit/s */
    val uplinkBps: Double? = null,
    /** 왕복 시간 */
    val roundTripTime: Duration? = null,
    /** 플랫폼의 네트워크 성능 분류 */
    val effectiveType: EffectiveConnectionType? = null,
    /** 브라우저가 보고하는 온라인 상태 */
    val browserOnline: Boolean? = null,
) : DeviceSnapshot
val NetworkPerformanceEntity = Entity<NetworkPerformanceSnapshot>(EntityKind.NetworkPerformance, false, EntityMode.State, NetworkPerformanceSnapshot::class.java)

data class NetworkInterfaceSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 인터페이스 이름 */
    val name: String? = null,
    /** 인터페이스 종류 */
    val interfaceType: NetworkInterfaceType? = null,
    /** 인터페이스 동작 상태 */
    val operationalState: NetworkOperationalState? = null,
    /** 플랫폼이 허용해 공개하는 하드웨어 주소 */
    val hardwareAddress: String? = null,
    /** 인터페이스 IP 주소 정보 */
    val ipAddresses: List<IpAddressInfo>? = null,
    /** DNS 서버 주소 목록 */
    val dnsServers: List<String>? = null,
    /** 게이트웨이 주소 목록 */
    val gateways: List<String>? = null,
    /** 경로 정보 목록 */
    val routes: List<NetworkRoute>? = null,
    /** MTU byte 크기 */
    val mtuBytes: ULong? = null,
) : DeviceSnapshot
val NetworkInterfaceEntity = Entity<NetworkInterfaceSnapshot>(EntityKind.NetworkInterface, true, EntityMode.State, NetworkInterfaceSnapshot::class.java)

data class WifiConnectionSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 현재 연결 SSID */
    val ssid: String? = null,
    /** 현재 연결 BSSID */
    val bssid: String? = null,
    /** 현재 연결에서 선택된 인증 방식 */
    val security: WifiSecurity? = null,
    /** 수신 신호 세기 dBm */
    val rssiDbm: Double? = null,
    /** 현재 연결 주파수 Hz */
    val frequencyHz: Double? = null,
    /** 수신 링크 속도 bit/s */
    val receiveLinkSpeedBps: Double? = null,
    /** 송신 링크 속도 bit/s */
    val transmitLinkSpeedBps: Double? = null,
) : DeviceSnapshot
val WifiConnectionEntity = Entity<WifiConnectionSnapshot>(EntityKind.WifiConnection, true, EntityMode.State, WifiConnectionSnapshot::class.java)

data class CellularSubscriptionSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 슬롯 인덱스 */
    val slotIndex: Int? = null,
    /** 통신사 이름 */
    val carrierName: String? = null,
    /** 플랫폼이 보고하는 국가 코드 */
    val countryCode: String? = null,
    /** MCC. 앞자리 0을 보존하는 문자열 */
    val mobileCountryCode: String? = null,
    /** MNC. 앞자리 0을 보존하는 문자열 */
    val mobileNetworkCode: String? = null,
    /** 현재 데이터 연결의 무선 기술 */
    val radioTechnology: RadioTechnology? = null,
    /** 로밍 여부 */
    val roaming: Boolean? = null,
) : DeviceSnapshot
val CellularSubscriptionEntity = Entity<CellularSubscriptionSnapshot>(EntityKind.CellularSubscription, true, EntityMode.State, CellularSubscriptionSnapshot::class.java)

data class StorageVolumeSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 볼륨 이름 */
    val name: String? = null,
    /** 파일 시스템 */
    val fileSystem: String? = null,
    /** 볼륨 전체 용량 */
    val totalBytes: ULong? = null,
    /** 볼륨의 빈 공간 */
    val freeBytes: ULong? = null,
    /** 현재 호출자가 사용할 수 있는 여유 공간 */
    val availableToCallerBytes: ULong? = null,
    /** 할당량 등 호출자 제한을 반영한 전체 용량 */
    val totalBytesForCaller: ULong? = null,
    /** 읽기 전용 여부 */
    val readOnly: Boolean? = null,
    /** 이동식 여부 */
    val removable: Boolean? = null,
    /** 암호화 여부 */
    val encrypted: Boolean? = null,
    /** 이름의 대소문자 구분 여부 */
    val caseSensitive: Boolean? = null,
    /** 플랫폼이 중요한 용도에 제공하는 가용량 */
    val availableForImportantUsageBytes: ULong? = null,
    /** 플랫폼이 기회적 용도에 제공하는 가용량 */
    val availableForOpportunisticUsageBytes: ULong? = null,
    /** 플랫폼이 할당 가능하다고 보고하는 용량 */
    val allocatableBytes: ULong? = null,
) : DeviceSnapshot
val StorageVolumeEntity = Entity<StorageVolumeSnapshot>(EntityKind.StorageVolume, true, EntityMode.State, StorageVolumeSnapshot::class.java)

data class OriginStorageSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** origin 저장 한도 */
    val quotaBytes: ULong? = null,
    /** origin 사용량 */
    val usageBytes: ULong? = null,
    /** 플랫폼이 공개하는 저장 유형별 사용량 */
    val usageByCategory: Map<StorageCategory, ULong>? = null,
    /** 영구 저장 권한·상태 */
    val persistent: Boolean? = null,
) : DeviceSnapshot
val OriginStorageEntity = Entity<OriginStorageSnapshot>(EntityKind.OriginStorage, false, EntityMode.State, OriginStorageSnapshot::class.java)

data class AccelerometerSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 중력을 포함한 가속도 */
    val value: Vector3? = null,
) : DeviceSnapshot
val AccelerometerEntity = Entity<AccelerometerSnapshot>(EntityKind.Accelerometer, true, EntityMode.Sample, AccelerometerSnapshot::class.java)

data class LinearAccelerationSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 중력을 제외한 가속도 */
    val value: Vector3? = null,
) : DeviceSnapshot
val LinearAccelerationEntity = Entity<LinearAccelerationSnapshot>(EntityKind.LinearAcceleration, true, EntityMode.Sample, LinearAccelerationSnapshot::class.java)

data class GravitySnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 중력 벡터 */
    val value: Vector3? = null,
) : DeviceSnapshot
val GravityEntity = Entity<GravitySnapshot>(EntityKind.Gravity, true, EntityMode.Sample, GravitySnapshot::class.java)

data class GyroscopeSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 각속도 */
    val value: Vector3? = null,
) : DeviceSnapshot
val GyroscopeEntity = Entity<GyroscopeSnapshot>(EntityKind.Gyroscope, true, EntityMode.Sample, GyroscopeSnapshot::class.java)

data class MagnetometerSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 자기장 */
    val value: Vector3? = null,
) : DeviceSnapshot
val MagnetometerEntity = Entity<MagnetometerSnapshot>(EntityKind.Magnetometer, true, EntityMode.Sample, MagnetometerSnapshot::class.java)

data class RelativeOrientationSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 수집 세션의 상대 기준에 대한 자세 */
    val value: Quaternion? = null,
) : DeviceSnapshot
val RelativeOrientationEntity = Entity<RelativeOrientationSnapshot>(EntityKind.RelativeOrientation, true, EntityMode.Sample, RelativeOrientationSnapshot::class.java)

data class AbsoluteOrientationSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 동쪽·자기북·위쪽 기준에 대한 자세 */
    val value: Quaternion? = null,
) : DeviceSnapshot
val AbsoluteOrientationEntity = Entity<AbsoluteOrientationSnapshot>(EntityKind.AbsoluteOrientation, true, EntityMode.Sample, AbsoluteOrientationSnapshot::class.java)

data class IlluminanceSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 조도 */
    val value: Double? = null,
) : DeviceSnapshot
val IlluminanceEntity = Entity<IlluminanceSnapshot>(EntityKind.Illuminance, true, EntityMode.Sample, IlluminanceSnapshot::class.java)

data class PressureSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 기압 */
    val value: Double? = null,
) : DeviceSnapshot
val PressureEntity = Entity<PressureSnapshot>(EntityKind.Pressure, true, EntityMode.Sample, PressureSnapshot::class.java)

data class AmbientTemperatureSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 주변 온도 */
    val value: Double? = null,
) : DeviceSnapshot
val AmbientTemperatureEntity = Entity<AmbientTemperatureSnapshot>(EntityKind.AmbientTemperature, true, EntityMode.Sample, AmbientTemperatureSnapshot::class.java)

data class RelativeHumiditySnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 상대 습도 */
    val value: Double? = null,
) : DeviceSnapshot
val RelativeHumidityEntity = Entity<RelativeHumiditySnapshot>(EntityKind.RelativeHumidity, true, EntityMode.Sample, RelativeHumiditySnapshot::class.java)

data class ProximityNearSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 근접 상태 */
    val value: Boolean? = null,
) : DeviceSnapshot
val ProximityNearEntity = Entity<ProximityNearSnapshot>(EntityKind.ProximityNear, true, EntityMode.Sample, ProximityNearSnapshot::class.java)

data class ProximityDistanceSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 근접 대상까지의 거리 */
    val value: Double? = null,
) : DeviceSnapshot
val ProximityDistanceEntity = Entity<ProximityDistanceSnapshot>(EntityKind.ProximityDistance, true, EntityMode.Sample, ProximityDistanceSnapshot::class.java)

data class RelativeAltitudeSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 수집 세션의 기준점 대비 상대 고도 */
    val value: Double? = null,
) : DeviceSnapshot
val RelativeAltitudeEntity = Entity<RelativeAltitudeSnapshot>(EntityKind.RelativeAltitude, true, EntityMode.Sample, RelativeAltitudeSnapshot::class.java)

data class HingeAngleSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 힌지 각도 */
    val value: Double? = null,
) : DeviceSnapshot
val HingeAngleEntity = Entity<HingeAngleSnapshot>(EntityKind.HingeAngle, true, EntityMode.Sample, HingeAngleSnapshot::class.java)

data class StepCountSinceBootSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 부팅 기준 누적 걸음 수 */
    val value: Long? = null,
) : DeviceSnapshot
val StepCountSinceBootEntity = Entity<StepCountSinceBootSnapshot>(EntityKind.StepCountSinceBoot, true, EntityMode.Sample, StepCountSinceBootSnapshot::class.java)

data class StepDetectedSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 걸음 발생. false 초기 이벤트는 없음 */
    val value: Boolean? = null,
) : DeviceSnapshot
val StepDetectedEntity = Entity<StepDetectedSnapshot>(EntityKind.StepDetected, true, EntityMode.Event, StepDetectedSnapshot::class.java)

data class SignificantMotionSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 큰 움직임 발생. false 초기 이벤트는 없음 */
    val value: Boolean? = null,
) : DeviceSnapshot
val SignificantMotionEntity = Entity<SignificantMotionSnapshot>(EntityKind.SignificantMotion, true, EntityMode.Event, SignificantMotionSnapshot::class.java)

data class HumanPresenceSnapshot(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 사람 존재 여부 */
    val value: Boolean? = null,
) : DeviceSnapshot
val HumanPresenceEntity = Entity<HumanPresenceSnapshot>(EntityKind.HumanPresence, true, EntityMode.Sample, HumanPresenceSnapshot::class.java)

data class SensorDescription(
    override val collectedAt: Instant = Instant.EPOCH,
    /** 센서 종류 */
    val kind: SensorKind? = null,
    /** 센서 이름 */
    val name: String? = null,
    /** 제조사 */
    val vendor: String? = null,
    /** 플랫폼이 보고하는 센서 버전 */
    val version: String? = null,
    /** 원본 센서의 보고 모드 */
    val reportingMode: SensorReportingMode? = null,
    /** 지원되는 최소 수집 간격 */
    val minimumInterval: Duration? = null,
    /** 지원되는 최대 수집 간격 */
    val maximumInterval: Duration? = null,
    /** 해당 센서 측정 단위의 최대 범위 */
    val maximumRange: Double? = null,
    /** 해당 센서 측정 단위의 분해능 */
    val resolution: Double? = null,
    /** 플랫폼이 보고하는 전류 소비 mA */
    val powerMilliamps: Double? = null,
    /** 플랫폼이 공개하는 FIFO 샘플 수용량 */
    val fifoCapacity: Int? = null,
) : DeviceSnapshot

internal fun normalizeSnapshot(snapshot: DeviceSnapshot): DeviceSnapshot = when (snapshot) {
    is DeviceInfoSnapshot -> snapshot.copy()
    is OsSnapshot -> snapshot.copy()
    is RuntimeSnapshot -> snapshot.copy(supportedAbis = SnapshotRules.knownSet(snapshot.supportedAbis, Abi::class.java))
    is CpuSnapshot -> snapshot.copy()
    is CpuCoreSnapshot -> snapshot.copy(currentClockHz = SnapshotRules.finite(snapshot.currentClockHz), maximumClockHz = SnapshotRules.finite(snapshot.maximumClockHz))
    is RamSnapshot -> snapshot.copy()
    is ProcessMemorySnapshot -> snapshot.copy()
    is LocaleSnapshot -> snapshot.copy(preferredLanguageTags = SnapshotRules.strings(snapshot.preferredLanguageTags), systemLanguageTags = SnapshotRules.strings(snapshot.systemLanguageTags), appLanguageTags = SnapshotRules.strings(snapshot.appLanguageTags))
    is TimeZoneSnapshot -> snapshot.copy()
    is AndroidBuildSnapshot -> snapshot.copy(buildTags = SnapshotRules.strings(snapshot.buildTags))
    is AndroidIdentitySnapshot -> snapshot.copy()
    is AppleVendorIdentitySnapshot -> snapshot.copy()
    is WindowsPublisherIdentitySnapshot -> snapshot.copy()
    is MacPlatformIdentitySnapshot -> snapshot.copy()
    is HardwareSerialSnapshot -> snapshot.copy()
    is TelephonyIdentitySnapshot -> snapshot.copy()
    is DisplaySnapshot -> snapshot.copy(logicalBounds = SnapshotRules.rectangle(snapshot.logicalBounds), workAreaBounds = SnapshotRules.rectangle(snapshot.workAreaBounds), physicalSizeMillimeters = SnapshotRules.size(snapshot.physicalSizeMillimeters), rotationDegrees = SnapshotRules.finite(snapshot.rotationDegrees), scaleFactor = SnapshotRules.finite(snapshot.scaleFactor), densityDpi = SnapshotRules.finite(snapshot.densityDpi), supportedModes = SnapshotRules.displayModes(snapshot.supportedModes), maximumRefreshRateHz = SnapshotRules.finite(snapshot.maximumRefreshRateHz), hdrFormats = SnapshotRules.knownSet(snapshot.hdrFormats, HdrFormat::class.java), brightness = SnapshotRules.ratio(snapshot.brightness))
    is ViewportSnapshot -> snapshot.copy(size = SnapshotRules.size(snapshot.size), visualViewportSize = SnapshotRules.size(snapshot.visualViewportSize), visualViewportScale = SnapshotRules.finite(snapshot.visualViewportScale), safeAreaInsets = SnapshotRules.insets(snapshot.safeAreaInsets), textScaleFactor = SnapshotRules.finite(snapshot.textScaleFactor))
    is PowerSnapshot -> snapshot.copy()
    is BatterySnapshot -> snapshot.copy(level = SnapshotRules.ratio(snapshot.level), timeToFull = SnapshotRules.duration(snapshot.timeToFull), timeToEmpty = SnapshotRules.duration(snapshot.timeToEmpty), voltageMillivolts = SnapshotRules.finite(snapshot.voltageMillivolts), currentMicroamps = SnapshotRules.finite(snapshot.currentMicroamps), averageCurrentMicroamps = SnapshotRules.finite(snapshot.averageCurrentMicroamps), chargeRateMilliwatts = SnapshotRules.finite(snapshot.chargeRateMilliwatts), temperatureCelsius = SnapshotRules.finite(snapshot.temperatureCelsius), remainingEnergyMilliwattHours = SnapshotRules.finite(snapshot.remainingEnergyMilliwattHours), fullChargeEnergyMilliwattHours = SnapshotRules.finite(snapshot.fullChargeEnergyMilliwattHours), designEnergyMilliwattHours = SnapshotRules.finite(snapshot.designEnergyMilliwattHours))
    is NetworkPathSnapshot -> snapshot.copy(transports = SnapshotRules.knownSet(snapshot.transports, NetworkTransport::class.java))
    is NetworkPerformanceSnapshot -> snapshot.copy(downlinkBps = SnapshotRules.finite(snapshot.downlinkBps), uplinkBps = SnapshotRules.finite(snapshot.uplinkBps), roundTripTime = SnapshotRules.duration(snapshot.roundTripTime))
    is NetworkInterfaceSnapshot -> snapshot.copy(ipAddresses = SnapshotRules.addresses(snapshot.ipAddresses), dnsServers = SnapshotRules.strings(snapshot.dnsServers), gateways = SnapshotRules.strings(snapshot.gateways), routes = SnapshotRules.routes(snapshot.routes))
    is WifiConnectionSnapshot -> snapshot.copy(rssiDbm = SnapshotRules.finite(snapshot.rssiDbm), frequencyHz = SnapshotRules.finite(snapshot.frequencyHz), receiveLinkSpeedBps = SnapshotRules.finite(snapshot.receiveLinkSpeedBps), transmitLinkSpeedBps = SnapshotRules.finite(snapshot.transmitLinkSpeedBps))
    is CellularSubscriptionSnapshot -> snapshot.copy()
    is StorageVolumeSnapshot -> snapshot.copy()
    is OriginStorageSnapshot -> snapshot.copy(usageByCategory = SnapshotRules.knownMap(snapshot.usageByCategory, StorageCategory::class.java))
    is AccelerometerSnapshot -> snapshot.copy(value = SnapshotRules.vector(snapshot.value))
    is LinearAccelerationSnapshot -> snapshot.copy(value = SnapshotRules.vector(snapshot.value))
    is GravitySnapshot -> snapshot.copy(value = SnapshotRules.vector(snapshot.value))
    is GyroscopeSnapshot -> snapshot.copy(value = SnapshotRules.vector(snapshot.value))
    is MagnetometerSnapshot -> snapshot.copy(value = SnapshotRules.vector(snapshot.value))
    is RelativeOrientationSnapshot -> snapshot.copy(value = SnapshotRules.rotation(snapshot.value))
    is AbsoluteOrientationSnapshot -> snapshot.copy(value = SnapshotRules.rotation(snapshot.value))
    is IlluminanceSnapshot -> snapshot.copy(value = SnapshotRules.finite(snapshot.value))
    is PressureSnapshot -> snapshot.copy(value = SnapshotRules.finite(snapshot.value))
    is AmbientTemperatureSnapshot -> snapshot.copy(value = SnapshotRules.finite(snapshot.value))
    is RelativeHumiditySnapshot -> snapshot.copy(value = SnapshotRules.ratio(snapshot.value))
    is ProximityNearSnapshot -> snapshot.copy()
    is ProximityDistanceSnapshot -> snapshot.copy(value = SnapshotRules.finite(snapshot.value))
    is RelativeAltitudeSnapshot -> snapshot.copy(value = SnapshotRules.finite(snapshot.value))
    is HingeAngleSnapshot -> snapshot.copy(value = SnapshotRules.finite(snapshot.value))
    is StepCountSinceBootSnapshot -> snapshot.copy()
    is StepDetectedSnapshot -> snapshot.copy()
    is SignificantMotionSnapshot -> snapshot.copy()
    is HumanPresenceSnapshot -> snapshot.copy()
    is SensorDescription -> snapshot.copy(minimumInterval = SnapshotRules.duration(snapshot.minimumInterval), maximumInterval = SnapshotRules.duration(snapshot.maximumInterval), maximumRange = SnapshotRules.finite(snapshot.maximumRange), resolution = SnapshotRules.finite(snapshot.resolution), powerMilliamps = SnapshotRules.finite(snapshot.powerMilliamps))
    else -> throw DeviceReadoutException(ErrorCode.ReadFailed, "Unknown snapshot type.")
}

internal fun stamp(value: DeviceSnapshot): DeviceSnapshot {
    val snapshot = normalizeSnapshot(value)
    return when (snapshot) {
    is DeviceInfoSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is OsSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is RuntimeSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is CpuSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is CpuCoreSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is RamSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is ProcessMemorySnapshot -> snapshot.copy(collectedAt = Instant.now())
    is LocaleSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is TimeZoneSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is AndroidBuildSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is AndroidIdentitySnapshot -> snapshot.copy(collectedAt = Instant.now())
    is AppleVendorIdentitySnapshot -> snapshot.copy(collectedAt = Instant.now())
    is WindowsPublisherIdentitySnapshot -> snapshot.copy(collectedAt = Instant.now())
    is MacPlatformIdentitySnapshot -> snapshot.copy(collectedAt = Instant.now())
    is HardwareSerialSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is TelephonyIdentitySnapshot -> snapshot.copy(collectedAt = Instant.now())
    is DisplaySnapshot -> snapshot.copy(collectedAt = Instant.now())
    is ViewportSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is PowerSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is BatterySnapshot -> snapshot.copy(collectedAt = Instant.now())
    is NetworkPathSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is NetworkPerformanceSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is NetworkInterfaceSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is WifiConnectionSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is CellularSubscriptionSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is StorageVolumeSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is OriginStorageSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is AccelerometerSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is LinearAccelerationSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is GravitySnapshot -> snapshot.copy(collectedAt = Instant.now())
    is GyroscopeSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is MagnetometerSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is RelativeOrientationSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is AbsoluteOrientationSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is IlluminanceSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is PressureSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is AmbientTemperatureSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is RelativeHumiditySnapshot -> snapshot.copy(collectedAt = Instant.now())
    is ProximityNearSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is ProximityDistanceSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is RelativeAltitudeSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is HingeAngleSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is StepCountSinceBootSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is StepDetectedSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is SignificantMotionSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is HumanPresenceSnapshot -> snapshot.copy(collectedAt = Instant.now())
    is SensorDescription -> snapshot.copy(collectedAt = Instant.now())
    else -> throw DeviceReadoutException(ErrorCode.ReadFailed, "Unknown snapshot type.")
    }
}

internal fun snapshotFields(snapshot: DeviceSnapshot): Map<String, Any?> = when (snapshot) {
    is DeviceInfoSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "manufacturer" to snapshot.manufacturer, "brand" to snapshot.brand, "modelCode" to snapshot.modelCode, "modelName" to snapshot.modelName, "deviceName" to snapshot.deviceName, "formFactor" to snapshot.formFactor, "product" to snapshot.product, "board" to snapshot.board)
    is OsSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "family" to snapshot.family, "name" to snapshot.name, "version" to snapshot.version, "build" to snapshot.build, "kernelName" to snapshot.kernelName, "kernelVersion" to snapshot.kernelVersion)
    is RuntimeSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "hostArchitecture" to snapshot.hostArchitecture, "processArchitecture" to snapshot.processArchitecture, "processBitness" to snapshot.processBitness, "supportedAbis" to snapshot.supportedAbis)
    is CpuSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "model" to snapshot.model, "manufacturer" to snapshot.manufacturer, "socModel" to snapshot.socModel, "socManufacturer" to snapshot.socManufacturer, "logicalProcessorCount" to snapshot.logicalProcessorCount, "availableLogicalProcessorCount" to snapshot.availableLogicalProcessorCount, "physicalCoreCount" to snapshot.physicalCoreCount, "processorPackageCount" to snapshot.processorPackageCount)
    is CpuCoreSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "logicalIndex" to snapshot.logicalIndex, "coreIndex" to snapshot.coreIndex, "packageIndex" to snapshot.packageIndex, "online" to snapshot.online, "currentClockHz" to snapshot.currentClockHz, "maximumClockHz" to snapshot.maximumClockHz)
    is RamSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "physicalBytes" to snapshot.physicalBytes, "kernelAccessibleBytes" to snapshot.kernelAccessibleBytes, "advertisedBytes" to snapshot.advertisedBytes, "availableBytes" to snapshot.availableBytes, "freeBytes" to snapshot.freeBytes, "lowMemory" to snapshot.lowMemory, "lowMemoryThresholdBytes" to snapshot.lowMemoryThresholdBytes)
    is ProcessMemorySnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "allocationRemainingBytes" to snapshot.allocationRemainingBytes)
    is LocaleSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "currentLanguageTag" to snapshot.currentLanguageTag, "preferredLanguageTags" to snapshot.preferredLanguageTags, "systemLanguageTags" to snapshot.systemLanguageTags, "appLanguageTags" to snapshot.appLanguageTags, "regionCode" to snapshot.regionCode, "scriptCode" to snapshot.scriptCode, "calendar" to snapshot.calendar, "numberingSystem" to snapshot.numberingSystem, "hourCycle" to snapshot.hourCycle, "firstWeekday" to snapshot.firstWeekday, "measurementSystem" to snapshot.measurementSystem)
    is TimeZoneSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "ianaId" to snapshot.ianaId, "windowsId" to snapshot.windowsId, "utcOffsetSeconds" to snapshot.utcOffsetSeconds, "daylightSavingTime" to snapshot.daylightSavingTime)
    is AndroidBuildSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "apiLevel" to snapshot.apiLevel, "securityPatch" to snapshot.securityPatch, "buildId" to snapshot.buildId, "buildDisplay" to snapshot.buildDisplay, "buildFingerprint" to snapshot.buildFingerprint, "buildType" to snapshot.buildType, "buildTags" to snapshot.buildTags, "bootloaderVersion" to snapshot.bootloaderVersion)
    is AndroidIdentitySnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "androidId" to snapshot.androidId)
    is AppleVendorIdentitySnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "vendorId" to snapshot.vendorId)
    is WindowsPublisherIdentitySnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "publisherId" to snapshot.publisherId, "source" to snapshot.source)
    is MacPlatformIdentitySnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "platformUuid" to snapshot.platformUuid)
    is HardwareSerialSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "serial" to snapshot.serial)
    is TelephonyIdentitySnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "imei" to snapshot.imei, "meid" to snapshot.meid)
    is DisplaySnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "label" to snapshot.label, "primary" to snapshot.primary, "internal" to snapshot.internal, "state" to snapshot.state, "logicalBounds" to snapshot.logicalBounds, "workAreaBounds" to snapshot.workAreaBounds, "pixelSize" to snapshot.pixelSize, "physicalSizeMillimeters" to snapshot.physicalSizeMillimeters, "orientation" to snapshot.orientation, "rotationDegrees" to snapshot.rotationDegrees, "scaleFactor" to snapshot.scaleFactor, "densityDpi" to snapshot.densityDpi, "currentMode" to snapshot.currentMode, "supportedModes" to snapshot.supportedModes, "maximumRefreshRateHz" to snapshot.maximumRefreshRateHz, "colorDepthBits" to snapshot.colorDepthBits, "colorGamut" to snapshot.colorGamut, "hdrFormats" to snapshot.hdrFormats, "brightness" to snapshot.brightness)
    is ViewportSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "size" to snapshot.size, "visualViewportSize" to snapshot.visualViewportSize, "visualViewportScale" to snapshot.visualViewportScale, "safeAreaInsets" to snapshot.safeAreaInsets, "textScaleFactor" to snapshot.textScaleFactor)
    is PowerSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "powerSource" to snapshot.powerSource, "powerSaveMode" to snapshot.powerSaveMode, "thermalState" to snapshot.thermalState)
    is BatterySnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "present" to snapshot.present, "level" to snapshot.level, "charging" to snapshot.charging, "state" to snapshot.state, "timeToFull" to snapshot.timeToFull, "timeToEmpty" to snapshot.timeToEmpty, "voltageMillivolts" to snapshot.voltageMillivolts, "currentMicroamps" to snapshot.currentMicroamps, "averageCurrentMicroamps" to snapshot.averageCurrentMicroamps, "chargeRateMilliwatts" to snapshot.chargeRateMilliwatts, "temperatureCelsius" to snapshot.temperatureCelsius, "chargeCounterMicroampHours" to snapshot.chargeCounterMicroampHours, "remainingEnergyMilliwattHours" to snapshot.remainingEnergyMilliwattHours, "fullChargeEnergyMilliwattHours" to snapshot.fullChargeEnergyMilliwattHours, "designEnergyMilliwattHours" to snapshot.designEnergyMilliwattHours, "technology" to snapshot.technology, "health" to snapshot.health, "cycleCount" to snapshot.cycleCount)
    is NetworkPathSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "connectionState" to snapshot.connectionState, "transports" to snapshot.transports, "metered" to snapshot.metered, "expensive" to snapshot.expensive, "constrained" to snapshot.constrained, "saveData" to snapshot.saveData, "supportsIpv4" to snapshot.supportsIpv4, "supportsIpv6" to snapshot.supportsIpv6, "supportsDns" to snapshot.supportsDns, "internetValidated" to snapshot.internetValidated, "captivePortal" to snapshot.captivePortal)
    is NetworkPerformanceSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "downlinkBps" to snapshot.downlinkBps, "uplinkBps" to snapshot.uplinkBps, "roundTripTime" to snapshot.roundTripTime, "effectiveType" to snapshot.effectiveType, "browserOnline" to snapshot.browserOnline)
    is NetworkInterfaceSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "name" to snapshot.name, "interfaceType" to snapshot.interfaceType, "operationalState" to snapshot.operationalState, "hardwareAddress" to snapshot.hardwareAddress, "ipAddresses" to snapshot.ipAddresses, "dnsServers" to snapshot.dnsServers, "gateways" to snapshot.gateways, "routes" to snapshot.routes, "mtuBytes" to snapshot.mtuBytes)
    is WifiConnectionSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "ssid" to snapshot.ssid, "bssid" to snapshot.bssid, "security" to snapshot.security, "rssiDbm" to snapshot.rssiDbm, "frequencyHz" to snapshot.frequencyHz, "receiveLinkSpeedBps" to snapshot.receiveLinkSpeedBps, "transmitLinkSpeedBps" to snapshot.transmitLinkSpeedBps)
    is CellularSubscriptionSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "slotIndex" to snapshot.slotIndex, "carrierName" to snapshot.carrierName, "countryCode" to snapshot.countryCode, "mobileCountryCode" to snapshot.mobileCountryCode, "mobileNetworkCode" to snapshot.mobileNetworkCode, "radioTechnology" to snapshot.radioTechnology, "roaming" to snapshot.roaming)
    is StorageVolumeSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "name" to snapshot.name, "fileSystem" to snapshot.fileSystem, "totalBytes" to snapshot.totalBytes, "freeBytes" to snapshot.freeBytes, "availableToCallerBytes" to snapshot.availableToCallerBytes, "totalBytesForCaller" to snapshot.totalBytesForCaller, "readOnly" to snapshot.readOnly, "removable" to snapshot.removable, "encrypted" to snapshot.encrypted, "caseSensitive" to snapshot.caseSensitive, "availableForImportantUsageBytes" to snapshot.availableForImportantUsageBytes, "availableForOpportunisticUsageBytes" to snapshot.availableForOpportunisticUsageBytes, "allocatableBytes" to snapshot.allocatableBytes)
    is OriginStorageSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "quotaBytes" to snapshot.quotaBytes, "usageBytes" to snapshot.usageBytes, "usageByCategory" to snapshot.usageByCategory, "persistent" to snapshot.persistent)
    is AccelerometerSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is LinearAccelerationSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is GravitySnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is GyroscopeSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is MagnetometerSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is RelativeOrientationSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is AbsoluteOrientationSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is IlluminanceSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is PressureSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is AmbientTemperatureSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is RelativeHumiditySnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is ProximityNearSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is ProximityDistanceSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is RelativeAltitudeSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is HingeAngleSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is StepCountSinceBootSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is StepDetectedSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is SignificantMotionSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is HumanPresenceSnapshot -> linkedMapOf("collectedAt" to snapshot.collectedAt, "value" to snapshot.value)
    is SensorDescription -> linkedMapOf("collectedAt" to snapshot.collectedAt, "kind" to snapshot.kind, "name" to snapshot.name, "vendor" to snapshot.vendor, "version" to snapshot.version, "reportingMode" to snapshot.reportingMode, "minimumInterval" to snapshot.minimumInterval, "maximumInterval" to snapshot.maximumInterval, "maximumRange" to snapshot.maximumRange, "resolution" to snapshot.resolution, "powerMilliamps" to snapshot.powerMilliamps, "fifoCapacity" to snapshot.fifoCapacity)
    else -> throw DeviceReadoutException(ErrorCode.ReadFailed, "Unknown snapshot type.")
}

internal fun bindingEntity(name: String): Entity<out DeviceSnapshot> = when (name) {
    "DeviceInfo" -> DeviceInfoEntity
    "Os" -> OsEntity
    "Runtime" -> RuntimeEntity
    "Cpu" -> CpuEntity
    "CpuCore" -> CpuCoreEntity
    "Ram" -> RamEntity
    "ProcessMemory" -> ProcessMemoryEntity
    "Locale" -> LocaleEntity
    "TimeZone" -> TimeZoneEntity
    "AndroidBuild" -> AndroidBuildEntity
    "AndroidIdentity" -> AndroidIdentityEntity
    "AppleVendorIdentity" -> AppleVendorIdentityEntity
    "WindowsPublisherIdentity" -> WindowsPublisherIdentityEntity
    "MacPlatformIdentity" -> MacPlatformIdentityEntity
    "HardwareSerial" -> HardwareSerialEntity
    "TelephonyIdentity" -> TelephonyIdentityEntity
    "Display" -> DisplayEntity
    "Viewport" -> ViewportEntity
    "Power" -> PowerEntity
    "Battery" -> BatteryEntity
    "NetworkPath" -> NetworkPathEntity
    "NetworkPerformance" -> NetworkPerformanceEntity
    "NetworkInterface" -> NetworkInterfaceEntity
    "WifiConnection" -> WifiConnectionEntity
    "CellularSubscription" -> CellularSubscriptionEntity
    "StorageVolume" -> StorageVolumeEntity
    "OriginStorage" -> OriginStorageEntity
    "Accelerometer" -> AccelerometerEntity
    "LinearAcceleration" -> LinearAccelerationEntity
    "Gravity" -> GravityEntity
    "Gyroscope" -> GyroscopeEntity
    "Magnetometer" -> MagnetometerEntity
    "RelativeOrientation" -> RelativeOrientationEntity
    "AbsoluteOrientation" -> AbsoluteOrientationEntity
    "Illuminance" -> IlluminanceEntity
    "Pressure" -> PressureEntity
    "AmbientTemperature" -> AmbientTemperatureEntity
    "RelativeHumidity" -> RelativeHumidityEntity
    "ProximityNear" -> ProximityNearEntity
    "ProximityDistance" -> ProximityDistanceEntity
    "RelativeAltitude" -> RelativeAltitudeEntity
    "HingeAngle" -> HingeAngleEntity
    "StepCountSinceBoot" -> StepCountSinceBootEntity
    "StepDetected" -> StepDetectedEntity
    "SignificantMotion" -> SignificantMotionEntity
    "HumanPresence" -> HumanPresenceEntity
    else -> throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "Unknown entity kind.")
}
