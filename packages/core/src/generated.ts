// Generated from schema/device-readout.json and schema/enums.json.
import { defineEntity } from './entity.js';
import type { DeviceSnapshot, CalendarId, NumberingSystemId, Size, Rect, Insets, Vector3, Quaternion, DisplayMode, IpAddress, IpAddressInfo, NetworkRoute, Duration } from './structures.js';
export enum FormFactor {
  Phone = 'Phone',
  Tablet = 'Tablet',
  Laptop = 'Laptop',
  Desktop = 'Desktop',
  Television = 'Television',
  Watch = 'Watch',
  Automotive = 'Automotive',
  Headset = 'Headset',
}
export enum OsFamily {
  Android = 'Android',
  IOS = 'IOS',
  IPadOS = 'IPadOS',
  Windows = 'Windows',
  MacOS = 'MacOS',
  Linux = 'Linux',
  ChromeOS = 'ChromeOS',
}
export enum Architecture {
  X86 = 'X86',
  X64 = 'X64',
  Arm32 = 'Arm32',
  Arm64 = 'Arm64',
  RiscV32 = 'RiscV32',
  RiscV64 = 'RiscV64',
  Wasm32 = 'Wasm32',
  Wasm64 = 'Wasm64',
}
export enum Abi {
  ArmeabiV7a = 'ArmeabiV7a',
  Arm64V8a = 'Arm64V8a',
  X86 = 'X86',
  X86_64 = 'X86_64',
}
export enum HourCycle {
  H11 = 'H11',
  H12 = 'H12',
  H23 = 'H23',
  H24 = 'H24',
}
export enum Weekday {
  Monday = 'Monday',
  Tuesday = 'Tuesday',
  Wednesday = 'Wednesday',
  Thursday = 'Thursday',
  Friday = 'Friday',
  Saturday = 'Saturday',
  Sunday = 'Sunday',
}
export enum MeasurementSystem {
  Metric = 'Metric',
  US = 'US',
  UK = 'UK',
}
export enum WindowsIdentitySource {
  Tpm = 'Tpm',
  Uefi = 'Uefi',
  Registry = 'Registry',
}
export enum DisplayState {
  On = 'On',
  Off = 'Off',
  Doze = 'Doze',
  DozeSuspended = 'DozeSuspended',
  OnSuspended = 'OnSuspended',
}
export enum DisplayOrientation {
  PortraitPrimary = 'PortraitPrimary',
  PortraitSecondary = 'PortraitSecondary',
  LandscapePrimary = 'LandscapePrimary',
  LandscapeSecondary = 'LandscapeSecondary',
}
export enum ColorGamut {
  Srgb = 'Srgb',
  DisplayP3 = 'DisplayP3',
  Rec2020 = 'Rec2020',
}
export enum HdrFormat {
  Hdr10 = 'Hdr10',
  Hdr10Plus = 'Hdr10Plus',
  DolbyVision = 'DolbyVision',
  Hlg = 'Hlg',
}
export enum PowerSource {
  Battery = 'Battery',
  External = 'External',
  Ups = 'Ups',
}
export enum AndroidThermalState {
  None = 'AndroidThermalState.None',
  Light = 'AndroidThermalState.Light',
  Moderate = 'AndroidThermalState.Moderate',
  Severe = 'AndroidThermalState.Severe',
  Critical = 'AndroidThermalState.Critical',
  Emergency = 'AndroidThermalState.Emergency',
  Shutdown = 'AndroidThermalState.Shutdown',
}
export enum AppleThermalState {
  Nominal = 'AppleThermalState.Nominal',
  Fair = 'AppleThermalState.Fair',
  Serious = 'AppleThermalState.Serious',
  Critical = 'AppleThermalState.Critical',
}
export enum BatteryState {
  Charging = 'Charging',
  Discharging = 'Discharging',
  Full = 'Full',
  NotCharging = 'NotCharging',
  Idle = 'Idle',
}
export enum BatteryHealth {
  Good = 'Good',
  Overheated = 'Overheated',
  Cold = 'Cold',
  Dead = 'Dead',
  OverVoltage = 'OverVoltage',
  UnspecifiedFailure = 'UnspecifiedFailure',
}
export enum ConnectionState {
  Connected = 'Connected',
  Disconnected = 'Disconnected',
  Connecting = 'Connecting',
  Disconnecting = 'Disconnecting',
  Suspended = 'Suspended',
  ConnectionRequired = 'ConnectionRequired',
}
export enum NetworkTransport {
  Wifi = 'Wifi',
  Cellular = 'Cellular',
  Ethernet = 'Ethernet',
  Bluetooth = 'Bluetooth',
  Vpn = 'Vpn',
  Usb = 'Usb',
  WifiAware = 'WifiAware',
  Lowpan = 'Lowpan',
  Thread = 'Thread',
  Satellite = 'Satellite',
}
export enum EffectiveConnectionType {
  Slow2G = 'Slow2G',
  Type2G = 'Type2G',
  Type3G = 'Type3G',
  Type4G = 'Type4G',
}
export enum NetworkInterfaceType {
  Ethernet = 'Ethernet',
  Wifi = 'Wifi',
  Cellular = 'Cellular',
  Bluetooth = 'Bluetooth',
  Loopback = 'Loopback',
  Tunnel = 'Tunnel',
  Ppp = 'Ppp',
  Bridge = 'Bridge',
}
export enum NetworkOperationalState {
  Up = 'Up',
  Down = 'Down',
  Testing = 'Testing',
  Dormant = 'Dormant',
  NotPresent = 'NotPresent',
  LowerLayerDown = 'LowerLayerDown',
}
export enum WifiSecurity {
  Open = 'Open',
  Wep = 'Wep',
  Psk = 'Psk',
  Eap = 'Eap',
  Sae = 'Sae',
  Owe = 'Owe',
  WapiPsk = 'WapiPsk',
  WapiCert = 'WapiCert',
  EapWpa3Enterprise = 'EapWpa3Enterprise',
  EapWpa3Enterprise192Bit = 'EapWpa3Enterprise192Bit',
  PasspointR1R2 = 'PasspointR1R2',
  PasspointR3 = 'PasspointR3',
  Dpp = 'Dpp',
}
export enum RadioTechnology {
  Gsm = 'Gsm',
  Gprs = 'Gprs',
  Edge = 'Edge',
  Cdma = 'Cdma',
  Cdma1x = 'Cdma1x',
  Evdo0 = 'Evdo0',
  EvdoA = 'EvdoA',
  EvdoB = 'EvdoB',
  Ehrpd = 'Ehrpd',
  Umts = 'Umts',
  Hsdpa = 'Hsdpa',
  Hsupa = 'Hsupa',
  Hspa = 'Hspa',
  HspaPlus = 'HspaPlus',
  Iden = 'Iden',
  TdScdma = 'TdScdma',
  Lte = 'Lte',
  LteCa = 'LteCa',
  Nr = 'Nr',
  NrNsa = 'NrNsa',
  NrSa = 'NrSa',
  Iwlan = 'Iwlan',
}
export enum StorageCategory {
  IndexedDB = 'IndexedDB',
  Caches = 'Caches',
  ServiceWorker = 'ServiceWorker',
  FileSystem = 'FileSystem',
  LocalStorage = 'LocalStorage',
  SessionStorage = 'SessionStorage',
}
export enum SensorReportingMode {
  Continuous = 'Continuous',
  OnChange = 'OnChange',
  OneShot = 'OneShot',
  SpecialTrigger = 'SpecialTrigger',
}
export enum SensorKind {
  Accelerometer = 'Accelerometer',
  LinearAcceleration = 'LinearAcceleration',
  Gravity = 'Gravity',
  Gyroscope = 'Gyroscope',
  Magnetometer = 'Magnetometer',
  RelativeOrientation = 'RelativeOrientation',
  AbsoluteOrientation = 'AbsoluteOrientation',
  Illuminance = 'Illuminance',
  Pressure = 'Pressure',
  AmbientTemperature = 'AmbientTemperature',
  RelativeHumidity = 'RelativeHumidity',
  ProximityNear = 'ProximityNear',
  ProximityDistance = 'ProximityDistance',
  RelativeAltitude = 'RelativeAltitude',
  HingeAngle = 'HingeAngle',
  StepCountSinceBoot = 'StepCountSinceBoot',
  StepDetected = 'StepDetected',
  SignificantMotion = 'SignificantMotion',
  HumanPresence = 'HumanPresence',
}
export type ThermalState = AndroidThermalState | AppleThermalState;
export enum EntityKind {
  DeviceInfo = 'DeviceInfo',
  Os = 'Os',
  Runtime = 'Runtime',
  Cpu = 'Cpu',
  CpuCore = 'CpuCore',
  Ram = 'Ram',
  ProcessMemory = 'ProcessMemory',
  Locale = 'Locale',
  TimeZone = 'TimeZone',
  AndroidBuild = 'AndroidBuild',
  AndroidIdentity = 'AndroidIdentity',
  AppleVendorIdentity = 'AppleVendorIdentity',
  WindowsPublisherIdentity = 'WindowsPublisherIdentity',
  MacPlatformIdentity = 'MacPlatformIdentity',
  HardwareSerial = 'HardwareSerial',
  TelephonyIdentity = 'TelephonyIdentity',
  Display = 'Display',
  Viewport = 'Viewport',
  Power = 'Power',
  Battery = 'Battery',
  NetworkPath = 'NetworkPath',
  NetworkPerformance = 'NetworkPerformance',
  NetworkInterface = 'NetworkInterface',
  WifiConnection = 'WifiConnection',
  CellularSubscription = 'CellularSubscription',
  StorageVolume = 'StorageVolume',
  OriginStorage = 'OriginStorage',
  Accelerometer = 'Accelerometer',
  LinearAcceleration = 'LinearAcceleration',
  Gravity = 'Gravity',
  Gyroscope = 'Gyroscope',
  Magnetometer = 'Magnetometer',
  RelativeOrientation = 'RelativeOrientation',
  AbsoluteOrientation = 'AbsoluteOrientation',
  Illuminance = 'Illuminance',
  Pressure = 'Pressure',
  AmbientTemperature = 'AmbientTemperature',
  RelativeHumidity = 'RelativeHumidity',
  ProximityNear = 'ProximityNear',
  ProximityDistance = 'ProximityDistance',
  RelativeAltitude = 'RelativeAltitude',
  HingeAngle = 'HingeAngle',
  StepCountSinceBoot = 'StepCountSinceBoot',
  StepDetected = 'StepDetected',
  SignificantMotion = 'SignificantMotion',
  HumanPresence = 'HumanPresence',
}
export interface DeviceInfoSnapshot extends DeviceSnapshot {
  /** 제조사 */
  readonly manufacturer: string | null;
  /** 브랜드 */
  readonly brand: string | null;
  /** 플랫폼의 모델 코드 */
  readonly modelCode: string | null;
  /** 사용자에게 표시할 모델 이름 */
  readonly modelName: string | null;
  /** OS가 공개하는 기기 이름 */
  readonly deviceName: string | null;
  /** 휴대전화·태블릿·노트북 등 기기 형태 */
  readonly formFactor: FormFactor | null;
  /** 제품 식별 이름 */
  readonly product: string | null;
  /** 보드 식별 이름 */
  readonly board: string | null;
}
export const DeviceInfoEntity = defineEntity<DeviceInfoSnapshot>(EntityKind.DeviceInfo, false);
export interface OsSnapshot extends DeviceSnapshot {
  /** 운영체제 계열 */
  readonly family: OsFamily | null;
  /** 운영체제 이름 */
  readonly name: string | null;
  /** 운영체제 버전 */
  readonly version: string | null;
  /** 운영체제 빌드 */
  readonly build: string | null;
  /** 커널 이름 */
  readonly kernelName: string | null;
  /** 커널 버전 */
  readonly kernelVersion: string | null;
}
export const OsEntity = defineEntity<OsSnapshot>(EntityKind.Os, false);
export interface RuntimeSnapshot extends DeviceSnapshot {
  /** 호스트 시스템 아키텍처 */
  readonly hostArchitecture: Architecture | null;
  /** 현재 프로세스 아키텍처 */
  readonly processArchitecture: Architecture | null;
  /** 현재 프로세스 비트 수 */
  readonly processBitness: number | null;
  /** 플랫폼이 공개하는 지원 ABI 집합 */
  readonly supportedAbis: ReadonlySet<Abi> | null;
}
export const RuntimeEntity = defineEntity<RuntimeSnapshot>(EntityKind.Runtime, false);
export interface CpuSnapshot extends DeviceSnapshot {
  /** CPU 모델 */
  readonly model: string | null;
  /** CPU 제조사 */
  readonly manufacturer: string | null;
  /** SoC 모델 */
  readonly socModel: string | null;
  /** SoC 제조사 */
  readonly socManufacturer: string | null;
  /** 전체 논리 프로세서 수 */
  readonly logicalProcessorCount: number | null;
  /** 현재 실행 환경에 제공되는 논리 프로세서 수 */
  readonly availableLogicalProcessorCount: number | null;
  /** 물리 코어 수 */
  readonly physicalCoreCount: number | null;
  /** 프로세서 패키지 수 */
  readonly processorPackageCount: number | null;
}
export const CpuEntity = defineEntity<CpuSnapshot>(EntityKind.Cpu, false);
export interface CpuCoreSnapshot extends DeviceSnapshot {
  /** 논리 프로세서 인덱스 */
  readonly logicalIndex: number | null;
  /** 소속 물리 코어 인덱스 */
  readonly coreIndex: number | null;
  /** 소속 프로세서 패키지 인덱스 */
  readonly packageIndex: number | null;
  /** OS에서 사용 가능한 온라인 상태 */
  readonly online: boolean | null;
  /** 현재 클록 주파수 */
  readonly currentClockHz: number | null;
  /** 플랫폼이 보고하는 최대 클록 주파수 */
  readonly maximumClockHz: number | null;
}
export const CpuCoreEntity = defineEntity<CpuCoreSnapshot>(EntityKind.CpuCore, true);
export interface RamSnapshot extends DeviceSnapshot {
  /** 설치된 물리 RAM 용량 */
  readonly physicalBytes: bigint | null;
  /** 커널이 접근 가능한 RAM 용량 */
  readonly kernelAccessibleBytes: bigint | null;
  /** 플랫폼이 외부에 공개하는 표기용 RAM 용량 */
  readonly advertisedBytes: bigint | null;
  /** OS 정의상 사용 가능한 메모리 */
  readonly availableBytes: bigint | null;
  /** OS 정의상 비어 있는 메모리 */
  readonly freeBytes: bigint | null;
  /** OS가 보고하는 메모리 부족 상태 */
  readonly lowMemory: boolean | null;
  /** OS가 공개하는 메모리 부족 기준 용량 */
  readonly lowMemoryThresholdBytes: bigint | null;
}
export const RamEntity = defineEntity<RamSnapshot>(EntityKind.Ram, false);
export interface ProcessMemorySnapshot extends DeviceSnapshot {
  /** 현재 앱이 추가로 할당할 수 있다고 플랫폼이 보고하는 메모리 */
  readonly allocationRemainingBytes: bigint | null;
}
export const ProcessMemoryEntity = defineEntity<ProcessMemorySnapshot>(EntityKind.ProcessMemory, false);
export interface LocaleSnapshot extends DeviceSnapshot {
  /** 현재 유효한 언어 태그 */
  readonly currentLanguageTag: string | null;
  /** 선호 언어 태그. 원래 우선순위 보존 */
  readonly preferredLanguageTags: ReadonlyArray<string> | null;
  /** 시스템 언어 태그 목록 */
  readonly systemLanguageTags: ReadonlyArray<string> | null;
  /** 앱에 적용된 언어 태그 목록 */
  readonly appLanguageTags: ReadonlyArray<string> | null;
  /** 로케일 지역 코드 */
  readonly regionCode: string | null;
  /** 문자 체계 코드 */
  readonly scriptCode: string | null;
  /** 달력 체계 식별자 */
  readonly calendar: CalendarId | null;
  /** 숫자 표기 체계 식별자 */
  readonly numberingSystem: NumberingSystemId | null;
  /** 시간 표기 주기 */
  readonly hourCycle: HourCycle | null;
  /** 한 주의 첫 요일 */
  readonly firstWeekday: Weekday | null;
  /** 도량형 체계 */
  readonly measurementSystem: MeasurementSystem | null;
}
export const LocaleEntity = defineEntity<LocaleSnapshot>(EntityKind.Locale, false);
export interface TimeZoneSnapshot extends DeviceSnapshot {
  /** IANA 시간대 식별자 */
  readonly ianaId: string | null;
  /** Windows 시간대 식별자 */
  readonly windowsId: string | null;
  /** 수집 시점의 UTC 오프셋 초 */
  readonly utcOffsetSeconds: number | null;
  /** 수집 시점의 서머타임 적용 여부 */
  readonly daylightSavingTime: boolean | null;
}
export const TimeZoneEntity = defineEntity<TimeZoneSnapshot>(EntityKind.TimeZone, false);
export interface AndroidBuildSnapshot extends DeviceSnapshot {
  /** Android API 수준 */
  readonly apiLevel: number | null;
  /** 플랫폼이 공개하는 보안 패치 날짜 */
  readonly securityPatch: string | null;
  /** 빌드 ID */
  readonly buildId: string | null;
  /** 표시용 빌드 문자열 */
  readonly buildDisplay: string | null;
  /** OS 빌드를 식별하는 fingerprint */
  readonly buildFingerprint: string | null;
  /** 빌드 유형 */
  readonly buildType: string | null;
  /** 빌드 태그 */
  readonly buildTags: ReadonlyArray<string> | null;
  /** 부트로더 버전 */
  readonly bootloaderVersion: string | null;
}
export const AndroidBuildEntity = defineEntity<AndroidBuildSnapshot>(EntityKind.AndroidBuild, false);
export interface AndroidIdentitySnapshot extends DeviceSnapshot {
  /** 플랫폼이 제공하는 ANDROID_ID */
  readonly androidId: string | null;
}
export const AndroidIdentityEntity = defineEntity<AndroidIdentitySnapshot>(EntityKind.AndroidIdentity, false);
export interface AppleVendorIdentitySnapshot extends DeviceSnapshot {
  /** vendor 범위의 식별자 */
  readonly vendorId: string | null;
}
export const AppleVendorIdentityEntity = defineEntity<AppleVendorIdentitySnapshot>(EntityKind.AppleVendorIdentity, false);
export interface WindowsPublisherIdentitySnapshot extends DeviceSnapshot {
  /** publisher 범위의 시스템 식별자 */
  readonly publisherId: string | null;
  /** 식별자 생성에 사용된 플랫폼 소스 */
  readonly source: WindowsIdentitySource | null;
}
export const WindowsPublisherIdentityEntity = defineEntity<WindowsPublisherIdentitySnapshot>(EntityKind.WindowsPublisherIdentity, false);
export interface MacPlatformIdentitySnapshot extends DeviceSnapshot {
  /** 플랫폼 UUID */
  readonly platformUuid: string | null;
}
export const MacPlatformIdentityEntity = defineEntity<MacPlatformIdentitySnapshot>(EntityKind.MacPlatformIdentity, false);
export interface HardwareSerialSnapshot extends DeviceSnapshot {
  /** 플랫폼이 허용해 공개하는 하드웨어 일련번호 */
  readonly serial: string | null;
}
export const HardwareSerialEntity = defineEntity<HardwareSerialSnapshot>(EntityKind.HardwareSerial, false);
export interface TelephonyIdentitySnapshot extends DeviceSnapshot {
  /** 접근이 허용된 IMEI */
  readonly imei: string | null;
  /** 접근이 허용된 MEID */
  readonly meid: string | null;
}
export const TelephonyIdentityEntity = defineEntity<TelephonyIdentitySnapshot>(EntityKind.TelephonyIdentity, true);
export interface DisplaySnapshot extends DeviceSnapshot {
  /** 화면 표시 이름 */
  readonly label: string | null;
  /** 기본 화면 여부 */
  readonly primary: boolean | null;
  /** 내장 화면 여부 */
  readonly internal: boolean | null;
  /** 화면의 전원·표시 상태 */
  readonly state: DisplayState | null;
  /** 화면의 논리 좌표 영역 */
  readonly logicalBounds: Rect | null;
  /** 사용 가능한 작업 영역 */
  readonly workAreaBounds: Rect | null;
  /** 픽셀 크기 */
  readonly pixelSize: Size<number> | null;
  /** 물리 크기 mm */
  readonly physicalSizeMillimeters: Size<number> | null;
  /** 화면 방향 */
  readonly orientation: DisplayOrientation | null;
  /** 기준 방향에 대한 회전 각도 */
  readonly rotationDegrees: number | null;
  /** 논리 단위와 픽셀 사이 배율 */
  readonly scaleFactor: number | null;
  /** 인치당 픽셀 밀도 */
  readonly densityDpi: number | null;
  /** 현재 화면 모드 */
  readonly currentMode: DisplayMode | null;
  /** 지원 화면 모드 목록 */
  readonly supportedModes: ReadonlyArray<DisplayMode> | null;
  /** 플랫폼이 공개하는 최대 주사율 */
  readonly maximumRefreshRateHz: number | null;
  /** 플랫폼이 보고하는 색 깊이 */
  readonly colorDepthBits: number | null;
  /** 플랫폼이 보고하는 화면 색역 */
  readonly colorGamut: ColorGamut | null;
  /** 지원 HDR 형식 집합 */
  readonly hdrFormats: ReadonlySet<HdrFormat> | null;
  /** 밝기 0–1 */
  readonly brightness: number | null;
}
export const DisplayEntity = defineEntity<DisplaySnapshot>(EntityKind.Display, true);
export interface ViewportSnapshot extends DeviceSnapshot {
  /** 레이아웃 뷰포트 크기 */
  readonly size: Size<number> | null;
  /** 현재 보이는 뷰포트 크기 */
  readonly visualViewportSize: Size<number> | null;
  /** 시각 뷰포트 확대 배율 */
  readonly visualViewportScale: number | null;
  /** 안전 영역 여백 */
  readonly safeAreaInsets: Insets | null;
  /** 텍스트 확대 배율 */
  readonly textScaleFactor: number | null;
}
export const ViewportEntity = defineEntity<ViewportSnapshot>(EntityKind.Viewport, true);
export interface PowerSnapshot extends DeviceSnapshot {
  /** 전원 공급원 */
  readonly powerSource: PowerSource | null;
  /** 절전 모드 적용 여부 */
  readonly powerSaveMode: boolean | null;
  /** 플랫폼별 열 상태 타입의 합집합 */
  readonly thermalState: ThermalState | null;
}
export const PowerEntity = defineEntity<PowerSnapshot>(EntityKind.Power, false);
export interface BatterySnapshot extends DeviceSnapshot {
  /** 배터리 존재 여부 */
  readonly present: boolean | null;
  /** 충전 잔량 비율 0–1 */
  readonly level: number | null;
  /** 충전 중 여부 */
  readonly charging: boolean | null;
  /** 충전·방전 등 상태 */
  readonly state: BatteryState | null;
  /** 완충까지 남은 시간 */
  readonly timeToFull: Duration | null;
  /** 소진까지 남은 시간 */
  readonly timeToEmpty: Duration | null;
  /** 전압 mV */
  readonly voltageMillivolts: number | null;
  /** 현재 전류 μA */
  readonly currentMicroamps: number | null;
  /** 평균 전류 μA */
  readonly averageCurrentMicroamps: number | null;
  /** 충전·방전 전력 mW */
  readonly chargeRateMilliwatts: number | null;
  /** 배터리 온도 °C */
  readonly temperatureCelsius: number | null;
  /** 전하량 μAh */
  readonly chargeCounterMicroampHours: bigint | null;
  /** 남은 에너지 mWh */
  readonly remainingEnergyMilliwattHours: number | null;
  /** 현재 완충 용량 mWh */
  readonly fullChargeEnergyMilliwattHours: number | null;
  /** 설계 용량 mWh */
  readonly designEnergyMilliwattHours: number | null;
  /** 배터리 기술·화학 종류 */
  readonly technology: string | null;
  /** 플랫폼이 보고하는 상태·고장 종류 */
  readonly health: BatteryHealth | null;
  /** 충전 사이클 수 */
  readonly cycleCount: bigint | null;
}
export const BatteryEntity = defineEntity<BatterySnapshot>(EntityKind.Battery, true);
export interface NetworkPathSnapshot extends DeviceSnapshot {
  /** 로컬 연결 경로 상태 */
  readonly connectionState: ConnectionState | null;
  /** 경로에 사용되는 전송 수단 집합 */
  readonly transports: ReadonlySet<NetworkTransport> | null;
  /** 사용량 제한·종량제 네트워크 여부 */
  readonly metered: boolean | null;
  /** 플랫폼이 비용이 큰 경로로 분류하는지 여부 */
  readonly expensive: boolean | null;
  /** 플랫폼의 제한된 데이터 모드 여부 */
  readonly constrained: boolean | null;
  /** 사용자의 데이터 절약 선호 */
  readonly saveData: boolean | null;
  /** 경로의 IPv4 지원 여부 */
  readonly supportsIpv4: boolean | null;
  /** 경로의 IPv6 지원 여부 */
  readonly supportsIpv6: boolean | null;
  /** 경로의 DNS 지원 여부 */
  readonly supportsDns: boolean | null;
  /** OS가 보고하는 인터넷 검증 상태 */
  readonly internetValidated: boolean | null;
  /** OS가 보고하는 captive portal 상태 */
  readonly captivePortal: boolean | null;
}
export const NetworkPathEntity = defineEntity<NetworkPathSnapshot>(EntityKind.NetworkPath, false);
export interface NetworkPerformanceSnapshot extends DeviceSnapshot {
  /** 하향 전송 속도 bit/s */
  readonly downlinkBps: number | null;
  /** 상향 전송 속도 bit/s */
  readonly uplinkBps: number | null;
  /** 왕복 시간 */
  readonly roundTripTime: Duration | null;
  /** 플랫폼의 네트워크 성능 분류 */
  readonly effectiveType: EffectiveConnectionType | null;
  /** 브라우저가 보고하는 온라인 상태 */
  readonly browserOnline: boolean | null;
}
export const NetworkPerformanceEntity = defineEntity<NetworkPerformanceSnapshot>(EntityKind.NetworkPerformance, false);
export interface NetworkInterfaceSnapshot extends DeviceSnapshot {
  /** 인터페이스 이름 */
  readonly name: string | null;
  /** 인터페이스 종류 */
  readonly interfaceType: NetworkInterfaceType | null;
  /** 인터페이스 동작 상태 */
  readonly operationalState: NetworkOperationalState | null;
  /** 플랫폼이 허용해 공개하는 하드웨어 주소 */
  readonly hardwareAddress: string | null;
  /** 인터페이스 IP 주소 정보 */
  readonly ipAddresses: ReadonlyArray<IpAddressInfo> | null;
  /** DNS 서버 주소 목록 */
  readonly dnsServers: ReadonlyArray<IpAddress> | null;
  /** 게이트웨이 주소 목록 */
  readonly gateways: ReadonlyArray<IpAddress> | null;
  /** 경로 정보 목록 */
  readonly routes: ReadonlyArray<NetworkRoute> | null;
  /** MTU byte 크기 */
  readonly mtuBytes: bigint | null;
}
export const NetworkInterfaceEntity = defineEntity<NetworkInterfaceSnapshot>(EntityKind.NetworkInterface, true);
export interface WifiConnectionSnapshot extends DeviceSnapshot {
  /** 현재 연결 SSID */
  readonly ssid: string | null;
  /** 현재 연결 BSSID */
  readonly bssid: string | null;
  /** 현재 연결에서 선택된 인증 방식 */
  readonly security: WifiSecurity | null;
  /** 수신 신호 세기 dBm */
  readonly rssiDbm: number | null;
  /** 현재 연결 주파수 Hz */
  readonly frequencyHz: number | null;
  /** 수신 링크 속도 bit/s */
  readonly receiveLinkSpeedBps: number | null;
  /** 송신 링크 속도 bit/s */
  readonly transmitLinkSpeedBps: number | null;
}
export const WifiConnectionEntity = defineEntity<WifiConnectionSnapshot>(EntityKind.WifiConnection, true);
export interface CellularSubscriptionSnapshot extends DeviceSnapshot {
  /** 슬롯 인덱스 */
  readonly slotIndex: number | null;
  /** 통신사 이름 */
  readonly carrierName: string | null;
  /** 플랫폼이 보고하는 국가 코드 */
  readonly countryCode: string | null;
  /** MCC. 앞자리 0을 보존하는 문자열 */
  readonly mobileCountryCode: string | null;
  /** MNC. 앞자리 0을 보존하는 문자열 */
  readonly mobileNetworkCode: string | null;
  /** 현재 데이터 연결의 무선 기술 */
  readonly radioTechnology: RadioTechnology | null;
  /** 로밍 여부 */
  readonly roaming: boolean | null;
}
export const CellularSubscriptionEntity = defineEntity<CellularSubscriptionSnapshot>(EntityKind.CellularSubscription, true);
export interface StorageVolumeSnapshot extends DeviceSnapshot {
  /** 볼륨 이름 */
  readonly name: string | null;
  /** 파일 시스템 */
  readonly fileSystem: string | null;
  /** 볼륨 전체 용량 */
  readonly totalBytes: bigint | null;
  /** 볼륨의 빈 공간 */
  readonly freeBytes: bigint | null;
  /** 현재 호출자가 사용할 수 있는 여유 공간 */
  readonly availableToCallerBytes: bigint | null;
  /** 할당량 등 호출자 제한을 반영한 전체 용량 */
  readonly totalBytesForCaller: bigint | null;
  /** 읽기 전용 여부 */
  readonly readOnly: boolean | null;
  /** 이동식 여부 */
  readonly removable: boolean | null;
  /** 암호화 여부 */
  readonly encrypted: boolean | null;
  /** 이름의 대소문자 구분 여부 */
  readonly caseSensitive: boolean | null;
  /** 플랫폼이 중요한 용도에 제공하는 가용량 */
  readonly availableForImportantUsageBytes: bigint | null;
  /** 플랫폼이 기회적 용도에 제공하는 가용량 */
  readonly availableForOpportunisticUsageBytes: bigint | null;
  /** 플랫폼이 할당 가능하다고 보고하는 용량 */
  readonly allocatableBytes: bigint | null;
}
export const StorageVolumeEntity = defineEntity<StorageVolumeSnapshot>(EntityKind.StorageVolume, true);
export interface OriginStorageSnapshot extends DeviceSnapshot {
  /** origin 저장 한도 */
  readonly quotaBytes: bigint | null;
  /** origin 사용량 */
  readonly usageBytes: bigint | null;
  /** 플랫폼이 공개하는 저장 유형별 사용량 */
  readonly usageByCategory: Readonly<Partial<Record<StorageCategory, bigint>>> | null;
  /** 영구 저장 권한·상태 */
  readonly persistent: boolean | null;
}
export const OriginStorageEntity = defineEntity<OriginStorageSnapshot>(EntityKind.OriginStorage, false);
export interface AccelerometerSnapshot extends DeviceSnapshot {
  /** 중력을 포함한 가속도 */
  readonly value: Vector3 | null;
}
export const AccelerometerEntity = defineEntity<AccelerometerSnapshot>(EntityKind.Accelerometer, true);
export interface LinearAccelerationSnapshot extends DeviceSnapshot {
  /** 중력을 제외한 가속도 */
  readonly value: Vector3 | null;
}
export const LinearAccelerationEntity = defineEntity<LinearAccelerationSnapshot>(EntityKind.LinearAcceleration, true);
export interface GravitySnapshot extends DeviceSnapshot {
  /** 중력 벡터 */
  readonly value: Vector3 | null;
}
export const GravityEntity = defineEntity<GravitySnapshot>(EntityKind.Gravity, true);
export interface GyroscopeSnapshot extends DeviceSnapshot {
  /** 각속도 */
  readonly value: Vector3 | null;
}
export const GyroscopeEntity = defineEntity<GyroscopeSnapshot>(EntityKind.Gyroscope, true);
export interface MagnetometerSnapshot extends DeviceSnapshot {
  /** 자기장 */
  readonly value: Vector3 | null;
}
export const MagnetometerEntity = defineEntity<MagnetometerSnapshot>(EntityKind.Magnetometer, true);
export interface RelativeOrientationSnapshot extends DeviceSnapshot {
  /** 수집 세션의 상대 기준에 대한 자세 */
  readonly value: Quaternion | null;
}
export const RelativeOrientationEntity = defineEntity<RelativeOrientationSnapshot>(EntityKind.RelativeOrientation, true);
export interface AbsoluteOrientationSnapshot extends DeviceSnapshot {
  /** 동쪽·자기북·위쪽 기준에 대한 자세 */
  readonly value: Quaternion | null;
}
export const AbsoluteOrientationEntity = defineEntity<AbsoluteOrientationSnapshot>(EntityKind.AbsoluteOrientation, true);
export interface IlluminanceSnapshot extends DeviceSnapshot {
  /** 조도 */
  readonly value: number | null;
}
export const IlluminanceEntity = defineEntity<IlluminanceSnapshot>(EntityKind.Illuminance, true);
export interface PressureSnapshot extends DeviceSnapshot {
  /** 기압 */
  readonly value: number | null;
}
export const PressureEntity = defineEntity<PressureSnapshot>(EntityKind.Pressure, true);
export interface AmbientTemperatureSnapshot extends DeviceSnapshot {
  /** 주변 온도 */
  readonly value: number | null;
}
export const AmbientTemperatureEntity = defineEntity<AmbientTemperatureSnapshot>(EntityKind.AmbientTemperature, true);
export interface RelativeHumiditySnapshot extends DeviceSnapshot {
  /** 상대 습도 */
  readonly value: number | null;
}
export const RelativeHumidityEntity = defineEntity<RelativeHumiditySnapshot>(EntityKind.RelativeHumidity, true);
export interface ProximityNearSnapshot extends DeviceSnapshot {
  /** 근접 상태 */
  readonly value: boolean | null;
}
export const ProximityNearEntity = defineEntity<ProximityNearSnapshot>(EntityKind.ProximityNear, true);
export interface ProximityDistanceSnapshot extends DeviceSnapshot {
  /** 근접 대상까지의 거리 */
  readonly value: number | null;
}
export const ProximityDistanceEntity = defineEntity<ProximityDistanceSnapshot>(EntityKind.ProximityDistance, true);
export interface RelativeAltitudeSnapshot extends DeviceSnapshot {
  /** 수집 세션의 기준점 대비 상대 고도 */
  readonly value: number | null;
}
export const RelativeAltitudeEntity = defineEntity<RelativeAltitudeSnapshot>(EntityKind.RelativeAltitude, true);
export interface HingeAngleSnapshot extends DeviceSnapshot {
  /** 힌지 각도 */
  readonly value: number | null;
}
export const HingeAngleEntity = defineEntity<HingeAngleSnapshot>(EntityKind.HingeAngle, true);
export interface StepCountSinceBootSnapshot extends DeviceSnapshot {
  /** 부팅 기준 누적 걸음 수 */
  readonly value: bigint | null;
}
export const StepCountSinceBootEntity = defineEntity<StepCountSinceBootSnapshot>(EntityKind.StepCountSinceBoot, true);
export interface StepDetectedSnapshot extends DeviceSnapshot {
  /** 걸음 발생. false 초기 이벤트는 없음 */
  readonly value: boolean | null;
}
export const StepDetectedEntity = defineEntity<StepDetectedSnapshot>(EntityKind.StepDetected, true);
export interface SignificantMotionSnapshot extends DeviceSnapshot {
  /** 큰 움직임 발생. false 초기 이벤트는 없음 */
  readonly value: boolean | null;
}
export const SignificantMotionEntity = defineEntity<SignificantMotionSnapshot>(EntityKind.SignificantMotion, true);
export interface HumanPresenceSnapshot extends DeviceSnapshot {
  /** 사람 존재 여부 */
  readonly value: boolean | null;
}
export const HumanPresenceEntity = defineEntity<HumanPresenceSnapshot>(EntityKind.HumanPresence, true);
export interface SensorDescription extends DeviceSnapshot {
  /** 센서 종류 */
  readonly kind: SensorKind | null;
  /** 센서 이름 */
  readonly name: string | null;
  /** 제조사 */
  readonly vendor: string | null;
  /** 플랫폼이 보고하는 센서 버전 */
  readonly version: string | null;
  /** 원본 센서의 보고 모드 */
  readonly reportingMode: SensorReportingMode | null;
  /** 지원되는 최소 수집 간격 */
  readonly minimumInterval: Duration | null;
  /** 지원되는 최대 수집 간격 */
  readonly maximumInterval: Duration | null;
  /** 해당 센서 측정 단위의 최대 범위 */
  readonly maximumRange: number | null;
  /** 해당 센서 측정 단위의 분해능 */
  readonly resolution: number | null;
  /** 플랫폼이 보고하는 전류 소비 mA */
  readonly powerMilliamps: number | null;
  /** 플랫폼이 공개하는 FIFO 샘플 수용량 */
  readonly fifoCapacity: number | null;
}
