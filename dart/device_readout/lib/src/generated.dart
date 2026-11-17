// Generated from schema/device-readout.json and schema/enums.json.
part of 'core.dart';

enum FormFactor implements _WireEnum {
  phone('Phone'),
  tablet('Tablet'),
  laptop('Laptop'),
  desktop('Desktop'),
  television('Television'),
  watch('Watch'),
  automotive('Automotive'),
  headset('Headset');
  @override
  final String wireName;
  const FormFactor(this.wireName);
}

enum OsFamily implements _WireEnum {
  android('Android'),
  iOS('IOS'),
  iPadOS('IPadOS'),
  windows('Windows'),
  macOS('MacOS'),
  linux('Linux'),
  chromeOS('ChromeOS');
  @override
  final String wireName;
  const OsFamily(this.wireName);
}

enum Architecture implements _WireEnum {
  x86('X86'),
  x64('X64'),
  arm32('Arm32'),
  arm64('Arm64'),
  riscV32('RiscV32'),
  riscV64('RiscV64'),
  wasm32('Wasm32'),
  wasm64('Wasm64');
  @override
  final String wireName;
  const Architecture(this.wireName);
}

enum Abi implements _WireEnum {
  armeabiV7a('ArmeabiV7a'),
  arm64V8a('Arm64V8a'),
  x86('X86'),
  x86_64('X86_64');
  @override
  final String wireName;
  const Abi(this.wireName);
}

enum HourCycle implements _WireEnum {
  h11('H11'),
  h12('H12'),
  h23('H23'),
  h24('H24');
  @override
  final String wireName;
  const HourCycle(this.wireName);
}

enum Weekday implements _WireEnum {
  monday('Monday'),
  tuesday('Tuesday'),
  wednesday('Wednesday'),
  thursday('Thursday'),
  friday('Friday'),
  saturday('Saturday'),
  sunday('Sunday');
  @override
  final String wireName;
  const Weekday(this.wireName);
}

enum MeasurementSystem implements _WireEnum {
  metric('Metric'),
  uS('US'),
  uK('UK');
  @override
  final String wireName;
  const MeasurementSystem(this.wireName);
}

enum WindowsIdentitySource implements _WireEnum {
  tpm('Tpm'),
  uefi('Uefi'),
  registry('Registry');
  @override
  final String wireName;
  const WindowsIdentitySource(this.wireName);
}

enum DisplayState implements _WireEnum {
  on('On'),
  off('Off'),
  doze('Doze'),
  dozeSuspended('DozeSuspended'),
  onSuspended('OnSuspended');
  @override
  final String wireName;
  const DisplayState(this.wireName);
}

enum DisplayOrientation implements _WireEnum {
  portraitPrimary('PortraitPrimary'),
  portraitSecondary('PortraitSecondary'),
  landscapePrimary('LandscapePrimary'),
  landscapeSecondary('LandscapeSecondary');
  @override
  final String wireName;
  const DisplayOrientation(this.wireName);
}

enum ColorGamut implements _WireEnum {
  srgb('Srgb'),
  displayP3('DisplayP3'),
  rec2020('Rec2020');
  @override
  final String wireName;
  const ColorGamut(this.wireName);
}

enum HdrFormat implements _WireEnum {
  hdr10('Hdr10'),
  hdr10Plus('Hdr10Plus'),
  dolbyVision('DolbyVision'),
  hlg('Hlg');
  @override
  final String wireName;
  const HdrFormat(this.wireName);
}

enum PowerSource implements _WireEnum {
  battery('Battery'),
  external('External'),
  ups('Ups');
  @override
  final String wireName;
  const PowerSource(this.wireName);
}

enum AndroidThermalState implements _WireEnum, ThermalState {
  none('None'),
  light('Light'),
  moderate('Moderate'),
  severe('Severe'),
  critical('Critical'),
  emergency('Emergency'),
  shutdown('Shutdown');
  @override
  final String wireName;
  const AndroidThermalState(this.wireName);
}

enum AppleThermalState implements _WireEnum, ThermalState {
  nominal('Nominal'),
  fair('Fair'),
  serious('Serious'),
  critical('Critical');
  @override
  final String wireName;
  const AppleThermalState(this.wireName);
}

enum BatteryState implements _WireEnum {
  charging('Charging'),
  discharging('Discharging'),
  full('Full'),
  notCharging('NotCharging'),
  idle('Idle');
  @override
  final String wireName;
  const BatteryState(this.wireName);
}

enum BatteryHealth implements _WireEnum {
  good('Good'),
  overheated('Overheated'),
  cold('Cold'),
  dead('Dead'),
  overVoltage('OverVoltage'),
  unspecifiedFailure('UnspecifiedFailure');
  @override
  final String wireName;
  const BatteryHealth(this.wireName);
}

enum ConnectionState implements _WireEnum {
  connected('Connected'),
  disconnected('Disconnected'),
  connecting('Connecting'),
  disconnecting('Disconnecting'),
  suspended('Suspended'),
  connectionRequired('ConnectionRequired');
  @override
  final String wireName;
  const ConnectionState(this.wireName);
}

enum NetworkTransport implements _WireEnum {
  wifi('Wifi'),
  cellular('Cellular'),
  ethernet('Ethernet'),
  bluetooth('Bluetooth'),
  vpn('Vpn'),
  usb('Usb'),
  wifiAware('WifiAware'),
  lowpan('Lowpan'),
  thread('Thread'),
  satellite('Satellite');
  @override
  final String wireName;
  const NetworkTransport(this.wireName);
}

enum EffectiveConnectionType implements _WireEnum {
  slow2G('Slow2G'),
  type2G('Type2G'),
  type3G('Type3G'),
  type4G('Type4G');
  @override
  final String wireName;
  const EffectiveConnectionType(this.wireName);
}

enum NetworkInterfaceType implements _WireEnum {
  ethernet('Ethernet'),
  wifi('Wifi'),
  cellular('Cellular'),
  bluetooth('Bluetooth'),
  loopback('Loopback'),
  tunnel('Tunnel'),
  ppp('Ppp'),
  bridge('Bridge');
  @override
  final String wireName;
  const NetworkInterfaceType(this.wireName);
}

enum NetworkOperationalState implements _WireEnum {
  up('Up'),
  down('Down'),
  testing('Testing'),
  dormant('Dormant'),
  notPresent('NotPresent'),
  lowerLayerDown('LowerLayerDown');
  @override
  final String wireName;
  const NetworkOperationalState(this.wireName);
}

enum WifiSecurity implements _WireEnum {
  open('Open'),
  wep('Wep'),
  psk('Psk'),
  eap('Eap'),
  sae('Sae'),
  owe('Owe'),
  wapiPsk('WapiPsk'),
  wapiCert('WapiCert'),
  eapWpa3Enterprise('EapWpa3Enterprise'),
  eapWpa3Enterprise192Bit('EapWpa3Enterprise192Bit'),
  passpointR1R2('PasspointR1R2'),
  passpointR3('PasspointR3'),
  dpp('Dpp');
  @override
  final String wireName;
  const WifiSecurity(this.wireName);
}

enum RadioTechnology implements _WireEnum {
  gsm('Gsm'),
  gprs('Gprs'),
  edge('Edge'),
  cdma('Cdma'),
  cdma1x('Cdma1x'),
  evdo0('Evdo0'),
  evdoA('EvdoA'),
  evdoB('EvdoB'),
  ehrpd('Ehrpd'),
  umts('Umts'),
  hsdpa('Hsdpa'),
  hsupa('Hsupa'),
  hspa('Hspa'),
  hspaPlus('HspaPlus'),
  iden('Iden'),
  tdScdma('TdScdma'),
  lte('Lte'),
  lteCa('LteCa'),
  nr('Nr'),
  nrNsa('NrNsa'),
  nrSa('NrSa'),
  iwlan('Iwlan');
  @override
  final String wireName;
  const RadioTechnology(this.wireName);
}

enum StorageCategory implements _WireEnum {
  indexedDB('IndexedDB'),
  caches('Caches'),
  serviceWorker('ServiceWorker'),
  fileSystem('FileSystem'),
  localStorage('LocalStorage'),
  sessionStorage('SessionStorage');
  @override
  final String wireName;
  const StorageCategory(this.wireName);
}

enum SensorReportingMode implements _WireEnum {
  continuous('Continuous'),
  onChange('OnChange'),
  oneShot('OneShot'),
  specialTrigger('SpecialTrigger');
  @override
  final String wireName;
  const SensorReportingMode(this.wireName);
}

enum SensorKind implements _WireEnum {
  accelerometer('Accelerometer'),
  linearAcceleration('LinearAcceleration'),
  gravity('Gravity'),
  gyroscope('Gyroscope'),
  magnetometer('Magnetometer'),
  relativeOrientation('RelativeOrientation'),
  absoluteOrientation('AbsoluteOrientation'),
  illuminance('Illuminance'),
  pressure('Pressure'),
  ambientTemperature('AmbientTemperature'),
  relativeHumidity('RelativeHumidity'),
  proximityNear('ProximityNear'),
  proximityDistance('ProximityDistance'),
  relativeAltitude('RelativeAltitude'),
  hingeAngle('HingeAngle'),
  stepCountSinceBoot('StepCountSinceBoot'),
  stepDetected('StepDetected'),
  significantMotion('SignificantMotion'),
  humanPresence('HumanPresence');
  @override
  final String wireName;
  const SensorKind(this.wireName);
}

enum EntityKind { deviceInfo, os, runtime, cpu, cpuCore, ram, processMemory, locale, timeZone, androidBuild, androidIdentity, appleVendorIdentity, windowsPublisherIdentity, macPlatformIdentity, hardwareSerial, telephonyIdentity, display, viewport, power, battery, networkPath, networkPerformance, networkInterface, wifiConnection, cellularSubscription, storageVolume, originStorage, accelerometer, linearAcceleration, gravity, gyroscope, magnetometer, relativeOrientation, absoluteOrientation, illuminance, pressure, ambientTemperature, relativeHumidity, proximityNear, proximityDistance, relativeAltitude, hingeAngle, stepCountSinceBoot, stepDetected, significantMotion, humanPresence }

abstract final class Entities {
  static const deviceInfo = Entity<DeviceInfoSnapshot>._(EntityKind.deviceInfo, EntityMode.state, false);
  static const os = Entity<OsSnapshot>._(EntityKind.os, EntityMode.state, false);
  static const runtime = Entity<RuntimeSnapshot>._(EntityKind.runtime, EntityMode.state, false);
  static const cpu = Entity<CpuSnapshot>._(EntityKind.cpu, EntityMode.state, false);
  static const cpuCore = Entity<CpuCoreSnapshot>._(EntityKind.cpuCore, EntityMode.state, true);
  static const ram = Entity<RamSnapshot>._(EntityKind.ram, EntityMode.state, false);
  static const processMemory = Entity<ProcessMemorySnapshot>._(EntityKind.processMemory, EntityMode.state, false);
  static const locale = Entity<LocaleSnapshot>._(EntityKind.locale, EntityMode.state, false);
  static const timeZone = Entity<TimeZoneSnapshot>._(EntityKind.timeZone, EntityMode.state, false);
  static const androidBuild = Entity<AndroidBuildSnapshot>._(EntityKind.androidBuild, EntityMode.state, false);
  static const androidIdentity = Entity<AndroidIdentitySnapshot>._(EntityKind.androidIdentity, EntityMode.state, false);
  static const appleVendorIdentity = Entity<AppleVendorIdentitySnapshot>._(EntityKind.appleVendorIdentity, EntityMode.state, false);
  static const windowsPublisherIdentity = Entity<WindowsPublisherIdentitySnapshot>._(EntityKind.windowsPublisherIdentity, EntityMode.state, false);
  static const macPlatformIdentity = Entity<MacPlatformIdentitySnapshot>._(EntityKind.macPlatformIdentity, EntityMode.state, false);
  static const hardwareSerial = Entity<HardwareSerialSnapshot>._(EntityKind.hardwareSerial, EntityMode.state, false);
  static const telephonyIdentity = Entity<TelephonyIdentitySnapshot>._(EntityKind.telephonyIdentity, EntityMode.state, true);
  static const display = Entity<DisplaySnapshot>._(EntityKind.display, EntityMode.state, true);
  static const viewport = Entity<ViewportSnapshot>._(EntityKind.viewport, EntityMode.state, true);
  static const power = Entity<PowerSnapshot>._(EntityKind.power, EntityMode.state, false);
  static const battery = Entity<BatterySnapshot>._(EntityKind.battery, EntityMode.state, true);
  static const networkPath = Entity<NetworkPathSnapshot>._(EntityKind.networkPath, EntityMode.state, false);
  static const networkPerformance = Entity<NetworkPerformanceSnapshot>._(EntityKind.networkPerformance, EntityMode.state, false);
  static const networkInterface = Entity<NetworkInterfaceSnapshot>._(EntityKind.networkInterface, EntityMode.state, true);
  static const wifiConnection = Entity<WifiConnectionSnapshot>._(EntityKind.wifiConnection, EntityMode.state, true);
  static const cellularSubscription = Entity<CellularSubscriptionSnapshot>._(EntityKind.cellularSubscription, EntityMode.state, true);
  static const storageVolume = Entity<StorageVolumeSnapshot>._(EntityKind.storageVolume, EntityMode.state, true);
  static const originStorage = Entity<OriginStorageSnapshot>._(EntityKind.originStorage, EntityMode.state, false);
  static const accelerometer = Entity<AccelerometerSnapshot>._(EntityKind.accelerometer, EntityMode.sample, true);
  static const linearAcceleration = Entity<LinearAccelerationSnapshot>._(EntityKind.linearAcceleration, EntityMode.sample, true);
  static const gravity = Entity<GravitySnapshot>._(EntityKind.gravity, EntityMode.sample, true);
  static const gyroscope = Entity<GyroscopeSnapshot>._(EntityKind.gyroscope, EntityMode.sample, true);
  static const magnetometer = Entity<MagnetometerSnapshot>._(EntityKind.magnetometer, EntityMode.sample, true);
  static const relativeOrientation = Entity<RelativeOrientationSnapshot>._(EntityKind.relativeOrientation, EntityMode.sample, true);
  static const absoluteOrientation = Entity<AbsoluteOrientationSnapshot>._(EntityKind.absoluteOrientation, EntityMode.sample, true);
  static const illuminance = Entity<IlluminanceSnapshot>._(EntityKind.illuminance, EntityMode.sample, true);
  static const pressure = Entity<PressureSnapshot>._(EntityKind.pressure, EntityMode.sample, true);
  static const ambientTemperature = Entity<AmbientTemperatureSnapshot>._(EntityKind.ambientTemperature, EntityMode.sample, true);
  static const relativeHumidity = Entity<RelativeHumiditySnapshot>._(EntityKind.relativeHumidity, EntityMode.sample, true);
  static const proximityNear = Entity<ProximityNearSnapshot>._(EntityKind.proximityNear, EntityMode.sample, true);
  static const proximityDistance = Entity<ProximityDistanceSnapshot>._(EntityKind.proximityDistance, EntityMode.sample, true);
  static const relativeAltitude = Entity<RelativeAltitudeSnapshot>._(EntityKind.relativeAltitude, EntityMode.sample, true);
  static const hingeAngle = Entity<HingeAngleSnapshot>._(EntityKind.hingeAngle, EntityMode.sample, true);
  static const stepCountSinceBoot = Entity<StepCountSinceBootSnapshot>._(EntityKind.stepCountSinceBoot, EntityMode.sample, true);
  static const stepDetected = Entity<StepDetectedSnapshot>._(EntityKind.stepDetected, EntityMode.event, true);
  static const significantMotion = Entity<SignificantMotionSnapshot>._(EntityKind.significantMotion, EntityMode.event, true);
  static const humanPresence = Entity<HumanPresenceSnapshot>._(EntityKind.humanPresence, EntityMode.sample, true);
}

SensorKind? _sensorKind(EntityKind kind) => switch (kind) {
  EntityKind.accelerometer => SensorKind.accelerometer,
  EntityKind.linearAcceleration => SensorKind.linearAcceleration,
  EntityKind.gravity => SensorKind.gravity,
  EntityKind.gyroscope => SensorKind.gyroscope,
  EntityKind.magnetometer => SensorKind.magnetometer,
  EntityKind.relativeOrientation => SensorKind.relativeOrientation,
  EntityKind.absoluteOrientation => SensorKind.absoluteOrientation,
  EntityKind.illuminance => SensorKind.illuminance,
  EntityKind.pressure => SensorKind.pressure,
  EntityKind.ambientTemperature => SensorKind.ambientTemperature,
  EntityKind.relativeHumidity => SensorKind.relativeHumidity,
  EntityKind.proximityNear => SensorKind.proximityNear,
  EntityKind.proximityDistance => SensorKind.proximityDistance,
  EntityKind.relativeAltitude => SensorKind.relativeAltitude,
  EntityKind.hingeAngle => SensorKind.hingeAngle,
  EntityKind.stepCountSinceBoot => SensorKind.stepCountSinceBoot,
  EntityKind.stepDetected => SensorKind.stepDetected,
  EntityKind.significantMotion => SensorKind.significantMotion,
  EntityKind.humanPresence => SensorKind.humanPresence,
  _ => null,
};

final class DeviceInfoSnapshot extends DeviceSnapshot {
  /// 제조사
  final String? manufacturer;
  /// 브랜드
  final String? brand;
  /// 플랫폼의 모델 코드
  final String? modelCode;
  /// 사용자에게 표시할 모델 이름
  final String? modelName;
  /// OS가 공개하는 기기 이름
  final String? deviceName;
  /// 휴대전화·태블릿·노트북 등 기기 형태
  final FormFactor? formFactor;
  /// 제품 식별 이름
  final String? product;
  /// 보드 식별 이름
  final String? board;
  DeviceInfoSnapshot({super.collectedAt,
    this.manufacturer,
    this.brand,
    this.modelCode,
    this.modelName,
    this.deviceName,
    this.formFactor,
    this.product,
    this.board,
  });
  DeviceInfoSnapshot._completed(DeviceInfoSnapshot snapshot)
    : manufacturer = snapshot.manufacturer,
      brand = snapshot.brand,
      modelCode = snapshot.modelCode,
      modelName = snapshot.modelName,
      deviceName = snapshot.deviceName,
      formFactor = snapshot.formFactor,
      product = snapshot.product,
      board = snapshot.board,
      super._completed();
  @override
  DeviceInfoSnapshot _collected() => DeviceInfoSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.deviceInfo;
  @override
  Map<String, Object?> _fields() => {
    'manufacturer': manufacturer,
    'brand': brand,
    'modelCode': modelCode,
    'modelName': modelName,
    'deviceName': deviceName,
    'formFactor': formFactor,
    'product': product,
    'board': board,
  };
}

final class OsSnapshot extends DeviceSnapshot {
  /// 운영체제 계열
  final OsFamily? family;
  /// 운영체제 이름
  final String? name;
  /// 운영체제 버전
  final String? version;
  /// 운영체제 빌드
  final String? build;
  /// 커널 이름
  final String? kernelName;
  /// 커널 버전
  final String? kernelVersion;
  OsSnapshot({super.collectedAt,
    this.family,
    this.name,
    this.version,
    this.build,
    this.kernelName,
    this.kernelVersion,
  });
  OsSnapshot._completed(OsSnapshot snapshot)
    : family = snapshot.family,
      name = snapshot.name,
      version = snapshot.version,
      build = snapshot.build,
      kernelName = snapshot.kernelName,
      kernelVersion = snapshot.kernelVersion,
      super._completed();
  @override
  OsSnapshot _collected() => OsSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.os;
  @override
  Map<String, Object?> _fields() => {
    'family': family,
    'name': name,
    'version': version,
    'build': build,
    'kernelName': kernelName,
    'kernelVersion': kernelVersion,
  };
}

final class RuntimeSnapshot extends DeviceSnapshot {
  /// 호스트 시스템 아키텍처
  final Architecture? hostArchitecture;
  /// 현재 프로세스 아키텍처
  final Architecture? processArchitecture;
  /// 현재 프로세스 비트 수
  final int? processBitness;
  /// 플랫폼이 공개하는 지원 ABI 집합
  final Set<Abi>? supportedAbis;
  RuntimeSnapshot({super.collectedAt,
    this.hostArchitecture,
    this.processArchitecture,
    this.processBitness,
    Set<Abi>? supportedAbis,
  }) : supportedAbis = supportedAbis == null ? null : Set.unmodifiable(supportedAbis);
  RuntimeSnapshot._completed(RuntimeSnapshot snapshot)
    : hostArchitecture = snapshot.hostArchitecture,
      processArchitecture = snapshot.processArchitecture,
      processBitness = snapshot.processBitness,
      supportedAbis = snapshot.supportedAbis,
      super._completed();
  @override
  RuntimeSnapshot _collected() => RuntimeSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.runtime;
  @override
  Map<String, Object?> _fields() => {
    'hostArchitecture': hostArchitecture,
    'processArchitecture': processArchitecture,
    'processBitness': processBitness,
    'supportedAbis': supportedAbis,
  };
}

final class CpuSnapshot extends DeviceSnapshot {
  /// CPU 모델
  final String? model;
  /// CPU 제조사
  final String? manufacturer;
  /// SoC 모델
  final String? socModel;
  /// SoC 제조사
  final String? socManufacturer;
  /// 전체 논리 프로세서 수
  final int? logicalProcessorCount;
  /// 현재 실행 환경에 제공되는 논리 프로세서 수
  final int? availableLogicalProcessorCount;
  /// 물리 코어 수
  final int? physicalCoreCount;
  /// 프로세서 패키지 수
  final int? processorPackageCount;
  CpuSnapshot({super.collectedAt,
    this.model,
    this.manufacturer,
    this.socModel,
    this.socManufacturer,
    this.logicalProcessorCount,
    this.availableLogicalProcessorCount,
    this.physicalCoreCount,
    this.processorPackageCount,
  });
  CpuSnapshot._completed(CpuSnapshot snapshot)
    : model = snapshot.model,
      manufacturer = snapshot.manufacturer,
      socModel = snapshot.socModel,
      socManufacturer = snapshot.socManufacturer,
      logicalProcessorCount = snapshot.logicalProcessorCount,
      availableLogicalProcessorCount = snapshot.availableLogicalProcessorCount,
      physicalCoreCount = snapshot.physicalCoreCount,
      processorPackageCount = snapshot.processorPackageCount,
      super._completed();
  @override
  CpuSnapshot _collected() => CpuSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.cpu;
  @override
  Map<String, Object?> _fields() => {
    'model': model,
    'manufacturer': manufacturer,
    'socModel': socModel,
    'socManufacturer': socManufacturer,
    'logicalProcessorCount': logicalProcessorCount,
    'availableLogicalProcessorCount': availableLogicalProcessorCount,
    'physicalCoreCount': physicalCoreCount,
    'processorPackageCount': processorPackageCount,
  };
}

final class CpuCoreSnapshot extends DeviceSnapshot {
  /// 논리 프로세서 인덱스
  final int? logicalIndex;
  /// 소속 물리 코어 인덱스
  final int? coreIndex;
  /// 소속 프로세서 패키지 인덱스
  final int? packageIndex;
  /// OS에서 사용 가능한 온라인 상태
  final bool? online;
  /// 현재 클록 주파수
  final double? currentClockHz;
  /// 플랫폼이 보고하는 최대 클록 주파수
  final double? maximumClockHz;
  CpuCoreSnapshot({super.collectedAt,
    this.logicalIndex,
    this.coreIndex,
    this.packageIndex,
    this.online,
    this.currentClockHz,
    this.maximumClockHz,
  });
  CpuCoreSnapshot._completed(CpuCoreSnapshot snapshot)
    : logicalIndex = snapshot.logicalIndex,
      coreIndex = snapshot.coreIndex,
      packageIndex = snapshot.packageIndex,
      online = snapshot.online,
      currentClockHz = snapshot.currentClockHz,
      maximumClockHz = snapshot.maximumClockHz,
      super._completed();
  @override
  CpuCoreSnapshot _collected() => CpuCoreSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.cpuCore;
  @override
  Map<String, Object?> _fields() => {
    'logicalIndex': logicalIndex,
    'coreIndex': coreIndex,
    'packageIndex': packageIndex,
    'online': online,
    'currentClockHz': currentClockHz,
    'maximumClockHz': maximumClockHz,
  };
}

final class RamSnapshot extends DeviceSnapshot {
  /// 설치된 물리 RAM 용량
  final BigInt? physicalBytes;
  /// 커널이 접근 가능한 RAM 용량
  final BigInt? kernelAccessibleBytes;
  /// 플랫폼이 외부에 공개하는 표기용 RAM 용량
  final BigInt? advertisedBytes;
  /// OS 정의상 사용 가능한 메모리
  final BigInt? availableBytes;
  /// OS 정의상 비어 있는 메모리
  final BigInt? freeBytes;
  /// OS가 보고하는 메모리 부족 상태
  final bool? lowMemory;
  /// OS가 공개하는 메모리 부족 기준 용량
  final BigInt? lowMemoryThresholdBytes;
  RamSnapshot({super.collectedAt,
    this.physicalBytes,
    this.kernelAccessibleBytes,
    this.advertisedBytes,
    this.availableBytes,
    this.freeBytes,
    this.lowMemory,
    this.lowMemoryThresholdBytes,
  });
  RamSnapshot._completed(RamSnapshot snapshot)
    : physicalBytes = snapshot.physicalBytes,
      kernelAccessibleBytes = snapshot.kernelAccessibleBytes,
      advertisedBytes = snapshot.advertisedBytes,
      availableBytes = snapshot.availableBytes,
      freeBytes = snapshot.freeBytes,
      lowMemory = snapshot.lowMemory,
      lowMemoryThresholdBytes = snapshot.lowMemoryThresholdBytes,
      super._completed();
  @override
  RamSnapshot _collected() => RamSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.ram;
  @override
  Map<String, Object?> _fields() => {
    'physicalBytes': physicalBytes,
    'kernelAccessibleBytes': kernelAccessibleBytes,
    'advertisedBytes': advertisedBytes,
    'availableBytes': availableBytes,
    'freeBytes': freeBytes,
    'lowMemory': lowMemory,
    'lowMemoryThresholdBytes': lowMemoryThresholdBytes,
  };
}

final class ProcessMemorySnapshot extends DeviceSnapshot {
  /// 현재 앱이 추가로 할당할 수 있다고 플랫폼이 보고하는 메모리
  final BigInt? allocationRemainingBytes;
  ProcessMemorySnapshot({super.collectedAt,
    this.allocationRemainingBytes,
  });
  ProcessMemorySnapshot._completed(ProcessMemorySnapshot snapshot)
    : allocationRemainingBytes = snapshot.allocationRemainingBytes,
      super._completed();
  @override
  ProcessMemorySnapshot _collected() => ProcessMemorySnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.processMemory;
  @override
  Map<String, Object?> _fields() => {
    'allocationRemainingBytes': allocationRemainingBytes,
  };
}

final class LocaleSnapshot extends DeviceSnapshot {
  /// 현재 유효한 언어 태그
  final String? currentLanguageTag;
  /// 선호 언어 태그. 원래 우선순위 보존
  final List<String>? preferredLanguageTags;
  /// 시스템 언어 태그 목록
  final List<String>? systemLanguageTags;
  /// 앱에 적용된 언어 태그 목록
  final List<String>? appLanguageTags;
  /// 로케일 지역 코드
  final String? regionCode;
  /// 문자 체계 코드
  final String? scriptCode;
  /// 달력 체계 식별자
  final String? calendar;
  /// 숫자 표기 체계 식별자
  final String? numberingSystem;
  /// 시간 표기 주기
  final HourCycle? hourCycle;
  /// 한 주의 첫 요일
  final Weekday? firstWeekday;
  /// 도량형 체계
  final MeasurementSystem? measurementSystem;
  LocaleSnapshot({super.collectedAt,
    this.currentLanguageTag,
    List<String>? preferredLanguageTags,
    List<String>? systemLanguageTags,
    List<String>? appLanguageTags,
    this.regionCode,
    this.scriptCode,
    this.calendar,
    this.numberingSystem,
    this.hourCycle,
    this.firstWeekday,
    this.measurementSystem,
  }) : preferredLanguageTags = preferredLanguageTags == null ? null : List.unmodifiable(preferredLanguageTags),
      systemLanguageTags = systemLanguageTags == null ? null : List.unmodifiable(systemLanguageTags),
      appLanguageTags = appLanguageTags == null ? null : List.unmodifiable(appLanguageTags);
  LocaleSnapshot._completed(LocaleSnapshot snapshot)
    : currentLanguageTag = snapshot.currentLanguageTag,
      preferredLanguageTags = snapshot.preferredLanguageTags,
      systemLanguageTags = snapshot.systemLanguageTags,
      appLanguageTags = snapshot.appLanguageTags,
      regionCode = snapshot.regionCode,
      scriptCode = snapshot.scriptCode,
      calendar = snapshot.calendar,
      numberingSystem = snapshot.numberingSystem,
      hourCycle = snapshot.hourCycle,
      firstWeekday = snapshot.firstWeekday,
      measurementSystem = snapshot.measurementSystem,
      super._completed();
  @override
  LocaleSnapshot _collected() => LocaleSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.locale;
  @override
  Map<String, Object?> _fields() => {
    'currentLanguageTag': currentLanguageTag,
    'preferredLanguageTags': preferredLanguageTags,
    'systemLanguageTags': systemLanguageTags,
    'appLanguageTags': appLanguageTags,
    'regionCode': regionCode,
    'scriptCode': scriptCode,
    'calendar': calendar,
    'numberingSystem': numberingSystem,
    'hourCycle': hourCycle,
    'firstWeekday': firstWeekday,
    'measurementSystem': measurementSystem,
  };
}

final class TimeZoneSnapshot extends DeviceSnapshot {
  /// IANA 시간대 식별자
  final String? ianaId;
  /// Windows 시간대 식별자
  final String? windowsId;
  /// 수집 시점의 UTC 오프셋 초
  final int? utcOffsetSeconds;
  /// 수집 시점의 서머타임 적용 여부
  final bool? daylightSavingTime;
  TimeZoneSnapshot({super.collectedAt,
    this.ianaId,
    this.windowsId,
    this.utcOffsetSeconds,
    this.daylightSavingTime,
  });
  TimeZoneSnapshot._completed(TimeZoneSnapshot snapshot)
    : ianaId = snapshot.ianaId,
      windowsId = snapshot.windowsId,
      utcOffsetSeconds = snapshot.utcOffsetSeconds,
      daylightSavingTime = snapshot.daylightSavingTime,
      super._completed();
  @override
  TimeZoneSnapshot _collected() => TimeZoneSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.timeZone;
  @override
  Map<String, Object?> _fields() => {
    'ianaId': ianaId,
    'windowsId': windowsId,
    'utcOffsetSeconds': utcOffsetSeconds,
    'daylightSavingTime': daylightSavingTime,
  };
}

final class AndroidBuildSnapshot extends DeviceSnapshot {
  /// Android API 수준
  final int? apiLevel;
  /// 플랫폼이 공개하는 보안 패치 날짜
  final String? securityPatch;
  /// 빌드 ID
  final String? buildId;
  /// 표시용 빌드 문자열
  final String? buildDisplay;
  /// OS 빌드를 식별하는 fingerprint
  final String? buildFingerprint;
  /// 빌드 유형
  final String? buildType;
  /// 빌드 태그
  final List<String>? buildTags;
  /// 부트로더 버전
  final String? bootloaderVersion;
  AndroidBuildSnapshot({super.collectedAt,
    this.apiLevel,
    this.securityPatch,
    this.buildId,
    this.buildDisplay,
    this.buildFingerprint,
    this.buildType,
    List<String>? buildTags,
    this.bootloaderVersion,
  }) : buildTags = buildTags == null ? null : List.unmodifiable(buildTags);
  AndroidBuildSnapshot._completed(AndroidBuildSnapshot snapshot)
    : apiLevel = snapshot.apiLevel,
      securityPatch = snapshot.securityPatch,
      buildId = snapshot.buildId,
      buildDisplay = snapshot.buildDisplay,
      buildFingerprint = snapshot.buildFingerprint,
      buildType = snapshot.buildType,
      buildTags = snapshot.buildTags,
      bootloaderVersion = snapshot.bootloaderVersion,
      super._completed();
  @override
  AndroidBuildSnapshot _collected() => AndroidBuildSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.androidBuild;
  @override
  Map<String, Object?> _fields() => {
    'apiLevel': apiLevel,
    'securityPatch': securityPatch,
    'buildId': buildId,
    'buildDisplay': buildDisplay,
    'buildFingerprint': buildFingerprint,
    'buildType': buildType,
    'buildTags': buildTags,
    'bootloaderVersion': bootloaderVersion,
  };
}

final class AndroidIdentitySnapshot extends DeviceSnapshot {
  /// 플랫폼이 제공하는 ANDROID_ID
  final String? androidId;
  AndroidIdentitySnapshot({super.collectedAt,
    this.androidId,
  });
  AndroidIdentitySnapshot._completed(AndroidIdentitySnapshot snapshot)
    : androidId = snapshot.androidId,
      super._completed();
  @override
  AndroidIdentitySnapshot _collected() => AndroidIdentitySnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.androidIdentity;
  @override
  Map<String, Object?> _fields() => {
    'androidId': androidId,
  };
}

final class AppleVendorIdentitySnapshot extends DeviceSnapshot {
  /// vendor 범위의 식별자
  final String? vendorId;
  AppleVendorIdentitySnapshot({super.collectedAt,
    this.vendorId,
  });
  AppleVendorIdentitySnapshot._completed(AppleVendorIdentitySnapshot snapshot)
    : vendorId = snapshot.vendorId,
      super._completed();
  @override
  AppleVendorIdentitySnapshot _collected() => AppleVendorIdentitySnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.appleVendorIdentity;
  @override
  Map<String, Object?> _fields() => {
    'vendorId': vendorId,
  };
}

final class WindowsPublisherIdentitySnapshot extends DeviceSnapshot {
  /// publisher 범위의 시스템 식별자
  final String? publisherId;
  /// 식별자 생성에 사용된 플랫폼 소스
  final WindowsIdentitySource? source;
  WindowsPublisherIdentitySnapshot({super.collectedAt,
    this.publisherId,
    this.source,
  });
  WindowsPublisherIdentitySnapshot._completed(WindowsPublisherIdentitySnapshot snapshot)
    : publisherId = snapshot.publisherId,
      source = snapshot.source,
      super._completed();
  @override
  WindowsPublisherIdentitySnapshot _collected() => WindowsPublisherIdentitySnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.windowsPublisherIdentity;
  @override
  Map<String, Object?> _fields() => {
    'publisherId': publisherId,
    'source': source,
  };
}

final class MacPlatformIdentitySnapshot extends DeviceSnapshot {
  /// 플랫폼 UUID
  final String? platformUuid;
  MacPlatformIdentitySnapshot({super.collectedAt,
    this.platformUuid,
  });
  MacPlatformIdentitySnapshot._completed(MacPlatformIdentitySnapshot snapshot)
    : platformUuid = snapshot.platformUuid,
      super._completed();
  @override
  MacPlatformIdentitySnapshot _collected() => MacPlatformIdentitySnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.macPlatformIdentity;
  @override
  Map<String, Object?> _fields() => {
    'platformUuid': platformUuid,
  };
}

final class HardwareSerialSnapshot extends DeviceSnapshot {
  /// 플랫폼이 허용해 공개하는 하드웨어 일련번호
  final String? serial;
  HardwareSerialSnapshot({super.collectedAt,
    this.serial,
  });
  HardwareSerialSnapshot._completed(HardwareSerialSnapshot snapshot)
    : serial = snapshot.serial,
      super._completed();
  @override
  HardwareSerialSnapshot _collected() => HardwareSerialSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.hardwareSerial;
  @override
  Map<String, Object?> _fields() => {
    'serial': serial,
  };
}

final class TelephonyIdentitySnapshot extends DeviceSnapshot {
  /// 접근이 허용된 IMEI
  final String? imei;
  /// 접근이 허용된 MEID
  final String? meid;
  TelephonyIdentitySnapshot({super.collectedAt,
    this.imei,
    this.meid,
  });
  TelephonyIdentitySnapshot._completed(TelephonyIdentitySnapshot snapshot)
    : imei = snapshot.imei,
      meid = snapshot.meid,
      super._completed();
  @override
  TelephonyIdentitySnapshot _collected() => TelephonyIdentitySnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.telephonyIdentity;
  @override
  Map<String, Object?> _fields() => {
    'imei': imei,
    'meid': meid,
  };
}

final class DisplaySnapshot extends DeviceSnapshot {
  /// 화면 표시 이름
  final String? label;
  /// 기본 화면 여부
  final bool? primary;
  /// 내장 화면 여부
  final bool? internal;
  /// 화면의 전원·표시 상태
  final DisplayState? state;
  /// 화면의 논리 좌표 영역
  final Rect? logicalBounds;
  /// 사용 가능한 작업 영역
  final Rect? workAreaBounds;
  /// 픽셀 크기
  final Size<int>? pixelSize;
  /// 물리 크기 mm
  final Size<double>? physicalSizeMillimeters;
  /// 화면 방향
  final DisplayOrientation? orientation;
  /// 기준 방향에 대한 회전 각도
  final double? rotationDegrees;
  /// 논리 단위와 픽셀 사이 배율
  final double? scaleFactor;
  /// 인치당 픽셀 밀도
  final double? densityDpi;
  /// 현재 화면 모드
  final DisplayMode? currentMode;
  /// 지원 화면 모드 목록
  final List<DisplayMode>? supportedModes;
  /// 플랫폼이 공개하는 최대 주사율
  final double? maximumRefreshRateHz;
  /// 플랫폼이 보고하는 색 깊이
  final int? colorDepthBits;
  /// 플랫폼이 보고하는 화면 색역
  final ColorGamut? colorGamut;
  /// 지원 HDR 형식 집합
  final Set<HdrFormat>? hdrFormats;
  /// 밝기 0–1
  final double? brightness;
  DisplaySnapshot({super.collectedAt,
    this.label,
    this.primary,
    this.internal,
    this.state,
    this.logicalBounds,
    this.workAreaBounds,
    this.pixelSize,
    this.physicalSizeMillimeters,
    this.orientation,
    this.rotationDegrees,
    this.scaleFactor,
    this.densityDpi,
    this.currentMode,
    List<DisplayMode>? supportedModes,
    this.maximumRefreshRateHz,
    this.colorDepthBits,
    this.colorGamut,
    Set<HdrFormat>? hdrFormats,
    this.brightness,
  }) : supportedModes = supportedModes == null ? null : List.unmodifiable(supportedModes),
      hdrFormats = hdrFormats == null ? null : Set.unmodifiable(hdrFormats);
  DisplaySnapshot._completed(DisplaySnapshot snapshot)
    : label = snapshot.label,
      primary = snapshot.primary,
      internal = snapshot.internal,
      state = snapshot.state,
      logicalBounds = snapshot.logicalBounds,
      workAreaBounds = snapshot.workAreaBounds,
      pixelSize = snapshot.pixelSize,
      physicalSizeMillimeters = snapshot.physicalSizeMillimeters,
      orientation = snapshot.orientation,
      rotationDegrees = snapshot.rotationDegrees,
      scaleFactor = snapshot.scaleFactor,
      densityDpi = snapshot.densityDpi,
      currentMode = snapshot.currentMode,
      supportedModes = snapshot.supportedModes,
      maximumRefreshRateHz = snapshot.maximumRefreshRateHz,
      colorDepthBits = snapshot.colorDepthBits,
      colorGamut = snapshot.colorGamut,
      hdrFormats = snapshot.hdrFormats,
      brightness = snapshot.brightness,
      super._completed();
  @override
  DisplaySnapshot _collected() => DisplaySnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.display;
  @override
  Map<String, Object?> _fields() => {
    'label': label,
    'primary': primary,
    'internal': internal,
    'state': state,
    'logicalBounds': logicalBounds,
    'workAreaBounds': workAreaBounds,
    'pixelSize': pixelSize,
    'physicalSizeMillimeters': physicalSizeMillimeters,
    'orientation': orientation,
    'rotationDegrees': rotationDegrees,
    'scaleFactor': scaleFactor,
    'densityDpi': densityDpi,
    'currentMode': currentMode,
    'supportedModes': supportedModes,
    'maximumRefreshRateHz': maximumRefreshRateHz,
    'colorDepthBits': colorDepthBits,
    'colorGamut': colorGamut,
    'hdrFormats': hdrFormats,
    'brightness': brightness,
  };
}

final class ViewportSnapshot extends DeviceSnapshot {
  /// 레이아웃 뷰포트 크기
  final Size<double>? size;
  /// 현재 보이는 뷰포트 크기
  final Size<double>? visualViewportSize;
  /// 시각 뷰포트 확대 배율
  final double? visualViewportScale;
  /// 안전 영역 여백
  final Insets? safeAreaInsets;
  /// 텍스트 확대 배율
  final double? textScaleFactor;
  ViewportSnapshot({super.collectedAt,
    this.size,
    this.visualViewportSize,
    this.visualViewportScale,
    this.safeAreaInsets,
    this.textScaleFactor,
  });
  ViewportSnapshot._completed(ViewportSnapshot snapshot)
    : size = snapshot.size,
      visualViewportSize = snapshot.visualViewportSize,
      visualViewportScale = snapshot.visualViewportScale,
      safeAreaInsets = snapshot.safeAreaInsets,
      textScaleFactor = snapshot.textScaleFactor,
      super._completed();
  @override
  ViewportSnapshot _collected() => ViewportSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.viewport;
  @override
  Map<String, Object?> _fields() => {
    'size': size,
    'visualViewportSize': visualViewportSize,
    'visualViewportScale': visualViewportScale,
    'safeAreaInsets': safeAreaInsets,
    'textScaleFactor': textScaleFactor,
  };
}

final class PowerSnapshot extends DeviceSnapshot {
  /// 전원 공급원
  final PowerSource? powerSource;
  /// 절전 모드 적용 여부
  final bool? powerSaveMode;
  /// 플랫폼별 열 상태 타입의 합집합
  final ThermalState? thermalState;
  PowerSnapshot({super.collectedAt,
    this.powerSource,
    this.powerSaveMode,
    this.thermalState,
  });
  PowerSnapshot._completed(PowerSnapshot snapshot)
    : powerSource = snapshot.powerSource,
      powerSaveMode = snapshot.powerSaveMode,
      thermalState = snapshot.thermalState,
      super._completed();
  @override
  PowerSnapshot _collected() => PowerSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.power;
  @override
  Map<String, Object?> _fields() => {
    'powerSource': powerSource,
    'powerSaveMode': powerSaveMode,
    'thermalState': thermalState,
  };
}

final class BatterySnapshot extends DeviceSnapshot {
  /// 배터리 존재 여부
  final bool? present;
  /// 충전 잔량 비율 0–1
  final double? level;
  /// 충전 중 여부
  final bool? charging;
  /// 충전·방전 등 상태
  final BatteryState? state;
  /// 완충까지 남은 시간
  final Duration? timeToFull;
  /// 소진까지 남은 시간
  final Duration? timeToEmpty;
  /// 전압 mV
  final double? voltageMillivolts;
  /// 현재 전류 μA
  final double? currentMicroamps;
  /// 평균 전류 μA
  final double? averageCurrentMicroamps;
  /// 충전·방전 전력 mW
  final double? chargeRateMilliwatts;
  /// 배터리 온도 °C
  final double? temperatureCelsius;
  /// 전하량 μAh
  final BigInt? chargeCounterMicroampHours;
  /// 남은 에너지 mWh
  final double? remainingEnergyMilliwattHours;
  /// 현재 완충 용량 mWh
  final double? fullChargeEnergyMilliwattHours;
  /// 설계 용량 mWh
  final double? designEnergyMilliwattHours;
  /// 배터리 기술·화학 종류
  final String? technology;
  /// 플랫폼이 보고하는 상태·고장 종류
  final BatteryHealth? health;
  /// 충전 사이클 수
  final BigInt? cycleCount;
  BatterySnapshot({super.collectedAt,
    this.present,
    this.level,
    this.charging,
    this.state,
    this.timeToFull,
    this.timeToEmpty,
    this.voltageMillivolts,
    this.currentMicroamps,
    this.averageCurrentMicroamps,
    this.chargeRateMilliwatts,
    this.temperatureCelsius,
    this.chargeCounterMicroampHours,
    this.remainingEnergyMilliwattHours,
    this.fullChargeEnergyMilliwattHours,
    this.designEnergyMilliwattHours,
    this.technology,
    this.health,
    this.cycleCount,
  });
  BatterySnapshot._completed(BatterySnapshot snapshot)
    : present = snapshot.present,
      level = snapshot.level,
      charging = snapshot.charging,
      state = snapshot.state,
      timeToFull = snapshot.timeToFull,
      timeToEmpty = snapshot.timeToEmpty,
      voltageMillivolts = snapshot.voltageMillivolts,
      currentMicroamps = snapshot.currentMicroamps,
      averageCurrentMicroamps = snapshot.averageCurrentMicroamps,
      chargeRateMilliwatts = snapshot.chargeRateMilliwatts,
      temperatureCelsius = snapshot.temperatureCelsius,
      chargeCounterMicroampHours = snapshot.chargeCounterMicroampHours,
      remainingEnergyMilliwattHours = snapshot.remainingEnergyMilliwattHours,
      fullChargeEnergyMilliwattHours = snapshot.fullChargeEnergyMilliwattHours,
      designEnergyMilliwattHours = snapshot.designEnergyMilliwattHours,
      technology = snapshot.technology,
      health = snapshot.health,
      cycleCount = snapshot.cycleCount,
      super._completed();
  @override
  BatterySnapshot _collected() => BatterySnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.battery;
  @override
  Map<String, Object?> _fields() => {
    'present': present,
    'level': level,
    'charging': charging,
    'state': state,
    'timeToFull': timeToFull,
    'timeToEmpty': timeToEmpty,
    'voltageMillivolts': voltageMillivolts,
    'currentMicroamps': currentMicroamps,
    'averageCurrentMicroamps': averageCurrentMicroamps,
    'chargeRateMilliwatts': chargeRateMilliwatts,
    'temperatureCelsius': temperatureCelsius,
    'chargeCounterMicroampHours': chargeCounterMicroampHours,
    'remainingEnergyMilliwattHours': remainingEnergyMilliwattHours,
    'fullChargeEnergyMilliwattHours': fullChargeEnergyMilliwattHours,
    'designEnergyMilliwattHours': designEnergyMilliwattHours,
    'technology': technology,
    'health': health,
    'cycleCount': cycleCount,
  };
}

final class NetworkPathSnapshot extends DeviceSnapshot {
  /// 로컬 연결 경로 상태
  final ConnectionState? connectionState;
  /// 경로에 사용되는 전송 수단 집합
  final Set<NetworkTransport>? transports;
  /// 사용량 제한·종량제 네트워크 여부
  final bool? metered;
  /// 플랫폼이 비용이 큰 경로로 분류하는지 여부
  final bool? expensive;
  /// 플랫폼의 제한된 데이터 모드 여부
  final bool? constrained;
  /// 사용자의 데이터 절약 선호
  final bool? saveData;
  /// 경로의 IPv4 지원 여부
  final bool? supportsIpv4;
  /// 경로의 IPv6 지원 여부
  final bool? supportsIpv6;
  /// 경로의 DNS 지원 여부
  final bool? supportsDns;
  /// OS가 보고하는 인터넷 검증 상태
  final bool? internetValidated;
  /// OS가 보고하는 captive portal 상태
  final bool? captivePortal;
  NetworkPathSnapshot({super.collectedAt,
    this.connectionState,
    Set<NetworkTransport>? transports,
    this.metered,
    this.expensive,
    this.constrained,
    this.saveData,
    this.supportsIpv4,
    this.supportsIpv6,
    this.supportsDns,
    this.internetValidated,
    this.captivePortal,
  }) : transports = transports == null ? null : Set.unmodifiable(transports);
  NetworkPathSnapshot._completed(NetworkPathSnapshot snapshot)
    : connectionState = snapshot.connectionState,
      transports = snapshot.transports,
      metered = snapshot.metered,
      expensive = snapshot.expensive,
      constrained = snapshot.constrained,
      saveData = snapshot.saveData,
      supportsIpv4 = snapshot.supportsIpv4,
      supportsIpv6 = snapshot.supportsIpv6,
      supportsDns = snapshot.supportsDns,
      internetValidated = snapshot.internetValidated,
      captivePortal = snapshot.captivePortal,
      super._completed();
  @override
  NetworkPathSnapshot _collected() => NetworkPathSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.networkPath;
  @override
  Map<String, Object?> _fields() => {
    'connectionState': connectionState,
    'transports': transports,
    'metered': metered,
    'expensive': expensive,
    'constrained': constrained,
    'saveData': saveData,
    'supportsIpv4': supportsIpv4,
    'supportsIpv6': supportsIpv6,
    'supportsDns': supportsDns,
    'internetValidated': internetValidated,
    'captivePortal': captivePortal,
  };
}

final class NetworkPerformanceSnapshot extends DeviceSnapshot {
  /// 하향 전송 속도 bit/s
  final double? downlinkBps;
  /// 상향 전송 속도 bit/s
  final double? uplinkBps;
  /// 왕복 시간
  final Duration? roundTripTime;
  /// 플랫폼의 네트워크 성능 분류
  final EffectiveConnectionType? effectiveType;
  /// 브라우저가 보고하는 온라인 상태
  final bool? browserOnline;
  NetworkPerformanceSnapshot({super.collectedAt,
    this.downlinkBps,
    this.uplinkBps,
    this.roundTripTime,
    this.effectiveType,
    this.browserOnline,
  });
  NetworkPerformanceSnapshot._completed(NetworkPerformanceSnapshot snapshot)
    : downlinkBps = snapshot.downlinkBps,
      uplinkBps = snapshot.uplinkBps,
      roundTripTime = snapshot.roundTripTime,
      effectiveType = snapshot.effectiveType,
      browserOnline = snapshot.browserOnline,
      super._completed();
  @override
  NetworkPerformanceSnapshot _collected() => NetworkPerformanceSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.networkPerformance;
  @override
  Map<String, Object?> _fields() => {
    'downlinkBps': downlinkBps,
    'uplinkBps': uplinkBps,
    'roundTripTime': roundTripTime,
    'effectiveType': effectiveType,
    'browserOnline': browserOnline,
  };
}

final class NetworkInterfaceSnapshot extends DeviceSnapshot {
  /// 인터페이스 이름
  final String? name;
  /// 인터페이스 종류
  final NetworkInterfaceType? interfaceType;
  /// 인터페이스 동작 상태
  final NetworkOperationalState? operationalState;
  /// 플랫폼이 허용해 공개하는 하드웨어 주소
  final String? hardwareAddress;
  /// 인터페이스 IP 주소 정보
  final List<IpAddressInfo>? ipAddresses;
  /// DNS 서버 주소 목록
  final List<String>? dnsServers;
  /// 게이트웨이 주소 목록
  final List<String>? gateways;
  /// 경로 정보 목록
  final List<NetworkRoute>? routes;
  /// MTU byte 크기
  final BigInt? mtuBytes;
  NetworkInterfaceSnapshot({super.collectedAt,
    this.name,
    this.interfaceType,
    this.operationalState,
    this.hardwareAddress,
    List<IpAddressInfo>? ipAddresses,
    List<String>? dnsServers,
    List<String>? gateways,
    List<NetworkRoute>? routes,
    this.mtuBytes,
  }) : ipAddresses = ipAddresses == null ? null : List.unmodifiable(ipAddresses),
      dnsServers = dnsServers == null ? null : List.unmodifiable(dnsServers),
      gateways = gateways == null ? null : List.unmodifiable(gateways),
      routes = routes == null ? null : List.unmodifiable(routes);
  NetworkInterfaceSnapshot._completed(NetworkInterfaceSnapshot snapshot)
    : name = snapshot.name,
      interfaceType = snapshot.interfaceType,
      operationalState = snapshot.operationalState,
      hardwareAddress = snapshot.hardwareAddress,
      ipAddresses = snapshot.ipAddresses,
      dnsServers = snapshot.dnsServers,
      gateways = snapshot.gateways,
      routes = snapshot.routes,
      mtuBytes = snapshot.mtuBytes,
      super._completed();
  @override
  NetworkInterfaceSnapshot _collected() => NetworkInterfaceSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.networkInterface;
  @override
  Map<String, Object?> _fields() => {
    'name': name,
    'interfaceType': interfaceType,
    'operationalState': operationalState,
    'hardwareAddress': hardwareAddress,
    'ipAddresses': ipAddresses,
    'dnsServers': dnsServers,
    'gateways': gateways,
    'routes': routes,
    'mtuBytes': mtuBytes,
  };
}

final class WifiConnectionSnapshot extends DeviceSnapshot {
  /// 현재 연결 SSID
  final String? ssid;
  /// 현재 연결 BSSID
  final String? bssid;
  /// 현재 연결에서 선택된 인증 방식
  final WifiSecurity? security;
  /// 수신 신호 세기 dBm
  final double? rssiDbm;
  /// 현재 연결 주파수 Hz
  final double? frequencyHz;
  /// 수신 링크 속도 bit/s
  final double? receiveLinkSpeedBps;
  /// 송신 링크 속도 bit/s
  final double? transmitLinkSpeedBps;
  WifiConnectionSnapshot({super.collectedAt,
    this.ssid,
    this.bssid,
    this.security,
    this.rssiDbm,
    this.frequencyHz,
    this.receiveLinkSpeedBps,
    this.transmitLinkSpeedBps,
  });
  WifiConnectionSnapshot._completed(WifiConnectionSnapshot snapshot)
    : ssid = snapshot.ssid,
      bssid = snapshot.bssid,
      security = snapshot.security,
      rssiDbm = snapshot.rssiDbm,
      frequencyHz = snapshot.frequencyHz,
      receiveLinkSpeedBps = snapshot.receiveLinkSpeedBps,
      transmitLinkSpeedBps = snapshot.transmitLinkSpeedBps,
      super._completed();
  @override
  WifiConnectionSnapshot _collected() => WifiConnectionSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.wifiConnection;
  @override
  Map<String, Object?> _fields() => {
    'ssid': ssid,
    'bssid': bssid,
    'security': security,
    'rssiDbm': rssiDbm,
    'frequencyHz': frequencyHz,
    'receiveLinkSpeedBps': receiveLinkSpeedBps,
    'transmitLinkSpeedBps': transmitLinkSpeedBps,
  };
}

final class CellularSubscriptionSnapshot extends DeviceSnapshot {
  /// 슬롯 인덱스
  final int? slotIndex;
  /// 통신사 이름
  final String? carrierName;
  /// 플랫폼이 보고하는 국가 코드
  final String? countryCode;
  /// MCC. 앞자리 0을 보존하는 문자열
  final String? mobileCountryCode;
  /// MNC. 앞자리 0을 보존하는 문자열
  final String? mobileNetworkCode;
  /// 현재 데이터 연결의 무선 기술
  final RadioTechnology? radioTechnology;
  /// 로밍 여부
  final bool? roaming;
  CellularSubscriptionSnapshot({super.collectedAt,
    this.slotIndex,
    this.carrierName,
    this.countryCode,
    this.mobileCountryCode,
    this.mobileNetworkCode,
    this.radioTechnology,
    this.roaming,
  });
  CellularSubscriptionSnapshot._completed(CellularSubscriptionSnapshot snapshot)
    : slotIndex = snapshot.slotIndex,
      carrierName = snapshot.carrierName,
      countryCode = snapshot.countryCode,
      mobileCountryCode = snapshot.mobileCountryCode,
      mobileNetworkCode = snapshot.mobileNetworkCode,
      radioTechnology = snapshot.radioTechnology,
      roaming = snapshot.roaming,
      super._completed();
  @override
  CellularSubscriptionSnapshot _collected() => CellularSubscriptionSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.cellularSubscription;
  @override
  Map<String, Object?> _fields() => {
    'slotIndex': slotIndex,
    'carrierName': carrierName,
    'countryCode': countryCode,
    'mobileCountryCode': mobileCountryCode,
    'mobileNetworkCode': mobileNetworkCode,
    'radioTechnology': radioTechnology,
    'roaming': roaming,
  };
}

final class StorageVolumeSnapshot extends DeviceSnapshot {
  /// 볼륨 이름
  final String? name;
  /// 파일 시스템
  final String? fileSystem;
  /// 볼륨 전체 용량
  final BigInt? totalBytes;
  /// 볼륨의 빈 공간
  final BigInt? freeBytes;
  /// 현재 호출자가 사용할 수 있는 여유 공간
  final BigInt? availableToCallerBytes;
  /// 할당량 등 호출자 제한을 반영한 전체 용량
  final BigInt? totalBytesForCaller;
  /// 읽기 전용 여부
  final bool? readOnly;
  /// 이동식 여부
  final bool? removable;
  /// 암호화 여부
  final bool? encrypted;
  /// 이름의 대소문자 구분 여부
  final bool? caseSensitive;
  /// 플랫폼이 중요한 용도에 제공하는 가용량
  final BigInt? availableForImportantUsageBytes;
  /// 플랫폼이 기회적 용도에 제공하는 가용량
  final BigInt? availableForOpportunisticUsageBytes;
  /// 플랫폼이 할당 가능하다고 보고하는 용량
  final BigInt? allocatableBytes;
  StorageVolumeSnapshot({super.collectedAt,
    this.name,
    this.fileSystem,
    this.totalBytes,
    this.freeBytes,
    this.availableToCallerBytes,
    this.totalBytesForCaller,
    this.readOnly,
    this.removable,
    this.encrypted,
    this.caseSensitive,
    this.availableForImportantUsageBytes,
    this.availableForOpportunisticUsageBytes,
    this.allocatableBytes,
  });
  StorageVolumeSnapshot._completed(StorageVolumeSnapshot snapshot)
    : name = snapshot.name,
      fileSystem = snapshot.fileSystem,
      totalBytes = snapshot.totalBytes,
      freeBytes = snapshot.freeBytes,
      availableToCallerBytes = snapshot.availableToCallerBytes,
      totalBytesForCaller = snapshot.totalBytesForCaller,
      readOnly = snapshot.readOnly,
      removable = snapshot.removable,
      encrypted = snapshot.encrypted,
      caseSensitive = snapshot.caseSensitive,
      availableForImportantUsageBytes = snapshot.availableForImportantUsageBytes,
      availableForOpportunisticUsageBytes = snapshot.availableForOpportunisticUsageBytes,
      allocatableBytes = snapshot.allocatableBytes,
      super._completed();
  @override
  StorageVolumeSnapshot _collected() => StorageVolumeSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.storageVolume;
  @override
  Map<String, Object?> _fields() => {
    'name': name,
    'fileSystem': fileSystem,
    'totalBytes': totalBytes,
    'freeBytes': freeBytes,
    'availableToCallerBytes': availableToCallerBytes,
    'totalBytesForCaller': totalBytesForCaller,
    'readOnly': readOnly,
    'removable': removable,
    'encrypted': encrypted,
    'caseSensitive': caseSensitive,
    'availableForImportantUsageBytes': availableForImportantUsageBytes,
    'availableForOpportunisticUsageBytes': availableForOpportunisticUsageBytes,
    'allocatableBytes': allocatableBytes,
  };
}

final class OriginStorageSnapshot extends DeviceSnapshot {
  /// origin 저장 한도
  final BigInt? quotaBytes;
  /// origin 사용량
  final BigInt? usageBytes;
  /// 플랫폼이 공개하는 저장 유형별 사용량
  final Map<StorageCategory, BigInt>? usageByCategory;
  /// 영구 저장 권한·상태
  final bool? persistent;
  OriginStorageSnapshot({super.collectedAt,
    this.quotaBytes,
    this.usageBytes,
    Map<StorageCategory, BigInt>? usageByCategory,
    this.persistent,
  }) : usageByCategory = usageByCategory == null ? null : Map.unmodifiable(usageByCategory);
  OriginStorageSnapshot._completed(OriginStorageSnapshot snapshot)
    : quotaBytes = snapshot.quotaBytes,
      usageBytes = snapshot.usageBytes,
      usageByCategory = snapshot.usageByCategory,
      persistent = snapshot.persistent,
      super._completed();
  @override
  OriginStorageSnapshot _collected() => OriginStorageSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.originStorage;
  @override
  Map<String, Object?> _fields() => {
    'quotaBytes': quotaBytes,
    'usageBytes': usageBytes,
    'usageByCategory': usageByCategory,
    'persistent': persistent,
  };
}

final class AccelerometerSnapshot extends DeviceSnapshot {
  /// 중력을 포함한 가속도
  final Vector3? value;
  AccelerometerSnapshot({super.collectedAt,
    this.value,
  });
  AccelerometerSnapshot._completed(AccelerometerSnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  AccelerometerSnapshot _collected() => AccelerometerSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.accelerometer;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class LinearAccelerationSnapshot extends DeviceSnapshot {
  /// 중력을 제외한 가속도
  final Vector3? value;
  LinearAccelerationSnapshot({super.collectedAt,
    this.value,
  });
  LinearAccelerationSnapshot._completed(LinearAccelerationSnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  LinearAccelerationSnapshot _collected() => LinearAccelerationSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.linearAcceleration;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class GravitySnapshot extends DeviceSnapshot {
  /// 중력 벡터
  final Vector3? value;
  GravitySnapshot({super.collectedAt,
    this.value,
  });
  GravitySnapshot._completed(GravitySnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  GravitySnapshot _collected() => GravitySnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.gravity;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class GyroscopeSnapshot extends DeviceSnapshot {
  /// 각속도
  final Vector3? value;
  GyroscopeSnapshot({super.collectedAt,
    this.value,
  });
  GyroscopeSnapshot._completed(GyroscopeSnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  GyroscopeSnapshot _collected() => GyroscopeSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.gyroscope;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class MagnetometerSnapshot extends DeviceSnapshot {
  /// 자기장
  final Vector3? value;
  MagnetometerSnapshot({super.collectedAt,
    this.value,
  });
  MagnetometerSnapshot._completed(MagnetometerSnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  MagnetometerSnapshot _collected() => MagnetometerSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.magnetometer;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class RelativeOrientationSnapshot extends DeviceSnapshot {
  /// 수집 세션의 상대 기준에 대한 자세
  final Quaternion? value;
  RelativeOrientationSnapshot({super.collectedAt,
    this.value,
  });
  RelativeOrientationSnapshot._completed(RelativeOrientationSnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  RelativeOrientationSnapshot _collected() => RelativeOrientationSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.relativeOrientation;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class AbsoluteOrientationSnapshot extends DeviceSnapshot {
  /// 동쪽·자기북·위쪽 기준에 대한 자세
  final Quaternion? value;
  AbsoluteOrientationSnapshot({super.collectedAt,
    this.value,
  });
  AbsoluteOrientationSnapshot._completed(AbsoluteOrientationSnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  AbsoluteOrientationSnapshot _collected() => AbsoluteOrientationSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.absoluteOrientation;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class IlluminanceSnapshot extends DeviceSnapshot {
  /// 조도
  final double? value;
  IlluminanceSnapshot({super.collectedAt,
    this.value,
  });
  IlluminanceSnapshot._completed(IlluminanceSnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  IlluminanceSnapshot _collected() => IlluminanceSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.illuminance;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class PressureSnapshot extends DeviceSnapshot {
  /// 기압
  final double? value;
  PressureSnapshot({super.collectedAt,
    this.value,
  });
  PressureSnapshot._completed(PressureSnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  PressureSnapshot _collected() => PressureSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.pressure;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class AmbientTemperatureSnapshot extends DeviceSnapshot {
  /// 주변 온도
  final double? value;
  AmbientTemperatureSnapshot({super.collectedAt,
    this.value,
  });
  AmbientTemperatureSnapshot._completed(AmbientTemperatureSnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  AmbientTemperatureSnapshot _collected() => AmbientTemperatureSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.ambientTemperature;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class RelativeHumiditySnapshot extends DeviceSnapshot {
  /// 상대 습도
  final double? value;
  RelativeHumiditySnapshot({super.collectedAt,
    this.value,
  });
  RelativeHumiditySnapshot._completed(RelativeHumiditySnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  RelativeHumiditySnapshot _collected() => RelativeHumiditySnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.relativeHumidity;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class ProximityNearSnapshot extends DeviceSnapshot {
  /// 근접 상태
  final bool? value;
  ProximityNearSnapshot({super.collectedAt,
    this.value,
  });
  ProximityNearSnapshot._completed(ProximityNearSnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  ProximityNearSnapshot _collected() => ProximityNearSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.proximityNear;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class ProximityDistanceSnapshot extends DeviceSnapshot {
  /// 근접 대상까지의 거리
  final double? value;
  ProximityDistanceSnapshot({super.collectedAt,
    this.value,
  });
  ProximityDistanceSnapshot._completed(ProximityDistanceSnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  ProximityDistanceSnapshot _collected() => ProximityDistanceSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.proximityDistance;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class RelativeAltitudeSnapshot extends DeviceSnapshot {
  /// 수집 세션의 기준점 대비 상대 고도
  final double? value;
  RelativeAltitudeSnapshot({super.collectedAt,
    this.value,
  });
  RelativeAltitudeSnapshot._completed(RelativeAltitudeSnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  RelativeAltitudeSnapshot _collected() => RelativeAltitudeSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.relativeAltitude;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class HingeAngleSnapshot extends DeviceSnapshot {
  /// 힌지 각도
  final double? value;
  HingeAngleSnapshot({super.collectedAt,
    this.value,
  });
  HingeAngleSnapshot._completed(HingeAngleSnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  HingeAngleSnapshot _collected() => HingeAngleSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.hingeAngle;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class StepCountSinceBootSnapshot extends DeviceSnapshot {
  /// 부팅 기준 누적 걸음 수
  final BigInt? value;
  StepCountSinceBootSnapshot({super.collectedAt,
    this.value,
  });
  StepCountSinceBootSnapshot._completed(StepCountSinceBootSnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  StepCountSinceBootSnapshot _collected() => StepCountSinceBootSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.stepCountSinceBoot;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class StepDetectedSnapshot extends DeviceSnapshot {
  /// 걸음 발생. false 초기 이벤트는 없음
  final bool? value;
  StepDetectedSnapshot({super.collectedAt,
    this.value,
  });
  StepDetectedSnapshot._completed(StepDetectedSnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  StepDetectedSnapshot _collected() => StepDetectedSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.stepDetected;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class SignificantMotionSnapshot extends DeviceSnapshot {
  /// 큰 움직임 발생. false 초기 이벤트는 없음
  final bool? value;
  SignificantMotionSnapshot({super.collectedAt,
    this.value,
  });
  SignificantMotionSnapshot._completed(SignificantMotionSnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  SignificantMotionSnapshot _collected() => SignificantMotionSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.significantMotion;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class HumanPresenceSnapshot extends DeviceSnapshot {
  /// 사람 존재 여부
  final bool? value;
  HumanPresenceSnapshot({super.collectedAt,
    this.value,
  });
  HumanPresenceSnapshot._completed(HumanPresenceSnapshot snapshot)
    : value = snapshot.value,
      super._completed();
  @override
  HumanPresenceSnapshot _collected() => HumanPresenceSnapshot._completed(this);
  @override
  EntityKind? get entityKind => EntityKind.humanPresence;
  @override
  Map<String, Object?> _fields() => {
    'value': value,
  };
}

final class SensorDescription extends DeviceSnapshot {
  /// 센서 종류
  final SensorKind? kind;
  /// 센서 이름
  final String? name;
  /// 제조사
  final String? vendor;
  /// 플랫폼이 보고하는 센서 버전
  final String? version;
  /// 원본 센서의 보고 모드
  final SensorReportingMode? reportingMode;
  /// 지원되는 최소 수집 간격
  final Duration? minimumInterval;
  /// 지원되는 최대 수집 간격
  final Duration? maximumInterval;
  /// 해당 센서 측정 단위의 최대 범위
  final double? maximumRange;
  /// 해당 센서 측정 단위의 분해능
  final double? resolution;
  /// 플랫폼이 보고하는 전류 소비 mA
  final double? powerMilliamps;
  /// 플랫폼이 공개하는 FIFO 샘플 수용량
  final int? fifoCapacity;
  SensorDescription({super.collectedAt,
    this.kind,
    this.name,
    this.vendor,
    this.version,
    this.reportingMode,
    this.minimumInterval,
    this.maximumInterval,
    this.maximumRange,
    this.resolution,
    this.powerMilliamps,
    this.fifoCapacity,
  });
  SensorDescription._completed(SensorDescription snapshot)
    : kind = snapshot.kind,
      name = snapshot.name,
      vendor = snapshot.vendor,
      version = snapshot.version,
      reportingMode = snapshot.reportingMode,
      minimumInterval = snapshot.minimumInterval,
      maximumInterval = snapshot.maximumInterval,
      maximumRange = snapshot.maximumRange,
      resolution = snapshot.resolution,
      powerMilliamps = snapshot.powerMilliamps,
      fifoCapacity = snapshot.fifoCapacity,
      super._completed();
  @override
  SensorDescription _collected() => SensorDescription._completed(this);
  @override
  EntityKind? get entityKind => null;
  @override
  Map<String, Object?> _fields() => {
    'kind': kind,
    'name': name,
    'vendor': vendor,
    'version': version,
    'reportingMode': reportingMode,
    'minimumInterval': minimumInterval,
    'maximumInterval': maximumInterval,
    'maximumRange': maximumRange,
    'resolution': resolution,
    'powerMilliamps': powerMilliamps,
    'fifoCapacity': fifoCapacity,
  };
}

/// Low-level native-adapter decoder. App queries use typed Entities.
abstract final class SnapshotCodec {
  static DeviceSnapshot decode(EntityKind kind, Map<String, Object?> fields, {DateTime? collectedAt}) => switch(kind) {
    EntityKind.deviceInfo => DeviceInfoSnapshot(collectedAt: collectedAt,
      manufacturer: fields['manufacturer'] is String ? fields['manufacturer'] as String : null,
      brand: fields['brand'] is String ? fields['brand'] as String : null,
      modelCode: fields['modelCode'] is String ? fields['modelCode'] as String : null,
      modelName: fields['modelName'] is String ? fields['modelName'] as String : null,
      deviceName: fields['deviceName'] is String ? fields['deviceName'] as String : null,
      formFactor: _enumValue(fields['formFactor'], FormFactor.values),
      product: fields['product'] is String ? fields['product'] as String : null,
      board: fields['board'] is String ? fields['board'] as String : null,
    ),
    EntityKind.os => OsSnapshot(collectedAt: collectedAt,
      family: _enumValue(fields['family'], OsFamily.values),
      name: fields['name'] is String ? fields['name'] as String : null,
      version: fields['version'] is String ? fields['version'] as String : null,
      build: fields['build'] is String ? fields['build'] as String : null,
      kernelName: fields['kernelName'] is String ? fields['kernelName'] as String : null,
      kernelVersion: fields['kernelVersion'] is String ? fields['kernelVersion'] as String : null,
    ),
    EntityKind.runtime => RuntimeSnapshot(collectedAt: collectedAt,
      hostArchitecture: _enumValue(fields['hostArchitecture'], Architecture.values),
      processArchitecture: _enumValue(fields['processArchitecture'], Architecture.values),
      processBitness: _integer(fields['processBitness']),
      supportedAbis: _set(fields['supportedAbis'], (raw) => _enumValue(raw, Abi.values)),
    ),
    EntityKind.cpu => CpuSnapshot(collectedAt: collectedAt,
      model: fields['model'] is String ? fields['model'] as String : null,
      manufacturer: fields['manufacturer'] is String ? fields['manufacturer'] as String : null,
      socModel: fields['socModel'] is String ? fields['socModel'] as String : null,
      socManufacturer: fields['socManufacturer'] is String ? fields['socManufacturer'] as String : null,
      logicalProcessorCount: _integer(fields['logicalProcessorCount']),
      availableLogicalProcessorCount: _integer(fields['availableLogicalProcessorCount']),
      physicalCoreCount: _integer(fields['physicalCoreCount']),
      processorPackageCount: _integer(fields['processorPackageCount']),
    ),
    EntityKind.cpuCore => CpuCoreSnapshot(collectedAt: collectedAt,
      logicalIndex: _integer(fields['logicalIndex']),
      coreIndex: _integer(fields['coreIndex']),
      packageIndex: _integer(fields['packageIndex']),
      online: fields['online'] is bool ? fields['online'] as bool : null,
      currentClockHz: _number(fields['currentClockHz']),
      maximumClockHz: _number(fields['maximumClockHz']),
    ),
    EntityKind.ram => RamSnapshot(collectedAt: collectedAt,
      physicalBytes: _counter(fields['physicalBytes']),
      kernelAccessibleBytes: _counter(fields['kernelAccessibleBytes']),
      advertisedBytes: _counter(fields['advertisedBytes']),
      availableBytes: _counter(fields['availableBytes']),
      freeBytes: _counter(fields['freeBytes']),
      lowMemory: fields['lowMemory'] is bool ? fields['lowMemory'] as bool : null,
      lowMemoryThresholdBytes: _counter(fields['lowMemoryThresholdBytes']),
    ),
    EntityKind.processMemory => ProcessMemorySnapshot(collectedAt: collectedAt,
      allocationRemainingBytes: _counter(fields['allocationRemainingBytes']),
    ),
    EntityKind.locale => LocaleSnapshot(collectedAt: collectedAt,
      currentLanguageTag: fields['currentLanguageTag'] is String ? fields['currentLanguageTag'] as String : null,
      preferredLanguageTags: _list(fields['preferredLanguageTags'], (raw) => raw is String ? raw : null),
      systemLanguageTags: _list(fields['systemLanguageTags'], (raw) => raw is String ? raw : null),
      appLanguageTags: _list(fields['appLanguageTags'], (raw) => raw is String ? raw : null),
      regionCode: fields['regionCode'] is String ? fields['regionCode'] as String : null,
      scriptCode: fields['scriptCode'] is String ? fields['scriptCode'] as String : null,
      calendar: fields['calendar'] is String ? fields['calendar'] as String : null,
      numberingSystem: fields['numberingSystem'] is String ? fields['numberingSystem'] as String : null,
      hourCycle: _enumValue(fields['hourCycle'], HourCycle.values),
      firstWeekday: _enumValue(fields['firstWeekday'], Weekday.values),
      measurementSystem: _enumValue(fields['measurementSystem'], MeasurementSystem.values),
    ),
    EntityKind.timeZone => TimeZoneSnapshot(collectedAt: collectedAt,
      ianaId: fields['ianaId'] is String ? fields['ianaId'] as String : null,
      windowsId: fields['windowsId'] is String ? fields['windowsId'] as String : null,
      utcOffsetSeconds: _integer(fields['utcOffsetSeconds']),
      daylightSavingTime: fields['daylightSavingTime'] is bool ? fields['daylightSavingTime'] as bool : null,
    ),
    EntityKind.androidBuild => AndroidBuildSnapshot(collectedAt: collectedAt,
      apiLevel: _integer(fields['apiLevel']),
      securityPatch: fields['securityPatch'] is String ? fields['securityPatch'] as String : null,
      buildId: fields['buildId'] is String ? fields['buildId'] as String : null,
      buildDisplay: fields['buildDisplay'] is String ? fields['buildDisplay'] as String : null,
      buildFingerprint: fields['buildFingerprint'] is String ? fields['buildFingerprint'] as String : null,
      buildType: fields['buildType'] is String ? fields['buildType'] as String : null,
      buildTags: _list(fields['buildTags'], (raw) => raw is String ? raw : null),
      bootloaderVersion: fields['bootloaderVersion'] is String ? fields['bootloaderVersion'] as String : null,
    ),
    EntityKind.androidIdentity => AndroidIdentitySnapshot(collectedAt: collectedAt,
      androidId: fields['androidId'] is String ? fields['androidId'] as String : null,
    ),
    EntityKind.appleVendorIdentity => AppleVendorIdentitySnapshot(collectedAt: collectedAt,
      vendorId: fields['vendorId'] is String ? fields['vendorId'] as String : null,
    ),
    EntityKind.windowsPublisherIdentity => WindowsPublisherIdentitySnapshot(collectedAt: collectedAt,
      publisherId: fields['publisherId'] is String ? fields['publisherId'] as String : null,
      source: _enumValue(fields['source'], WindowsIdentitySource.values),
    ),
    EntityKind.macPlatformIdentity => MacPlatformIdentitySnapshot(collectedAt: collectedAt,
      platformUuid: fields['platformUuid'] is String ? fields['platformUuid'] as String : null,
    ),
    EntityKind.hardwareSerial => HardwareSerialSnapshot(collectedAt: collectedAt,
      serial: fields['serial'] is String ? fields['serial'] as String : null,
    ),
    EntityKind.telephonyIdentity => TelephonyIdentitySnapshot(collectedAt: collectedAt,
      imei: fields['imei'] is String ? fields['imei'] as String : null,
      meid: fields['meid'] is String ? fields['meid'] as String : null,
    ),
    EntityKind.display => DisplaySnapshot(collectedAt: collectedAt,
      label: fields['label'] is String ? fields['label'] as String : null,
      primary: fields['primary'] is bool ? fields['primary'] as bool : null,
      internal: fields['internal'] is bool ? fields['internal'] as bool : null,
      state: _enumValue(fields['state'], DisplayState.values),
      logicalBounds: _components(fields['logicalBounds'], ['x', 'y', 'width', 'height'], (n) => Rect(n[0], n[1], n[2], n[3])),
      workAreaBounds: _components(fields['workAreaBounds'], ['x', 'y', 'width', 'height'], (n) => Rect(n[0], n[1], n[2], n[3])),
      pixelSize: _pixelSize(fields['pixelSize']),
      physicalSizeMillimeters: _components(fields['physicalSizeMillimeters'], ['width', 'height'], (n) => Size<double>(n[0], n[1])),
      orientation: _enumValue(fields['orientation'], DisplayOrientation.values),
      rotationDegrees: _number(fields['rotationDegrees']),
      scaleFactor: _number(fields['scaleFactor']),
      densityDpi: _number(fields['densityDpi']),
      currentMode: _displayMode(fields['currentMode']),
      supportedModes: _list(fields['supportedModes'], (raw) => _displayMode(raw)),
      maximumRefreshRateHz: _number(fields['maximumRefreshRateHz']),
      colorDepthBits: _integer(fields['colorDepthBits']),
      colorGamut: _enumValue(fields['colorGamut'], ColorGamut.values),
      hdrFormats: _set(fields['hdrFormats'], (raw) => _enumValue(raw, HdrFormat.values)),
      brightness: _ratio(fields['brightness']),
    ),
    EntityKind.viewport => ViewportSnapshot(collectedAt: collectedAt,
      size: _components(fields['size'], ['width', 'height'], (n) => Size<double>(n[0], n[1])),
      visualViewportSize: _components(fields['visualViewportSize'], ['width', 'height'], (n) => Size<double>(n[0], n[1])),
      visualViewportScale: _number(fields['visualViewportScale']),
      safeAreaInsets: _components(fields['safeAreaInsets'], ['top', 'right', 'bottom', 'left'], (n) => Insets(n[0], n[1], n[2], n[3])),
      textScaleFactor: _number(fields['textScaleFactor']),
    ),
    EntityKind.power => PowerSnapshot(collectedAt: collectedAt,
      powerSource: _enumValue(fields['powerSource'], PowerSource.values),
      powerSaveMode: fields['powerSaveMode'] is bool ? fields['powerSaveMode'] as bool : null,
      thermalState: _thermal(fields['thermalState']),
    ),
    EntityKind.battery => BatterySnapshot(collectedAt: collectedAt,
      present: fields['present'] is bool ? fields['present'] as bool : null,
      level: _ratio(fields['level']),
      charging: fields['charging'] is bool ? fields['charging'] as bool : null,
      state: _enumValue(fields['state'], BatteryState.values),
      timeToFull: _duration(fields['timeToFull']),
      timeToEmpty: _duration(fields['timeToEmpty']),
      voltageMillivolts: _number(fields['voltageMillivolts']),
      currentMicroamps: _number(fields['currentMicroamps']),
      averageCurrentMicroamps: _number(fields['averageCurrentMicroamps']),
      chargeRateMilliwatts: _number(fields['chargeRateMilliwatts']),
      temperatureCelsius: _number(fields['temperatureCelsius']),
      chargeCounterMicroampHours: _counter(fields['chargeCounterMicroampHours'], signed: true),
      remainingEnergyMilliwattHours: _number(fields['remainingEnergyMilliwattHours']),
      fullChargeEnergyMilliwattHours: _number(fields['fullChargeEnergyMilliwattHours']),
      designEnergyMilliwattHours: _number(fields['designEnergyMilliwattHours']),
      technology: fields['technology'] is String ? fields['technology'] as String : null,
      health: _enumValue(fields['health'], BatteryHealth.values),
      cycleCount: _counter(fields['cycleCount'], signed: true),
    ),
    EntityKind.networkPath => NetworkPathSnapshot(collectedAt: collectedAt,
      connectionState: _enumValue(fields['connectionState'], ConnectionState.values),
      transports: _set(fields['transports'], (raw) => _enumValue(raw, NetworkTransport.values)),
      metered: fields['metered'] is bool ? fields['metered'] as bool : null,
      expensive: fields['expensive'] is bool ? fields['expensive'] as bool : null,
      constrained: fields['constrained'] is bool ? fields['constrained'] as bool : null,
      saveData: fields['saveData'] is bool ? fields['saveData'] as bool : null,
      supportsIpv4: fields['supportsIpv4'] is bool ? fields['supportsIpv4'] as bool : null,
      supportsIpv6: fields['supportsIpv6'] is bool ? fields['supportsIpv6'] as bool : null,
      supportsDns: fields['supportsDns'] is bool ? fields['supportsDns'] as bool : null,
      internetValidated: fields['internetValidated'] is bool ? fields['internetValidated'] as bool : null,
      captivePortal: fields['captivePortal'] is bool ? fields['captivePortal'] as bool : null,
    ),
    EntityKind.networkPerformance => NetworkPerformanceSnapshot(collectedAt: collectedAt,
      downlinkBps: _number(fields['downlinkBps']),
      uplinkBps: _number(fields['uplinkBps']),
      roundTripTime: _duration(fields['roundTripTime']),
      effectiveType: _enumValue(fields['effectiveType'], EffectiveConnectionType.values),
      browserOnline: fields['browserOnline'] is bool ? fields['browserOnline'] as bool : null,
    ),
    EntityKind.networkInterface => NetworkInterfaceSnapshot(collectedAt: collectedAt,
      name: fields['name'] is String ? fields['name'] as String : null,
      interfaceType: _enumValue(fields['interfaceType'], NetworkInterfaceType.values),
      operationalState: _enumValue(fields['operationalState'], NetworkOperationalState.values),
      hardwareAddress: fields['hardwareAddress'] is String ? fields['hardwareAddress'] as String : null,
      ipAddresses: _list(fields['ipAddresses'], (raw) => _addressInfo(raw)),
      dnsServers: _list(fields['dnsServers'], (raw) => raw is String ? raw : null),
      gateways: _list(fields['gateways'], (raw) => raw is String ? raw : null),
      routes: _list(fields['routes'], (raw) => _route(raw)),
      mtuBytes: _counter(fields['mtuBytes']),
    ),
    EntityKind.wifiConnection => WifiConnectionSnapshot(collectedAt: collectedAt,
      ssid: fields['ssid'] is String ? fields['ssid'] as String : null,
      bssid: fields['bssid'] is String ? fields['bssid'] as String : null,
      security: _enumValue(fields['security'], WifiSecurity.values),
      rssiDbm: _number(fields['rssiDbm']),
      frequencyHz: _number(fields['frequencyHz']),
      receiveLinkSpeedBps: _number(fields['receiveLinkSpeedBps']),
      transmitLinkSpeedBps: _number(fields['transmitLinkSpeedBps']),
    ),
    EntityKind.cellularSubscription => CellularSubscriptionSnapshot(collectedAt: collectedAt,
      slotIndex: _integer(fields['slotIndex']),
      carrierName: fields['carrierName'] is String ? fields['carrierName'] as String : null,
      countryCode: fields['countryCode'] is String ? fields['countryCode'] as String : null,
      mobileCountryCode: fields['mobileCountryCode'] is String ? fields['mobileCountryCode'] as String : null,
      mobileNetworkCode: fields['mobileNetworkCode'] is String ? fields['mobileNetworkCode'] as String : null,
      radioTechnology: _enumValue(fields['radioTechnology'], RadioTechnology.values),
      roaming: fields['roaming'] is bool ? fields['roaming'] as bool : null,
    ),
    EntityKind.storageVolume => StorageVolumeSnapshot(collectedAt: collectedAt,
      name: fields['name'] is String ? fields['name'] as String : null,
      fileSystem: fields['fileSystem'] is String ? fields['fileSystem'] as String : null,
      totalBytes: _counter(fields['totalBytes']),
      freeBytes: _counter(fields['freeBytes']),
      availableToCallerBytes: _counter(fields['availableToCallerBytes']),
      totalBytesForCaller: _counter(fields['totalBytesForCaller']),
      readOnly: fields['readOnly'] is bool ? fields['readOnly'] as bool : null,
      removable: fields['removable'] is bool ? fields['removable'] as bool : null,
      encrypted: fields['encrypted'] is bool ? fields['encrypted'] as bool : null,
      caseSensitive: fields['caseSensitive'] is bool ? fields['caseSensitive'] as bool : null,
      availableForImportantUsageBytes: _counter(fields['availableForImportantUsageBytes']),
      availableForOpportunisticUsageBytes: _counter(fields['availableForOpportunisticUsageBytes']),
      allocatableBytes: _counter(fields['allocatableBytes']),
    ),
    EntityKind.originStorage => OriginStorageSnapshot(collectedAt: collectedAt,
      quotaBytes: _counter(fields['quotaBytes']),
      usageBytes: _counter(fields['usageBytes']),
      usageByCategory: _map(fields['usageByCategory'], (raw) => _enumValue(raw, StorageCategory.values), (raw) => _counter(raw)),
      persistent: fields['persistent'] is bool ? fields['persistent'] as bool : null,
    ),
    EntityKind.accelerometer => AccelerometerSnapshot(collectedAt: collectedAt,
      value: _components(fields['value'], ['x', 'y', 'z'], (n) => Vector3(n[0], n[1], n[2])),
    ),
    EntityKind.linearAcceleration => LinearAccelerationSnapshot(collectedAt: collectedAt,
      value: _components(fields['value'], ['x', 'y', 'z'], (n) => Vector3(n[0], n[1], n[2])),
    ),
    EntityKind.gravity => GravitySnapshot(collectedAt: collectedAt,
      value: _components(fields['value'], ['x', 'y', 'z'], (n) => Vector3(n[0], n[1], n[2])),
    ),
    EntityKind.gyroscope => GyroscopeSnapshot(collectedAt: collectedAt,
      value: _components(fields['value'], ['x', 'y', 'z'], (n) => Vector3(n[0], n[1], n[2])),
    ),
    EntityKind.magnetometer => MagnetometerSnapshot(collectedAt: collectedAt,
      value: _components(fields['value'], ['x', 'y', 'z'], (n) => Vector3(n[0], n[1], n[2])),
    ),
    EntityKind.relativeOrientation => RelativeOrientationSnapshot(collectedAt: collectedAt,
      value: _rotation(fields['value']),
    ),
    EntityKind.absoluteOrientation => AbsoluteOrientationSnapshot(collectedAt: collectedAt,
      value: _rotation(fields['value']),
    ),
    EntityKind.illuminance => IlluminanceSnapshot(collectedAt: collectedAt,
      value: _number(fields['value']),
    ),
    EntityKind.pressure => PressureSnapshot(collectedAt: collectedAt,
      value: _number(fields['value']),
    ),
    EntityKind.ambientTemperature => AmbientTemperatureSnapshot(collectedAt: collectedAt,
      value: _number(fields['value']),
    ),
    EntityKind.relativeHumidity => RelativeHumiditySnapshot(collectedAt: collectedAt,
      value: _ratio(fields['value']),
    ),
    EntityKind.proximityNear => ProximityNearSnapshot(collectedAt: collectedAt,
      value: fields['value'] is bool ? fields['value'] as bool : null,
    ),
    EntityKind.proximityDistance => ProximityDistanceSnapshot(collectedAt: collectedAt,
      value: _number(fields['value']),
    ),
    EntityKind.relativeAltitude => RelativeAltitudeSnapshot(collectedAt: collectedAt,
      value: _number(fields['value']),
    ),
    EntityKind.hingeAngle => HingeAngleSnapshot(collectedAt: collectedAt,
      value: _number(fields['value']),
    ),
    EntityKind.stepCountSinceBoot => StepCountSinceBootSnapshot(collectedAt: collectedAt,
      value: _counter(fields['value'], signed: true),
    ),
    EntityKind.stepDetected => StepDetectedSnapshot(collectedAt: collectedAt,
      value: fields['value'] is bool ? fields['value'] as bool : null,
    ),
    EntityKind.significantMotion => SignificantMotionSnapshot(collectedAt: collectedAt,
      value: fields['value'] is bool ? fields['value'] as bool : null,
    ),
    EntityKind.humanPresence => HumanPresenceSnapshot(collectedAt: collectedAt,
      value: fields['value'] is bool ? fields['value'] as bool : null,
    ),
  };
  static SensorDescription describe(Map<String, Object?> fields, {DateTime? collectedAt}) => SensorDescription(collectedAt: collectedAt,
    kind: _enumValue(fields['kind'], SensorKind.values),
    name: fields['name'] is String ? fields['name'] as String : null,
    vendor: fields['vendor'] is String ? fields['vendor'] as String : null,
    version: fields['version'] is String ? fields['version'] as String : null,
    reportingMode: _enumValue(fields['reportingMode'], SensorReportingMode.values),
    minimumInterval: _duration(fields['minimumInterval']),
    maximumInterval: _duration(fields['maximumInterval']),
    maximumRange: _number(fields['maximumRange']),
    resolution: _number(fields['resolution']),
    powerMilliamps: _number(fields['powerMilliamps']),
    fifoCapacity: _integer(fields['fifoCapacity']),
  );
  static DeviceSnapshot _hydrate(EntityKind kind, Map<String, Object?> fields, DateTime collectedAt) => switch(kind) {
    EntityKind.deviceInfo => DeviceInfoSnapshot(collectedAt: collectedAt,
      manufacturer: fields['manufacturer'] is String ? fields['manufacturer'] as String : null,
      brand: fields['brand'] is String ? fields['brand'] as String : null,
      modelCode: fields['modelCode'] is String ? fields['modelCode'] as String : null,
      modelName: fields['modelName'] is String ? fields['modelName'] as String : null,
      deviceName: fields['deviceName'] is String ? fields['deviceName'] as String : null,
      formFactor: _enumValue(fields['formFactor'], FormFactor.values),
      product: fields['product'] is String ? fields['product'] as String : null,
      board: fields['board'] is String ? fields['board'] as String : null,
    ),
    EntityKind.os => OsSnapshot(collectedAt: collectedAt,
      family: _enumValue(fields['family'], OsFamily.values),
      name: fields['name'] is String ? fields['name'] as String : null,
      version: fields['version'] is String ? fields['version'] as String : null,
      build: fields['build'] is String ? fields['build'] as String : null,
      kernelName: fields['kernelName'] is String ? fields['kernelName'] as String : null,
      kernelVersion: fields['kernelVersion'] is String ? fields['kernelVersion'] as String : null,
    ),
    EntityKind.runtime => RuntimeSnapshot(collectedAt: collectedAt,
      hostArchitecture: _enumValue(fields['hostArchitecture'], Architecture.values),
      processArchitecture: _enumValue(fields['processArchitecture'], Architecture.values),
      processBitness: _wireInteger(fields['processBitness']),
      supportedAbis: _set(fields['supportedAbis'], (raw) => _enumValue(raw, Abi.values)),
    ),
    EntityKind.cpu => CpuSnapshot(collectedAt: collectedAt,
      model: fields['model'] is String ? fields['model'] as String : null,
      manufacturer: fields['manufacturer'] is String ? fields['manufacturer'] as String : null,
      socModel: fields['socModel'] is String ? fields['socModel'] as String : null,
      socManufacturer: fields['socManufacturer'] is String ? fields['socManufacturer'] as String : null,
      logicalProcessorCount: _wireInteger(fields['logicalProcessorCount']),
      availableLogicalProcessorCount: _wireInteger(fields['availableLogicalProcessorCount']),
      physicalCoreCount: _wireInteger(fields['physicalCoreCount']),
      processorPackageCount: _wireInteger(fields['processorPackageCount']),
    ),
    EntityKind.cpuCore => CpuCoreSnapshot(collectedAt: collectedAt,
      logicalIndex: _wireInteger(fields['logicalIndex']),
      coreIndex: _wireInteger(fields['coreIndex']),
      packageIndex: _wireInteger(fields['packageIndex']),
      online: fields['online'] is bool ? fields['online'] as bool : null,
      currentClockHz: _wireNumber(fields['currentClockHz']),
      maximumClockHz: _wireNumber(fields['maximumClockHz']),
    ),
    EntityKind.ram => RamSnapshot(collectedAt: collectedAt,
      physicalBytes: _wireCounter(fields['physicalBytes']),
      kernelAccessibleBytes: _wireCounter(fields['kernelAccessibleBytes']),
      advertisedBytes: _wireCounter(fields['advertisedBytes']),
      availableBytes: _wireCounter(fields['availableBytes']),
      freeBytes: _wireCounter(fields['freeBytes']),
      lowMemory: fields['lowMemory'] is bool ? fields['lowMemory'] as bool : null,
      lowMemoryThresholdBytes: _wireCounter(fields['lowMemoryThresholdBytes']),
    ),
    EntityKind.processMemory => ProcessMemorySnapshot(collectedAt: collectedAt,
      allocationRemainingBytes: _wireCounter(fields['allocationRemainingBytes']),
    ),
    EntityKind.locale => LocaleSnapshot(collectedAt: collectedAt,
      currentLanguageTag: fields['currentLanguageTag'] is String ? fields['currentLanguageTag'] as String : null,
      preferredLanguageTags: _list(fields['preferredLanguageTags'], (raw) => raw is String ? raw : null),
      systemLanguageTags: _list(fields['systemLanguageTags'], (raw) => raw is String ? raw : null),
      appLanguageTags: _list(fields['appLanguageTags'], (raw) => raw is String ? raw : null),
      regionCode: fields['regionCode'] is String ? fields['regionCode'] as String : null,
      scriptCode: fields['scriptCode'] is String ? fields['scriptCode'] as String : null,
      calendar: fields['calendar'] is String ? fields['calendar'] as String : null,
      numberingSystem: fields['numberingSystem'] is String ? fields['numberingSystem'] as String : null,
      hourCycle: _enumValue(fields['hourCycle'], HourCycle.values),
      firstWeekday: _enumValue(fields['firstWeekday'], Weekday.values),
      measurementSystem: _enumValue(fields['measurementSystem'], MeasurementSystem.values),
    ),
    EntityKind.timeZone => TimeZoneSnapshot(collectedAt: collectedAt,
      ianaId: fields['ianaId'] is String ? fields['ianaId'] as String : null,
      windowsId: fields['windowsId'] is String ? fields['windowsId'] as String : null,
      utcOffsetSeconds: _wireInteger(fields['utcOffsetSeconds']),
      daylightSavingTime: fields['daylightSavingTime'] is bool ? fields['daylightSavingTime'] as bool : null,
    ),
    EntityKind.androidBuild => AndroidBuildSnapshot(collectedAt: collectedAt,
      apiLevel: _wireInteger(fields['apiLevel']),
      securityPatch: fields['securityPatch'] is String ? fields['securityPatch'] as String : null,
      buildId: fields['buildId'] is String ? fields['buildId'] as String : null,
      buildDisplay: fields['buildDisplay'] is String ? fields['buildDisplay'] as String : null,
      buildFingerprint: fields['buildFingerprint'] is String ? fields['buildFingerprint'] as String : null,
      buildType: fields['buildType'] is String ? fields['buildType'] as String : null,
      buildTags: _list(fields['buildTags'], (raw) => raw is String ? raw : null),
      bootloaderVersion: fields['bootloaderVersion'] is String ? fields['bootloaderVersion'] as String : null,
    ),
    EntityKind.androidIdentity => AndroidIdentitySnapshot(collectedAt: collectedAt,
      androidId: fields['androidId'] is String ? fields['androidId'] as String : null,
    ),
    EntityKind.appleVendorIdentity => AppleVendorIdentitySnapshot(collectedAt: collectedAt,
      vendorId: fields['vendorId'] is String ? fields['vendorId'] as String : null,
    ),
    EntityKind.windowsPublisherIdentity => WindowsPublisherIdentitySnapshot(collectedAt: collectedAt,
      publisherId: fields['publisherId'] is String ? fields['publisherId'] as String : null,
      source: _enumValue(fields['source'], WindowsIdentitySource.values),
    ),
    EntityKind.macPlatformIdentity => MacPlatformIdentitySnapshot(collectedAt: collectedAt,
      platformUuid: fields['platformUuid'] is String ? fields['platformUuid'] as String : null,
    ),
    EntityKind.hardwareSerial => HardwareSerialSnapshot(collectedAt: collectedAt,
      serial: fields['serial'] is String ? fields['serial'] as String : null,
    ),
    EntityKind.telephonyIdentity => TelephonyIdentitySnapshot(collectedAt: collectedAt,
      imei: fields['imei'] is String ? fields['imei'] as String : null,
      meid: fields['meid'] is String ? fields['meid'] as String : null,
    ),
    EntityKind.display => DisplaySnapshot(collectedAt: collectedAt,
      label: fields['label'] is String ? fields['label'] as String : null,
      primary: fields['primary'] is bool ? fields['primary'] as bool : null,
      internal: fields['internal'] is bool ? fields['internal'] as bool : null,
      state: _enumValue(fields['state'], DisplayState.values),
      logicalBounds: _wireComponents(fields['logicalBounds'], ['x', 'y', 'width', 'height'], (n) => Rect(n[0], n[1], n[2], n[3])),
      workAreaBounds: _wireComponents(fields['workAreaBounds'], ['x', 'y', 'width', 'height'], (n) => Rect(n[0], n[1], n[2], n[3])),
      pixelSize: _wirePixelSize(fields['pixelSize']),
      physicalSizeMillimeters: _wireComponents(fields['physicalSizeMillimeters'], ['width', 'height'], (n) => Size<double>(n[0], n[1])),
      orientation: _enumValue(fields['orientation'], DisplayOrientation.values),
      rotationDegrees: _wireNumber(fields['rotationDegrees']),
      scaleFactor: _wireNumber(fields['scaleFactor']),
      densityDpi: _wireNumber(fields['densityDpi']),
      currentMode: _wireDisplayMode(fields['currentMode']),
      supportedModes: _list(fields['supportedModes'], (raw) => _wireDisplayMode(raw)),
      maximumRefreshRateHz: _wireNumber(fields['maximumRefreshRateHz']),
      colorDepthBits: _wireInteger(fields['colorDepthBits']),
      colorGamut: _enumValue(fields['colorGamut'], ColorGamut.values),
      hdrFormats: _set(fields['hdrFormats'], (raw) => _enumValue(raw, HdrFormat.values)),
      brightness: _wireNumber(fields['brightness']),
    ),
    EntityKind.viewport => ViewportSnapshot(collectedAt: collectedAt,
      size: _wireComponents(fields['size'], ['width', 'height'], (n) => Size<double>(n[0], n[1])),
      visualViewportSize: _wireComponents(fields['visualViewportSize'], ['width', 'height'], (n) => Size<double>(n[0], n[1])),
      visualViewportScale: _wireNumber(fields['visualViewportScale']),
      safeAreaInsets: _wireComponents(fields['safeAreaInsets'], ['top', 'right', 'bottom', 'left'], (n) => Insets(n[0], n[1], n[2], n[3])),
      textScaleFactor: _wireNumber(fields['textScaleFactor']),
    ),
    EntityKind.power => PowerSnapshot(collectedAt: collectedAt,
      powerSource: _enumValue(fields['powerSource'], PowerSource.values),
      powerSaveMode: fields['powerSaveMode'] is bool ? fields['powerSaveMode'] as bool : null,
      thermalState: _thermal(fields['thermalState']),
    ),
    EntityKind.battery => BatterySnapshot(collectedAt: collectedAt,
      present: fields['present'] is bool ? fields['present'] as bool : null,
      level: _wireNumber(fields['level']),
      charging: fields['charging'] is bool ? fields['charging'] as bool : null,
      state: _enumValue(fields['state'], BatteryState.values),
      timeToFull: _wireDuration(fields['timeToFull']),
      timeToEmpty: _wireDuration(fields['timeToEmpty']),
      voltageMillivolts: _wireNumber(fields['voltageMillivolts']),
      currentMicroamps: _wireNumber(fields['currentMicroamps']),
      averageCurrentMicroamps: _wireNumber(fields['averageCurrentMicroamps']),
      chargeRateMilliwatts: _wireNumber(fields['chargeRateMilliwatts']),
      temperatureCelsius: _wireNumber(fields['temperatureCelsius']),
      chargeCounterMicroampHours: _wireCounter(fields['chargeCounterMicroampHours']),
      remainingEnergyMilliwattHours: _wireNumber(fields['remainingEnergyMilliwattHours']),
      fullChargeEnergyMilliwattHours: _wireNumber(fields['fullChargeEnergyMilliwattHours']),
      designEnergyMilliwattHours: _wireNumber(fields['designEnergyMilliwattHours']),
      technology: fields['technology'] is String ? fields['technology'] as String : null,
      health: _enumValue(fields['health'], BatteryHealth.values),
      cycleCount: _wireCounter(fields['cycleCount']),
    ),
    EntityKind.networkPath => NetworkPathSnapshot(collectedAt: collectedAt,
      connectionState: _enumValue(fields['connectionState'], ConnectionState.values),
      transports: _set(fields['transports'], (raw) => _enumValue(raw, NetworkTransport.values)),
      metered: fields['metered'] is bool ? fields['metered'] as bool : null,
      expensive: fields['expensive'] is bool ? fields['expensive'] as bool : null,
      constrained: fields['constrained'] is bool ? fields['constrained'] as bool : null,
      saveData: fields['saveData'] is bool ? fields['saveData'] as bool : null,
      supportsIpv4: fields['supportsIpv4'] is bool ? fields['supportsIpv4'] as bool : null,
      supportsIpv6: fields['supportsIpv6'] is bool ? fields['supportsIpv6'] as bool : null,
      supportsDns: fields['supportsDns'] is bool ? fields['supportsDns'] as bool : null,
      internetValidated: fields['internetValidated'] is bool ? fields['internetValidated'] as bool : null,
      captivePortal: fields['captivePortal'] is bool ? fields['captivePortal'] as bool : null,
    ),
    EntityKind.networkPerformance => NetworkPerformanceSnapshot(collectedAt: collectedAt,
      downlinkBps: _wireNumber(fields['downlinkBps']),
      uplinkBps: _wireNumber(fields['uplinkBps']),
      roundTripTime: _wireDuration(fields['roundTripTime']),
      effectiveType: _enumValue(fields['effectiveType'], EffectiveConnectionType.values),
      browserOnline: fields['browserOnline'] is bool ? fields['browserOnline'] as bool : null,
    ),
    EntityKind.networkInterface => NetworkInterfaceSnapshot(collectedAt: collectedAt,
      name: fields['name'] is String ? fields['name'] as String : null,
      interfaceType: _enumValue(fields['interfaceType'], NetworkInterfaceType.values),
      operationalState: _enumValue(fields['operationalState'], NetworkOperationalState.values),
      hardwareAddress: fields['hardwareAddress'] is String ? fields['hardwareAddress'] as String : null,
      ipAddresses: _list(fields['ipAddresses'], (raw) => _wireAddressInfo(raw)),
      dnsServers: _list(fields['dnsServers'], (raw) => raw is String ? raw : null),
      gateways: _list(fields['gateways'], (raw) => raw is String ? raw : null),
      routes: _list(fields['routes'], (raw) => _wireRoute(raw)),
      mtuBytes: _wireCounter(fields['mtuBytes']),
    ),
    EntityKind.wifiConnection => WifiConnectionSnapshot(collectedAt: collectedAt,
      ssid: fields['ssid'] is String ? fields['ssid'] as String : null,
      bssid: fields['bssid'] is String ? fields['bssid'] as String : null,
      security: _enumValue(fields['security'], WifiSecurity.values),
      rssiDbm: _wireNumber(fields['rssiDbm']),
      frequencyHz: _wireNumber(fields['frequencyHz']),
      receiveLinkSpeedBps: _wireNumber(fields['receiveLinkSpeedBps']),
      transmitLinkSpeedBps: _wireNumber(fields['transmitLinkSpeedBps']),
    ),
    EntityKind.cellularSubscription => CellularSubscriptionSnapshot(collectedAt: collectedAt,
      slotIndex: _wireInteger(fields['slotIndex']),
      carrierName: fields['carrierName'] is String ? fields['carrierName'] as String : null,
      countryCode: fields['countryCode'] is String ? fields['countryCode'] as String : null,
      mobileCountryCode: fields['mobileCountryCode'] is String ? fields['mobileCountryCode'] as String : null,
      mobileNetworkCode: fields['mobileNetworkCode'] is String ? fields['mobileNetworkCode'] as String : null,
      radioTechnology: _enumValue(fields['radioTechnology'], RadioTechnology.values),
      roaming: fields['roaming'] is bool ? fields['roaming'] as bool : null,
    ),
    EntityKind.storageVolume => StorageVolumeSnapshot(collectedAt: collectedAt,
      name: fields['name'] is String ? fields['name'] as String : null,
      fileSystem: fields['fileSystem'] is String ? fields['fileSystem'] as String : null,
      totalBytes: _wireCounter(fields['totalBytes']),
      freeBytes: _wireCounter(fields['freeBytes']),
      availableToCallerBytes: _wireCounter(fields['availableToCallerBytes']),
      totalBytesForCaller: _wireCounter(fields['totalBytesForCaller']),
      readOnly: fields['readOnly'] is bool ? fields['readOnly'] as bool : null,
      removable: fields['removable'] is bool ? fields['removable'] as bool : null,
      encrypted: fields['encrypted'] is bool ? fields['encrypted'] as bool : null,
      caseSensitive: fields['caseSensitive'] is bool ? fields['caseSensitive'] as bool : null,
      availableForImportantUsageBytes: _wireCounter(fields['availableForImportantUsageBytes']),
      availableForOpportunisticUsageBytes: _wireCounter(fields['availableForOpportunisticUsageBytes']),
      allocatableBytes: _wireCounter(fields['allocatableBytes']),
    ),
    EntityKind.originStorage => OriginStorageSnapshot(collectedAt: collectedAt,
      quotaBytes: _wireCounter(fields['quotaBytes']),
      usageBytes: _wireCounter(fields['usageBytes']),
      usageByCategory: _map(fields['usageByCategory'], (raw) => _enumValue(raw, StorageCategory.values), (raw) => _wireCounter(raw)),
      persistent: fields['persistent'] is bool ? fields['persistent'] as bool : null,
    ),
    EntityKind.accelerometer => AccelerometerSnapshot(collectedAt: collectedAt,
      value: _wireComponents(fields['value'], ['x', 'y', 'z'], (n) => Vector3(n[0], n[1], n[2])),
    ),
    EntityKind.linearAcceleration => LinearAccelerationSnapshot(collectedAt: collectedAt,
      value: _wireComponents(fields['value'], ['x', 'y', 'z'], (n) => Vector3(n[0], n[1], n[2])),
    ),
    EntityKind.gravity => GravitySnapshot(collectedAt: collectedAt,
      value: _wireComponents(fields['value'], ['x', 'y', 'z'], (n) => Vector3(n[0], n[1], n[2])),
    ),
    EntityKind.gyroscope => GyroscopeSnapshot(collectedAt: collectedAt,
      value: _wireComponents(fields['value'], ['x', 'y', 'z'], (n) => Vector3(n[0], n[1], n[2])),
    ),
    EntityKind.magnetometer => MagnetometerSnapshot(collectedAt: collectedAt,
      value: _wireComponents(fields['value'], ['x', 'y', 'z'], (n) => Vector3(n[0], n[1], n[2])),
    ),
    EntityKind.relativeOrientation => RelativeOrientationSnapshot(collectedAt: collectedAt,
      value: _wireRotation(fields['value']),
    ),
    EntityKind.absoluteOrientation => AbsoluteOrientationSnapshot(collectedAt: collectedAt,
      value: _wireRotation(fields['value']),
    ),
    EntityKind.illuminance => IlluminanceSnapshot(collectedAt: collectedAt,
      value: _wireNumber(fields['value']),
    ),
    EntityKind.pressure => PressureSnapshot(collectedAt: collectedAt,
      value: _wireNumber(fields['value']),
    ),
    EntityKind.ambientTemperature => AmbientTemperatureSnapshot(collectedAt: collectedAt,
      value: _wireNumber(fields['value']),
    ),
    EntityKind.relativeHumidity => RelativeHumiditySnapshot(collectedAt: collectedAt,
      value: _wireNumber(fields['value']),
    ),
    EntityKind.proximityNear => ProximityNearSnapshot(collectedAt: collectedAt,
      value: fields['value'] is bool ? fields['value'] as bool : null,
    ),
    EntityKind.proximityDistance => ProximityDistanceSnapshot(collectedAt: collectedAt,
      value: _wireNumber(fields['value']),
    ),
    EntityKind.relativeAltitude => RelativeAltitudeSnapshot(collectedAt: collectedAt,
      value: _wireNumber(fields['value']),
    ),
    EntityKind.hingeAngle => HingeAngleSnapshot(collectedAt: collectedAt,
      value: _wireNumber(fields['value']),
    ),
    EntityKind.stepCountSinceBoot => StepCountSinceBootSnapshot(collectedAt: collectedAt,
      value: _wireCounter(fields['value']),
    ),
    EntityKind.stepDetected => StepDetectedSnapshot(collectedAt: collectedAt,
      value: fields['value'] is bool ? fields['value'] as bool : null,
    ),
    EntityKind.significantMotion => SignificantMotionSnapshot(collectedAt: collectedAt,
      value: fields['value'] is bool ? fields['value'] as bool : null,
    ),
    EntityKind.humanPresence => HumanPresenceSnapshot(collectedAt: collectedAt,
      value: fields['value'] is bool ? fields['value'] as bool : null,
    ),
  };
  static SensorDescription _hydrateDescription(Map<String, Object?> fields, DateTime collectedAt) => SensorDescription(collectedAt: collectedAt,
    kind: _enumValue(fields['kind'], SensorKind.values),
    name: fields['name'] is String ? fields['name'] as String : null,
    vendor: fields['vendor'] is String ? fields['vendor'] as String : null,
    version: fields['version'] is String ? fields['version'] as String : null,
    reportingMode: _enumValue(fields['reportingMode'], SensorReportingMode.values),
    minimumInterval: _wireDuration(fields['minimumInterval']),
    maximumInterval: _wireDuration(fields['maximumInterval']),
    maximumRange: _wireNumber(fields['maximumRange']),
    resolution: _wireNumber(fields['resolution']),
    powerMilliamps: _wireNumber(fields['powerMilliamps']),
    fifoCapacity: _wireInteger(fields['fifoCapacity']),
  );
}
