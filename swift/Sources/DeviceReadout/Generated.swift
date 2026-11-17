// Generated from schema/device-readout.json and schema/enums.json.
import Foundation

public enum FormFactor: String, Sendable, CaseIterable {
    case phone = "Phone"
    case tablet = "Tablet"
    case laptop = "Laptop"
    case desktop = "Desktop"
    case television = "Television"
    case watch = "Watch"
    case automotive = "Automotive"
    case headset = "Headset"
}

public enum OsFamily: String, Sendable, CaseIterable {
    case android = "Android"
    case iOS = "IOS"
    case iPadOS = "IPadOS"
    case windows = "Windows"
    case macOS = "MacOS"
    case linux = "Linux"
    case chromeOS = "ChromeOS"
}

public enum Architecture: String, Sendable, CaseIterable {
    case x86 = "X86"
    case x64 = "X64"
    case arm32 = "Arm32"
    case arm64 = "Arm64"
    case riscV32 = "RiscV32"
    case riscV64 = "RiscV64"
    case wasm32 = "Wasm32"
    case wasm64 = "Wasm64"
}

public enum Abi: String, Sendable, CaseIterable {
    case armeabiV7a = "ArmeabiV7a"
    case arm64V8a = "Arm64V8a"
    case x86 = "X86"
    case x86_64 = "X86_64"
}

public enum HourCycle: String, Sendable, CaseIterable {
    case h11 = "H11"
    case h12 = "H12"
    case h23 = "H23"
    case h24 = "H24"
}

public enum Weekday: String, Sendable, CaseIterable {
    case monday = "Monday"
    case tuesday = "Tuesday"
    case wednesday = "Wednesday"
    case thursday = "Thursday"
    case friday = "Friday"
    case saturday = "Saturday"
    case sunday = "Sunday"
}

public enum MeasurementSystem: String, Sendable, CaseIterable {
    case metric = "Metric"
    case us = "US"
    case uk = "UK"
}

public enum WindowsIdentitySource: String, Sendable, CaseIterable {
    case tpm = "Tpm"
    case uefi = "Uefi"
    case registry = "Registry"
}

public enum DisplayState: String, Sendable, CaseIterable {
    case on = "On"
    case off = "Off"
    case doze = "Doze"
    case dozeSuspended = "DozeSuspended"
    case onSuspended = "OnSuspended"
}

public enum DisplayOrientation: String, Sendable, CaseIterable {
    case portraitPrimary = "PortraitPrimary"
    case portraitSecondary = "PortraitSecondary"
    case landscapePrimary = "LandscapePrimary"
    case landscapeSecondary = "LandscapeSecondary"
}

public enum ColorGamut: String, Sendable, CaseIterable {
    case srgb = "Srgb"
    case displayP3 = "DisplayP3"
    case rec2020 = "Rec2020"
}

public enum HdrFormat: String, Sendable, CaseIterable {
    case hdr10 = "Hdr10"
    case hdr10Plus = "Hdr10Plus"
    case dolbyVision = "DolbyVision"
    case hlg = "Hlg"
}

public enum PowerSource: String, Sendable, CaseIterable {
    case battery = "Battery"
    case external = "External"
    case ups = "Ups"
}

public enum AndroidThermalState: String, Sendable, CaseIterable {
    case none = "None"
    case light = "Light"
    case moderate = "Moderate"
    case severe = "Severe"
    case critical = "Critical"
    case emergency = "Emergency"
    case shutdown = "Shutdown"
}

public enum AppleThermalState: String, Sendable, CaseIterable {
    case nominal = "Nominal"
    case fair = "Fair"
    case serious = "Serious"
    case critical = "Critical"
}

public enum BatteryState: String, Sendable, CaseIterable {
    case charging = "Charging"
    case discharging = "Discharging"
    case full = "Full"
    case notCharging = "NotCharging"
    case idle = "Idle"
}

public enum BatteryHealth: String, Sendable, CaseIterable {
    case good = "Good"
    case overheated = "Overheated"
    case cold = "Cold"
    case dead = "Dead"
    case overVoltage = "OverVoltage"
    case unspecifiedFailure = "UnspecifiedFailure"
}

public enum ConnectionState: String, Sendable, CaseIterable {
    case connected = "Connected"
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case disconnecting = "Disconnecting"
    case suspended = "Suspended"
    case connectionRequired = "ConnectionRequired"
}

public enum NetworkTransport: String, Sendable, CaseIterable {
    case wifi = "Wifi"
    case cellular = "Cellular"
    case ethernet = "Ethernet"
    case bluetooth = "Bluetooth"
    case vpn = "Vpn"
    case usb = "Usb"
    case wifiAware = "WifiAware"
    case lowpan = "Lowpan"
    case thread = "Thread"
    case satellite = "Satellite"
}

public enum EffectiveConnectionType: String, Sendable, CaseIterable {
    case slow2G = "Slow2G"
    case type2G = "Type2G"
    case type3G = "Type3G"
    case type4G = "Type4G"
}

public enum NetworkInterfaceType: String, Sendable, CaseIterable {
    case ethernet = "Ethernet"
    case wifi = "Wifi"
    case cellular = "Cellular"
    case bluetooth = "Bluetooth"
    case loopback = "Loopback"
    case tunnel = "Tunnel"
    case ppp = "Ppp"
    case bridge = "Bridge"
}

public enum NetworkOperationalState: String, Sendable, CaseIterable {
    case up = "Up"
    case down = "Down"
    case testing = "Testing"
    case dormant = "Dormant"
    case notPresent = "NotPresent"
    case lowerLayerDown = "LowerLayerDown"
}

public enum WifiSecurity: String, Sendable, CaseIterable {
    case open = "Open"
    case wep = "Wep"
    case psk = "Psk"
    case eap = "Eap"
    case sae = "Sae"
    case owe = "Owe"
    case wapiPsk = "WapiPsk"
    case wapiCert = "WapiCert"
    case eapWpa3Enterprise = "EapWpa3Enterprise"
    case eapWpa3Enterprise192Bit = "EapWpa3Enterprise192Bit"
    case passpointR1R2 = "PasspointR1R2"
    case passpointR3 = "PasspointR3"
    case dpp = "Dpp"
}

public enum RadioTechnology: String, Sendable, CaseIterable {
    case gsm = "Gsm"
    case gprs = "Gprs"
    case edge = "Edge"
    case cdma = "Cdma"
    case cdma1x = "Cdma1x"
    case evdo0 = "Evdo0"
    case evdoA = "EvdoA"
    case evdoB = "EvdoB"
    case ehrpd = "Ehrpd"
    case umts = "Umts"
    case hsdpa = "Hsdpa"
    case hsupa = "Hsupa"
    case hspa = "Hspa"
    case hspaPlus = "HspaPlus"
    case iden = "Iden"
    case tdScdma = "TdScdma"
    case lte = "Lte"
    case lteCa = "LteCa"
    case nr = "Nr"
    case nrNsa = "NrNsa"
    case nrSa = "NrSa"
    case iwlan = "Iwlan"
}

public enum StorageCategory: String, Sendable, CaseIterable {
    case indexedDB = "IndexedDB"
    case caches = "Caches"
    case serviceWorker = "ServiceWorker"
    case fileSystem = "FileSystem"
    case localStorage = "LocalStorage"
    case sessionStorage = "SessionStorage"
}

public enum SensorReportingMode: String, Sendable, CaseIterable {
    case continuous = "Continuous"
    case onChange = "OnChange"
    case oneShot = "OneShot"
    case specialTrigger = "SpecialTrigger"
}

public enum SensorKind: String, Sendable, CaseIterable {
    case accelerometer = "Accelerometer"
    case linearAcceleration = "LinearAcceleration"
    case gravity = "Gravity"
    case gyroscope = "Gyroscope"
    case magnetometer = "Magnetometer"
    case relativeOrientation = "RelativeOrientation"
    case absoluteOrientation = "AbsoluteOrientation"
    case illuminance = "Illuminance"
    case pressure = "Pressure"
    case ambientTemperature = "AmbientTemperature"
    case relativeHumidity = "RelativeHumidity"
    case proximityNear = "ProximityNear"
    case proximityDistance = "ProximityDistance"
    case relativeAltitude = "RelativeAltitude"
    case hingeAngle = "HingeAngle"
    case stepCountSinceBoot = "StepCountSinceBoot"
    case stepDetected = "StepDetected"
    case significantMotion = "SignificantMotion"
    case humanPresence = "HumanPresence"
}

public enum EntityKind: String, Sendable, CaseIterable {
    case deviceInfo = "DeviceInfo"
    case os = "Os"
    case runtime = "Runtime"
    case cpu = "Cpu"
    case cpuCore = "CpuCore"
    case ram = "Ram"
    case processMemory = "ProcessMemory"
    case locale = "Locale"
    case timeZone = "TimeZone"
    case androidBuild = "AndroidBuild"
    case androidIdentity = "AndroidIdentity"
    case appleVendorIdentity = "AppleVendorIdentity"
    case windowsPublisherIdentity = "WindowsPublisherIdentity"
    case macPlatformIdentity = "MacPlatformIdentity"
    case hardwareSerial = "HardwareSerial"
    case telephonyIdentity = "TelephonyIdentity"
    case display = "Display"
    case viewport = "Viewport"
    case power = "Power"
    case battery = "Battery"
    case networkPath = "NetworkPath"
    case networkPerformance = "NetworkPerformance"
    case networkInterface = "NetworkInterface"
    case wifiConnection = "WifiConnection"
    case cellularSubscription = "CellularSubscription"
    case storageVolume = "StorageVolume"
    case originStorage = "OriginStorage"
    case accelerometer = "Accelerometer"
    case linearAcceleration = "LinearAcceleration"
    case gravity = "Gravity"
    case gyroscope = "Gyroscope"
    case magnetometer = "Magnetometer"
    case relativeOrientation = "RelativeOrientation"
    case absoluteOrientation = "AbsoluteOrientation"
    case illuminance = "Illuminance"
    case pressure = "Pressure"
    case ambientTemperature = "AmbientTemperature"
    case relativeHumidity = "RelativeHumidity"
    case proximityNear = "ProximityNear"
    case proximityDistance = "ProximityDistance"
    case relativeAltitude = "RelativeAltitude"
    case hingeAngle = "HingeAngle"
    case stepCountSinceBoot = "StepCountSinceBoot"
    case stepDetected = "StepDetected"
    case significantMotion = "SignificantMotion"
    case humanPresence = "HumanPresence"
}

public struct DeviceInfoSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 제조사
    public let `manufacturer`: String?
    /// 브랜드
    public let `brand`: String?
    /// 플랫폼의 모델 코드
    public let `modelCode`: String?
    /// 사용자에게 표시할 모델 이름
    public let `modelName`: String?
    /// OS가 공개하는 기기 이름
    public let `deviceName`: String?
    /// 휴대전화·태블릿·노트북 등 기기 형태
    public let `formFactor`: FormFactor?
    /// 제품 식별 이름
    public let `product`: String?
    /// 보드 식별 이름
    public let `board`: String?

    public init(`manufacturer`: String? = nil, `brand`: String? = nil, `modelCode`: String? = nil, `modelName`: String? = nil, `deviceName`: String? = nil, `formFactor`: FormFactor? = nil, `product`: String? = nil, `board`: String? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`manufacturer` = `manufacturer`
        self.`brand` = `brand`
        self.`modelCode` = `modelCode`
        self.`modelName` = `modelName`
        self.`deviceName` = `deviceName`
        self.`formFactor` = `formFactor`
        self.`product` = `product`
        self.`board` = `board`
    }

    func collected() -> any DeviceSnapshot {
        return Self(manufacturer: self.`manufacturer`, brand: self.`brand`, modelCode: self.`modelCode`, modelName: self.`modelName`, deviceName: self.`deviceName`, formFactor: self.`formFactor`, product: self.`product`, board: self.`board`, collectedAt: Date())
    }
}

public struct OsSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 운영체제 계열
    public let `family`: OsFamily?
    /// 운영체제 이름
    public let `name`: String?
    /// 운영체제 버전
    public let `version`: String?
    /// 운영체제 빌드
    public let `build`: String?
    /// 커널 이름
    public let `kernelName`: String?
    /// 커널 버전
    public let `kernelVersion`: String?

    public init(`family`: OsFamily? = nil, `name`: String? = nil, `version`: String? = nil, `build`: String? = nil, `kernelName`: String? = nil, `kernelVersion`: String? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`family` = `family`
        self.`name` = `name`
        self.`version` = `version`
        self.`build` = `build`
        self.`kernelName` = `kernelName`
        self.`kernelVersion` = `kernelVersion`
    }

    func collected() -> any DeviceSnapshot {
        return Self(family: self.`family`, name: self.`name`, version: self.`version`, build: self.`build`, kernelName: self.`kernelName`, kernelVersion: self.`kernelVersion`, collectedAt: Date())
    }
}

public struct RuntimeSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 호스트 시스템 아키텍처
    public let `hostArchitecture`: Architecture?
    /// 현재 프로세스 아키텍처
    public let `processArchitecture`: Architecture?
    /// 현재 프로세스 비트 수
    public let `processBitness`: Int?
    /// 플랫폼이 공개하는 지원 ABI 집합
    public let `supportedAbis`: Set<Abi>?

    public init(`hostArchitecture`: Architecture? = nil, `processArchitecture`: Architecture? = nil, `processBitness`: Int? = nil, `supportedAbis`: Set<Abi>? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`hostArchitecture` = `hostArchitecture`
        self.`processArchitecture` = `processArchitecture`
        self.`processBitness` = `processBitness`
        self.`supportedAbis` = `supportedAbis`
    }

    func collected() -> any DeviceSnapshot {
        return Self(hostArchitecture: self.`hostArchitecture`, processArchitecture: self.`processArchitecture`, processBitness: self.`processBitness`, supportedAbis: self.`supportedAbis`, collectedAt: Date())
    }
}

public struct CpuSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// CPU 모델
    public let `model`: String?
    /// CPU 제조사
    public let `manufacturer`: String?
    /// SoC 모델
    public let `socModel`: String?
    /// SoC 제조사
    public let `socManufacturer`: String?
    /// 전체 논리 프로세서 수
    public let `logicalProcessorCount`: Int?
    /// 현재 실행 환경에 제공되는 논리 프로세서 수
    public let `availableLogicalProcessorCount`: Int?
    /// 물리 코어 수
    public let `physicalCoreCount`: Int?
    /// 프로세서 패키지 수
    public let `processorPackageCount`: Int?

    public init(`model`: String? = nil, `manufacturer`: String? = nil, `socModel`: String? = nil, `socManufacturer`: String? = nil, `logicalProcessorCount`: Int? = nil, `availableLogicalProcessorCount`: Int? = nil, `physicalCoreCount`: Int? = nil, `processorPackageCount`: Int? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`model` = `model`
        self.`manufacturer` = `manufacturer`
        self.`socModel` = `socModel`
        self.`socManufacturer` = `socManufacturer`
        self.`logicalProcessorCount` = `logicalProcessorCount`
        self.`availableLogicalProcessorCount` = `availableLogicalProcessorCount`
        self.`physicalCoreCount` = `physicalCoreCount`
        self.`processorPackageCount` = `processorPackageCount`
    }

    func collected() -> any DeviceSnapshot {
        return Self(model: self.`model`, manufacturer: self.`manufacturer`, socModel: self.`socModel`, socManufacturer: self.`socManufacturer`, logicalProcessorCount: self.`logicalProcessorCount`, availableLogicalProcessorCount: self.`availableLogicalProcessorCount`, physicalCoreCount: self.`physicalCoreCount`, processorPackageCount: self.`processorPackageCount`, collectedAt: Date())
    }
}

public struct CpuCoreSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 논리 프로세서 인덱스
    public let `logicalIndex`: Int?
    /// 소속 물리 코어 인덱스
    public let `coreIndex`: Int?
    /// 소속 프로세서 패키지 인덱스
    public let `packageIndex`: Int?
    /// OS에서 사용 가능한 온라인 상태
    public let `online`: Bool?
    /// 현재 클록 주파수
    public let `currentClockHz`: Double?
    /// 플랫폼이 보고하는 최대 클록 주파수
    public let `maximumClockHz`: Double?

    public init(`logicalIndex`: Int? = nil, `coreIndex`: Int? = nil, `packageIndex`: Int? = nil, `online`: Bool? = nil, `currentClockHz`: Double? = nil, `maximumClockHz`: Double? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`logicalIndex` = `logicalIndex`
        self.`coreIndex` = `coreIndex`
        self.`packageIndex` = `packageIndex`
        self.`online` = `online`
        self.`currentClockHz` = `currentClockHz`
        self.`maximumClockHz` = `maximumClockHz`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField4 = SnapshotRules.finite(self.`currentClockHz`)
        let normalizedField5 = SnapshotRules.finite(self.`maximumClockHz`)
        return Self(logicalIndex: self.`logicalIndex`, coreIndex: self.`coreIndex`, packageIndex: self.`packageIndex`, online: self.`online`, currentClockHz: normalizedField4, maximumClockHz: normalizedField5, collectedAt: Date())
    }
}

public struct RamSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 설치된 물리 RAM 용량
    public let `physicalBytes`: UInt64?
    /// 커널이 접근 가능한 RAM 용량
    public let `kernelAccessibleBytes`: UInt64?
    /// 플랫폼이 외부에 공개하는 표기용 RAM 용량
    public let `advertisedBytes`: UInt64?
    /// OS 정의상 사용 가능한 메모리
    public let `availableBytes`: UInt64?
    /// OS 정의상 비어 있는 메모리
    public let `freeBytes`: UInt64?
    /// OS가 보고하는 메모리 부족 상태
    public let `lowMemory`: Bool?
    /// OS가 공개하는 메모리 부족 기준 용량
    public let `lowMemoryThresholdBytes`: UInt64?

    public init(`physicalBytes`: UInt64? = nil, `kernelAccessibleBytes`: UInt64? = nil, `advertisedBytes`: UInt64? = nil, `availableBytes`: UInt64? = nil, `freeBytes`: UInt64? = nil, `lowMemory`: Bool? = nil, `lowMemoryThresholdBytes`: UInt64? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`physicalBytes` = `physicalBytes`
        self.`kernelAccessibleBytes` = `kernelAccessibleBytes`
        self.`advertisedBytes` = `advertisedBytes`
        self.`availableBytes` = `availableBytes`
        self.`freeBytes` = `freeBytes`
        self.`lowMemory` = `lowMemory`
        self.`lowMemoryThresholdBytes` = `lowMemoryThresholdBytes`
    }

    func collected() -> any DeviceSnapshot {
        return Self(physicalBytes: self.`physicalBytes`, kernelAccessibleBytes: self.`kernelAccessibleBytes`, advertisedBytes: self.`advertisedBytes`, availableBytes: self.`availableBytes`, freeBytes: self.`freeBytes`, lowMemory: self.`lowMemory`, lowMemoryThresholdBytes: self.`lowMemoryThresholdBytes`, collectedAt: Date())
    }
}

public struct ProcessMemorySnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 현재 앱이 추가로 할당할 수 있다고 플랫폼이 보고하는 메모리
    public let `allocationRemainingBytes`: UInt64?

    public init(`allocationRemainingBytes`: UInt64? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`allocationRemainingBytes` = `allocationRemainingBytes`
    }

    func collected() -> any DeviceSnapshot {
        return Self(allocationRemainingBytes: self.`allocationRemainingBytes`, collectedAt: Date())
    }
}

public struct LocaleSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 현재 유효한 언어 태그
    public let `currentLanguageTag`: String?
    /// 선호 언어 태그. 원래 우선순위 보존
    public let `preferredLanguageTags`: [String]?
    /// 시스템 언어 태그 목록
    public let `systemLanguageTags`: [String]?
    /// 앱에 적용된 언어 태그 목록
    public let `appLanguageTags`: [String]?
    /// 로케일 지역 코드
    public let `regionCode`: String?
    /// 문자 체계 코드
    public let `scriptCode`: String?
    /// 달력 체계 식별자
    public let `calendar`: String?
    /// 숫자 표기 체계 식별자
    public let `numberingSystem`: String?
    /// 시간 표기 주기
    public let `hourCycle`: HourCycle?
    /// 한 주의 첫 요일
    public let `firstWeekday`: Weekday?
    /// 도량형 체계
    public let `measurementSystem`: MeasurementSystem?

    public init(`currentLanguageTag`: String? = nil, `preferredLanguageTags`: [String]? = nil, `systemLanguageTags`: [String]? = nil, `appLanguageTags`: [String]? = nil, `regionCode`: String? = nil, `scriptCode`: String? = nil, `calendar`: String? = nil, `numberingSystem`: String? = nil, `hourCycle`: HourCycle? = nil, `firstWeekday`: Weekday? = nil, `measurementSystem`: MeasurementSystem? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`currentLanguageTag` = `currentLanguageTag`
        self.`preferredLanguageTags` = `preferredLanguageTags`
        self.`systemLanguageTags` = `systemLanguageTags`
        self.`appLanguageTags` = `appLanguageTags`
        self.`regionCode` = `regionCode`
        self.`scriptCode` = `scriptCode`
        self.`calendar` = `calendar`
        self.`numberingSystem` = `numberingSystem`
        self.`hourCycle` = `hourCycle`
        self.`firstWeekday` = `firstWeekday`
        self.`measurementSystem` = `measurementSystem`
    }

    func collected() -> any DeviceSnapshot {
        return Self(currentLanguageTag: self.`currentLanguageTag`, preferredLanguageTags: self.`preferredLanguageTags`, systemLanguageTags: self.`systemLanguageTags`, appLanguageTags: self.`appLanguageTags`, regionCode: self.`regionCode`, scriptCode: self.`scriptCode`, calendar: self.`calendar`, numberingSystem: self.`numberingSystem`, hourCycle: self.`hourCycle`, firstWeekday: self.`firstWeekday`, measurementSystem: self.`measurementSystem`, collectedAt: Date())
    }
}

public struct TimeZoneSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// IANA 시간대 식별자
    public let `ianaId`: String?
    /// Windows 시간대 식별자
    public let `windowsId`: String?
    /// 수집 시점의 UTC 오프셋 초
    public let `utcOffsetSeconds`: Int?
    /// 수집 시점의 서머타임 적용 여부
    public let `daylightSavingTime`: Bool?

    public init(`ianaId`: String? = nil, `windowsId`: String? = nil, `utcOffsetSeconds`: Int? = nil, `daylightSavingTime`: Bool? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`ianaId` = `ianaId`
        self.`windowsId` = `windowsId`
        self.`utcOffsetSeconds` = `utcOffsetSeconds`
        self.`daylightSavingTime` = `daylightSavingTime`
    }

    func collected() -> any DeviceSnapshot {
        return Self(ianaId: self.`ianaId`, windowsId: self.`windowsId`, utcOffsetSeconds: self.`utcOffsetSeconds`, daylightSavingTime: self.`daylightSavingTime`, collectedAt: Date())
    }
}

public struct AndroidBuildSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// Android API 수준
    public let `apiLevel`: Int?
    /// 플랫폼이 공개하는 보안 패치 날짜
    public let `securityPatch`: String?
    /// 빌드 ID
    public let `buildId`: String?
    /// 표시용 빌드 문자열
    public let `buildDisplay`: String?
    /// OS 빌드를 식별하는 fingerprint
    public let `buildFingerprint`: String?
    /// 빌드 유형
    public let `buildType`: String?
    /// 빌드 태그
    public let `buildTags`: [String]?
    /// 부트로더 버전
    public let `bootloaderVersion`: String?

    public init(`apiLevel`: Int? = nil, `securityPatch`: String? = nil, `buildId`: String? = nil, `buildDisplay`: String? = nil, `buildFingerprint`: String? = nil, `buildType`: String? = nil, `buildTags`: [String]? = nil, `bootloaderVersion`: String? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`apiLevel` = `apiLevel`
        self.`securityPatch` = `securityPatch`
        self.`buildId` = `buildId`
        self.`buildDisplay` = `buildDisplay`
        self.`buildFingerprint` = `buildFingerprint`
        self.`buildType` = `buildType`
        self.`buildTags` = `buildTags`
        self.`bootloaderVersion` = `bootloaderVersion`
    }

    func collected() -> any DeviceSnapshot {
        return Self(apiLevel: self.`apiLevel`, securityPatch: self.`securityPatch`, buildId: self.`buildId`, buildDisplay: self.`buildDisplay`, buildFingerprint: self.`buildFingerprint`, buildType: self.`buildType`, buildTags: self.`buildTags`, bootloaderVersion: self.`bootloaderVersion`, collectedAt: Date())
    }
}

public struct AndroidIdentitySnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 플랫폼이 제공하는 ANDROID_ID
    public let `androidId`: String?

    public init(`androidId`: String? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`androidId` = `androidId`
    }

    func collected() -> any DeviceSnapshot {
        return Self(androidId: self.`androidId`, collectedAt: Date())
    }
}

public struct AppleVendorIdentitySnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// vendor 범위의 식별자
    public let `vendorId`: String?

    public init(`vendorId`: String? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`vendorId` = `vendorId`
    }

    func collected() -> any DeviceSnapshot {
        return Self(vendorId: self.`vendorId`, collectedAt: Date())
    }
}

public struct WindowsPublisherIdentitySnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// publisher 범위의 시스템 식별자
    public let `publisherId`: String?
    /// 식별자 생성에 사용된 플랫폼 소스
    public let `source`: WindowsIdentitySource?

    public init(`publisherId`: String? = nil, `source`: WindowsIdentitySource? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`publisherId` = `publisherId`
        self.`source` = `source`
    }

    func collected() -> any DeviceSnapshot {
        return Self(publisherId: self.`publisherId`, source: self.`source`, collectedAt: Date())
    }
}

public struct MacPlatformIdentitySnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 플랫폼 UUID
    public let `platformUuid`: String?

    public init(`platformUuid`: String? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`platformUuid` = `platformUuid`
    }

    func collected() -> any DeviceSnapshot {
        return Self(platformUuid: self.`platformUuid`, collectedAt: Date())
    }
}

public struct HardwareSerialSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 플랫폼이 허용해 공개하는 하드웨어 일련번호
    public let `serial`: String?

    public init(`serial`: String? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`serial` = `serial`
    }

    func collected() -> any DeviceSnapshot {
        return Self(serial: self.`serial`, collectedAt: Date())
    }
}

public struct TelephonyIdentitySnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 접근이 허용된 IMEI
    public let `imei`: String?
    /// 접근이 허용된 MEID
    public let `meid`: String?

    public init(`imei`: String? = nil, `meid`: String? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`imei` = `imei`
        self.`meid` = `meid`
    }

    func collected() -> any DeviceSnapshot {
        return Self(imei: self.`imei`, meid: self.`meid`, collectedAt: Date())
    }
}

public struct DisplaySnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 화면 표시 이름
    public let `label`: String?
    /// 기본 화면 여부
    public let `primary`: Bool?
    /// 내장 화면 여부
    public let `internal`: Bool?
    /// 화면의 전원·표시 상태
    public let `state`: DisplayState?
    /// 화면의 논리 좌표 영역
    public let `logicalBounds`: Rect?
    /// 사용 가능한 작업 영역
    public let `workAreaBounds`: Rect?
    /// 픽셀 크기
    public let `pixelSize`: Size<Int>?
    /// 물리 크기 mm
    public let `physicalSizeMillimeters`: Size<Double>?
    /// 화면 방향
    public let `orientation`: DisplayOrientation?
    /// 기준 방향에 대한 회전 각도
    public let `rotationDegrees`: Double?
    /// 논리 단위와 픽셀 사이 배율
    public let `scaleFactor`: Double?
    /// 인치당 픽셀 밀도
    public let `densityDpi`: Double?
    /// 현재 화면 모드
    public let `currentMode`: DisplayMode?
    /// 지원 화면 모드 목록
    public let `supportedModes`: [DisplayMode]?
    /// 플랫폼이 공개하는 최대 주사율
    public let `maximumRefreshRateHz`: Double?
    /// 플랫폼이 보고하는 색 깊이
    public let `colorDepthBits`: Int?
    /// 플랫폼이 보고하는 화면 색역
    public let `colorGamut`: ColorGamut?
    /// 지원 HDR 형식 집합
    public let `hdrFormats`: Set<HdrFormat>?
    /// 밝기 0–1
    public let `brightness`: Double?

    public init(`label`: String? = nil, `primary`: Bool? = nil, `internal`: Bool? = nil, `state`: DisplayState? = nil, `logicalBounds`: Rect? = nil, `workAreaBounds`: Rect? = nil, `pixelSize`: Size<Int>? = nil, `physicalSizeMillimeters`: Size<Double>? = nil, `orientation`: DisplayOrientation? = nil, `rotationDegrees`: Double? = nil, `scaleFactor`: Double? = nil, `densityDpi`: Double? = nil, `currentMode`: DisplayMode? = nil, `supportedModes`: [DisplayMode]? = nil, `maximumRefreshRateHz`: Double? = nil, `colorDepthBits`: Int? = nil, `colorGamut`: ColorGamut? = nil, `hdrFormats`: Set<HdrFormat>? = nil, `brightness`: Double? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`label` = `label`
        self.`primary` = `primary`
        self.`internal` = `internal`
        self.`state` = `state`
        self.`logicalBounds` = `logicalBounds`
        self.`workAreaBounds` = `workAreaBounds`
        self.`pixelSize` = `pixelSize`
        self.`physicalSizeMillimeters` = `physicalSizeMillimeters`
        self.`orientation` = `orientation`
        self.`rotationDegrees` = `rotationDegrees`
        self.`scaleFactor` = `scaleFactor`
        self.`densityDpi` = `densityDpi`
        self.`currentMode` = `currentMode`
        self.`supportedModes` = `supportedModes`
        self.`maximumRefreshRateHz` = `maximumRefreshRateHz`
        self.`colorDepthBits` = `colorDepthBits`
        self.`colorGamut` = `colorGamut`
        self.`hdrFormats` = `hdrFormats`
        self.`brightness` = `brightness`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField4 = SnapshotRules.rectangle(self.`logicalBounds`)
        let normalizedField5 = SnapshotRules.rectangle(self.`workAreaBounds`)
        let normalizedField7 = SnapshotRules.size(self.`physicalSizeMillimeters`)
        let normalizedField9 = SnapshotRules.finite(self.`rotationDegrees`)
        let normalizedField10 = SnapshotRules.finite(self.`scaleFactor`)
        let normalizedField11 = SnapshotRules.finite(self.`densityDpi`)
        let normalizedField12 = SnapshotRules.displayMode(self.`currentMode`)
        let normalizedField13 = SnapshotRules.displayModes(self.`supportedModes`)
        let normalizedField14 = SnapshotRules.finite(self.`maximumRefreshRateHz`)
        let normalizedField18 = SnapshotRules.ratio(self.`brightness`)
        return Self(label: self.`label`, primary: self.`primary`, internal: self.`internal`, state: self.`state`, logicalBounds: normalizedField4, workAreaBounds: normalizedField5, pixelSize: self.`pixelSize`, physicalSizeMillimeters: normalizedField7, orientation: self.`orientation`, rotationDegrees: normalizedField9, scaleFactor: normalizedField10, densityDpi: normalizedField11, currentMode: normalizedField12, supportedModes: normalizedField13, maximumRefreshRateHz: normalizedField14, colorDepthBits: self.`colorDepthBits`, colorGamut: self.`colorGamut`, hdrFormats: self.`hdrFormats`, brightness: normalizedField18, collectedAt: Date())
    }
}

public struct ViewportSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 레이아웃 뷰포트 크기
    public let `size`: Size<Double>?
    /// 현재 보이는 뷰포트 크기
    public let `visualViewportSize`: Size<Double>?
    /// 시각 뷰포트 확대 배율
    public let `visualViewportScale`: Double?
    /// 안전 영역 여백
    public let `safeAreaInsets`: Insets?
    /// 텍스트 확대 배율
    public let `textScaleFactor`: Double?

    public init(`size`: Size<Double>? = nil, `visualViewportSize`: Size<Double>? = nil, `visualViewportScale`: Double? = nil, `safeAreaInsets`: Insets? = nil, `textScaleFactor`: Double? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`size` = `size`
        self.`visualViewportSize` = `visualViewportSize`
        self.`visualViewportScale` = `visualViewportScale`
        self.`safeAreaInsets` = `safeAreaInsets`
        self.`textScaleFactor` = `textScaleFactor`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField0 = SnapshotRules.size(self.`size`)
        let normalizedField1 = SnapshotRules.size(self.`visualViewportSize`)
        let normalizedField2 = SnapshotRules.finite(self.`visualViewportScale`)
        let normalizedField3 = SnapshotRules.insets(self.`safeAreaInsets`)
        let normalizedField4 = SnapshotRules.finite(self.`textScaleFactor`)
        return Self(size: normalizedField0, visualViewportSize: normalizedField1, visualViewportScale: normalizedField2, safeAreaInsets: normalizedField3, textScaleFactor: normalizedField4, collectedAt: Date())
    }
}

public struct PowerSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 전원 공급원
    public let `powerSource`: PowerSource?
    /// 절전 모드 적용 여부
    public let `powerSaveMode`: Bool?
    /// 플랫폼별 열 상태 타입의 합집합
    public let `thermalState`: ThermalState?

    public init(`powerSource`: PowerSource? = nil, `powerSaveMode`: Bool? = nil, `thermalState`: ThermalState? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`powerSource` = `powerSource`
        self.`powerSaveMode` = `powerSaveMode`
        self.`thermalState` = `thermalState`
    }

    func collected() -> any DeviceSnapshot {
        return Self(powerSource: self.`powerSource`, powerSaveMode: self.`powerSaveMode`, thermalState: self.`thermalState`, collectedAt: Date())
    }
}

public struct BatterySnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 배터리 존재 여부
    public let `present`: Bool?
    /// 충전 잔량 비율 0–1
    public let `level`: Double?
    /// 충전 중 여부
    public let `charging`: Bool?
    /// 충전·방전 등 상태
    public let `state`: BatteryState?
    /// 완충까지 남은 시간
    public let `timeToFull`: Duration?
    /// 소진까지 남은 시간
    public let `timeToEmpty`: Duration?
    /// 전압 mV
    public let `voltageMillivolts`: Double?
    /// 현재 전류 μA
    public let `currentMicroamps`: Double?
    /// 평균 전류 μA
    public let `averageCurrentMicroamps`: Double?
    /// 충전·방전 전력 mW
    public let `chargeRateMilliwatts`: Double?
    /// 배터리 온도 °C
    public let `temperatureCelsius`: Double?
    /// 전하량 μAh
    public let `chargeCounterMicroampHours`: Int64?
    /// 남은 에너지 mWh
    public let `remainingEnergyMilliwattHours`: Double?
    /// 현재 완충 용량 mWh
    public let `fullChargeEnergyMilliwattHours`: Double?
    /// 설계 용량 mWh
    public let `designEnergyMilliwattHours`: Double?
    /// 배터리 기술·화학 종류
    public let `technology`: String?
    /// 플랫폼이 보고하는 상태·고장 종류
    public let `health`: BatteryHealth?
    /// 충전 사이클 수
    public let `cycleCount`: Int64?

    public init(`present`: Bool? = nil, `level`: Double? = nil, `charging`: Bool? = nil, `state`: BatteryState? = nil, `timeToFull`: Duration? = nil, `timeToEmpty`: Duration? = nil, `voltageMillivolts`: Double? = nil, `currentMicroamps`: Double? = nil, `averageCurrentMicroamps`: Double? = nil, `chargeRateMilliwatts`: Double? = nil, `temperatureCelsius`: Double? = nil, `chargeCounterMicroampHours`: Int64? = nil, `remainingEnergyMilliwattHours`: Double? = nil, `fullChargeEnergyMilliwattHours`: Double? = nil, `designEnergyMilliwattHours`: Double? = nil, `technology`: String? = nil, `health`: BatteryHealth? = nil, `cycleCount`: Int64? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`present` = `present`
        self.`level` = `level`
        self.`charging` = `charging`
        self.`state` = `state`
        self.`timeToFull` = `timeToFull`
        self.`timeToEmpty` = `timeToEmpty`
        self.`voltageMillivolts` = `voltageMillivolts`
        self.`currentMicroamps` = `currentMicroamps`
        self.`averageCurrentMicroamps` = `averageCurrentMicroamps`
        self.`chargeRateMilliwatts` = `chargeRateMilliwatts`
        self.`temperatureCelsius` = `temperatureCelsius`
        self.`chargeCounterMicroampHours` = `chargeCounterMicroampHours`
        self.`remainingEnergyMilliwattHours` = `remainingEnergyMilliwattHours`
        self.`fullChargeEnergyMilliwattHours` = `fullChargeEnergyMilliwattHours`
        self.`designEnergyMilliwattHours` = `designEnergyMilliwattHours`
        self.`technology` = `technology`
        self.`health` = `health`
        self.`cycleCount` = `cycleCount`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField1 = SnapshotRules.ratio(self.`level`)
        let normalizedField4 = SnapshotRules.duration(self.`timeToFull`)
        let normalizedField5 = SnapshotRules.duration(self.`timeToEmpty`)
        let normalizedField6 = SnapshotRules.finite(self.`voltageMillivolts`)
        let normalizedField7 = SnapshotRules.finite(self.`currentMicroamps`)
        let normalizedField8 = SnapshotRules.finite(self.`averageCurrentMicroamps`)
        let normalizedField9 = SnapshotRules.finite(self.`chargeRateMilliwatts`)
        let normalizedField10 = SnapshotRules.finite(self.`temperatureCelsius`)
        let normalizedField12 = SnapshotRules.finite(self.`remainingEnergyMilliwattHours`)
        let normalizedField13 = SnapshotRules.finite(self.`fullChargeEnergyMilliwattHours`)
        let normalizedField14 = SnapshotRules.finite(self.`designEnergyMilliwattHours`)
        return Self(present: self.`present`, level: normalizedField1, charging: self.`charging`, state: self.`state`, timeToFull: normalizedField4, timeToEmpty: normalizedField5, voltageMillivolts: normalizedField6, currentMicroamps: normalizedField7, averageCurrentMicroamps: normalizedField8, chargeRateMilliwatts: normalizedField9, temperatureCelsius: normalizedField10, chargeCounterMicroampHours: self.`chargeCounterMicroampHours`, remainingEnergyMilliwattHours: normalizedField12, fullChargeEnergyMilliwattHours: normalizedField13, designEnergyMilliwattHours: normalizedField14, technology: self.`technology`, health: self.`health`, cycleCount: self.`cycleCount`, collectedAt: Date())
    }
}

public struct NetworkPathSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 로컬 연결 경로 상태
    public let `connectionState`: ConnectionState?
    /// 경로에 사용되는 전송 수단 집합
    public let `transports`: Set<NetworkTransport>?
    /// 사용량 제한·종량제 네트워크 여부
    public let `metered`: Bool?
    /// 플랫폼이 비용이 큰 경로로 분류하는지 여부
    public let `expensive`: Bool?
    /// 플랫폼의 제한된 데이터 모드 여부
    public let `constrained`: Bool?
    /// 사용자의 데이터 절약 선호
    public let `saveData`: Bool?
    /// 경로의 IPv4 지원 여부
    public let `supportsIpv4`: Bool?
    /// 경로의 IPv6 지원 여부
    public let `supportsIpv6`: Bool?
    /// 경로의 DNS 지원 여부
    public let `supportsDns`: Bool?
    /// OS가 보고하는 인터넷 검증 상태
    public let `internetValidated`: Bool?
    /// OS가 보고하는 captive portal 상태
    public let `captivePortal`: Bool?

    public init(`connectionState`: ConnectionState? = nil, `transports`: Set<NetworkTransport>? = nil, `metered`: Bool? = nil, `expensive`: Bool? = nil, `constrained`: Bool? = nil, `saveData`: Bool? = nil, `supportsIpv4`: Bool? = nil, `supportsIpv6`: Bool? = nil, `supportsDns`: Bool? = nil, `internetValidated`: Bool? = nil, `captivePortal`: Bool? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`connectionState` = `connectionState`
        self.`transports` = `transports`
        self.`metered` = `metered`
        self.`expensive` = `expensive`
        self.`constrained` = `constrained`
        self.`saveData` = `saveData`
        self.`supportsIpv4` = `supportsIpv4`
        self.`supportsIpv6` = `supportsIpv6`
        self.`supportsDns` = `supportsDns`
        self.`internetValidated` = `internetValidated`
        self.`captivePortal` = `captivePortal`
    }

    func collected() -> any DeviceSnapshot {
        return Self(connectionState: self.`connectionState`, transports: self.`transports`, metered: self.`metered`, expensive: self.`expensive`, constrained: self.`constrained`, saveData: self.`saveData`, supportsIpv4: self.`supportsIpv4`, supportsIpv6: self.`supportsIpv6`, supportsDns: self.`supportsDns`, internetValidated: self.`internetValidated`, captivePortal: self.`captivePortal`, collectedAt: Date())
    }
}

public struct NetworkPerformanceSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 하향 전송 속도 bit/s
    public let `downlinkBps`: Double?
    /// 상향 전송 속도 bit/s
    public let `uplinkBps`: Double?
    /// 왕복 시간
    public let `roundTripTime`: Duration?
    /// 플랫폼의 네트워크 성능 분류
    public let `effectiveType`: EffectiveConnectionType?
    /// 브라우저가 보고하는 온라인 상태
    public let `browserOnline`: Bool?

    public init(`downlinkBps`: Double? = nil, `uplinkBps`: Double? = nil, `roundTripTime`: Duration? = nil, `effectiveType`: EffectiveConnectionType? = nil, `browserOnline`: Bool? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`downlinkBps` = `downlinkBps`
        self.`uplinkBps` = `uplinkBps`
        self.`roundTripTime` = `roundTripTime`
        self.`effectiveType` = `effectiveType`
        self.`browserOnline` = `browserOnline`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField0 = SnapshotRules.finite(self.`downlinkBps`)
        let normalizedField1 = SnapshotRules.finite(self.`uplinkBps`)
        let normalizedField2 = SnapshotRules.duration(self.`roundTripTime`)
        return Self(downlinkBps: normalizedField0, uplinkBps: normalizedField1, roundTripTime: normalizedField2, effectiveType: self.`effectiveType`, browserOnline: self.`browserOnline`, collectedAt: Date())
    }
}

public struct NetworkInterfaceSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 인터페이스 이름
    public let `name`: String?
    /// 인터페이스 종류
    public let `interfaceType`: NetworkInterfaceType?
    /// 인터페이스 동작 상태
    public let `operationalState`: NetworkOperationalState?
    /// 플랫폼이 허용해 공개하는 하드웨어 주소
    public let `hardwareAddress`: String?
    /// 인터페이스 IP 주소 정보
    public let `ipAddresses`: [IpAddressInfo]?
    /// DNS 서버 주소 목록
    public let `dnsServers`: [String]?
    /// 게이트웨이 주소 목록
    public let `gateways`: [String]?
    /// 경로 정보 목록
    public let `routes`: [NetworkRoute]?
    /// MTU byte 크기
    public let `mtuBytes`: UInt64?

    public init(`name`: String? = nil, `interfaceType`: NetworkInterfaceType? = nil, `operationalState`: NetworkOperationalState? = nil, `hardwareAddress`: String? = nil, `ipAddresses`: [IpAddressInfo]? = nil, `dnsServers`: [String]? = nil, `gateways`: [String]? = nil, `routes`: [NetworkRoute]? = nil, `mtuBytes`: UInt64? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`name` = `name`
        self.`interfaceType` = `interfaceType`
        self.`operationalState` = `operationalState`
        self.`hardwareAddress` = `hardwareAddress`
        self.`ipAddresses` = `ipAddresses`
        self.`dnsServers` = `dnsServers`
        self.`gateways` = `gateways`
        self.`routes` = `routes`
        self.`mtuBytes` = `mtuBytes`
    }

    func collected() -> any DeviceSnapshot {
        return Self(name: self.`name`, interfaceType: self.`interfaceType`, operationalState: self.`operationalState`, hardwareAddress: self.`hardwareAddress`, ipAddresses: self.`ipAddresses`, dnsServers: self.`dnsServers`, gateways: self.`gateways`, routes: self.`routes`, mtuBytes: self.`mtuBytes`, collectedAt: Date())
    }
}

public struct WifiConnectionSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 현재 연결 SSID
    public let `ssid`: String?
    /// 현재 연결 BSSID
    public let `bssid`: String?
    /// 현재 연결에서 선택된 인증 방식
    public let `security`: WifiSecurity?
    /// 수신 신호 세기 dBm
    public let `rssiDbm`: Double?
    /// 현재 연결 주파수 Hz
    public let `frequencyHz`: Double?
    /// 수신 링크 속도 bit/s
    public let `receiveLinkSpeedBps`: Double?
    /// 송신 링크 속도 bit/s
    public let `transmitLinkSpeedBps`: Double?

    public init(`ssid`: String? = nil, `bssid`: String? = nil, `security`: WifiSecurity? = nil, `rssiDbm`: Double? = nil, `frequencyHz`: Double? = nil, `receiveLinkSpeedBps`: Double? = nil, `transmitLinkSpeedBps`: Double? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`ssid` = `ssid`
        self.`bssid` = `bssid`
        self.`security` = `security`
        self.`rssiDbm` = `rssiDbm`
        self.`frequencyHz` = `frequencyHz`
        self.`receiveLinkSpeedBps` = `receiveLinkSpeedBps`
        self.`transmitLinkSpeedBps` = `transmitLinkSpeedBps`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField3 = SnapshotRules.finite(self.`rssiDbm`)
        let normalizedField4 = SnapshotRules.finite(self.`frequencyHz`)
        let normalizedField5 = SnapshotRules.finite(self.`receiveLinkSpeedBps`)
        let normalizedField6 = SnapshotRules.finite(self.`transmitLinkSpeedBps`)
        return Self(ssid: self.`ssid`, bssid: self.`bssid`, security: self.`security`, rssiDbm: normalizedField3, frequencyHz: normalizedField4, receiveLinkSpeedBps: normalizedField5, transmitLinkSpeedBps: normalizedField6, collectedAt: Date())
    }
}

public struct CellularSubscriptionSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 슬롯 인덱스
    public let `slotIndex`: Int?
    /// 통신사 이름
    public let `carrierName`: String?
    /// 플랫폼이 보고하는 국가 코드
    public let `countryCode`: String?
    /// MCC. 앞자리 0을 보존하는 문자열
    public let `mobileCountryCode`: String?
    /// MNC. 앞자리 0을 보존하는 문자열
    public let `mobileNetworkCode`: String?
    /// 현재 데이터 연결의 무선 기술
    public let `radioTechnology`: RadioTechnology?
    /// 로밍 여부
    public let `roaming`: Bool?

    public init(`slotIndex`: Int? = nil, `carrierName`: String? = nil, `countryCode`: String? = nil, `mobileCountryCode`: String? = nil, `mobileNetworkCode`: String? = nil, `radioTechnology`: RadioTechnology? = nil, `roaming`: Bool? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`slotIndex` = `slotIndex`
        self.`carrierName` = `carrierName`
        self.`countryCode` = `countryCode`
        self.`mobileCountryCode` = `mobileCountryCode`
        self.`mobileNetworkCode` = `mobileNetworkCode`
        self.`radioTechnology` = `radioTechnology`
        self.`roaming` = `roaming`
    }

    func collected() -> any DeviceSnapshot {
        return Self(slotIndex: self.`slotIndex`, carrierName: self.`carrierName`, countryCode: self.`countryCode`, mobileCountryCode: self.`mobileCountryCode`, mobileNetworkCode: self.`mobileNetworkCode`, radioTechnology: self.`radioTechnology`, roaming: self.`roaming`, collectedAt: Date())
    }
}

public struct StorageVolumeSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 볼륨 이름
    public let `name`: String?
    /// 파일 시스템
    public let `fileSystem`: String?
    /// 볼륨 전체 용량
    public let `totalBytes`: UInt64?
    /// 볼륨의 빈 공간
    public let `freeBytes`: UInt64?
    /// 현재 호출자가 사용할 수 있는 여유 공간
    public let `availableToCallerBytes`: UInt64?
    /// 할당량 등 호출자 제한을 반영한 전체 용량
    public let `totalBytesForCaller`: UInt64?
    /// 읽기 전용 여부
    public let `readOnly`: Bool?
    /// 이동식 여부
    public let `removable`: Bool?
    /// 암호화 여부
    public let `encrypted`: Bool?
    /// 이름의 대소문자 구분 여부
    public let `caseSensitive`: Bool?
    /// 플랫폼이 중요한 용도에 제공하는 가용량
    public let `availableForImportantUsageBytes`: UInt64?
    /// 플랫폼이 기회적 용도에 제공하는 가용량
    public let `availableForOpportunisticUsageBytes`: UInt64?
    /// 플랫폼이 할당 가능하다고 보고하는 용량
    public let `allocatableBytes`: UInt64?

    public init(`name`: String? = nil, `fileSystem`: String? = nil, `totalBytes`: UInt64? = nil, `freeBytes`: UInt64? = nil, `availableToCallerBytes`: UInt64? = nil, `totalBytesForCaller`: UInt64? = nil, `readOnly`: Bool? = nil, `removable`: Bool? = nil, `encrypted`: Bool? = nil, `caseSensitive`: Bool? = nil, `availableForImportantUsageBytes`: UInt64? = nil, `availableForOpportunisticUsageBytes`: UInt64? = nil, `allocatableBytes`: UInt64? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`name` = `name`
        self.`fileSystem` = `fileSystem`
        self.`totalBytes` = `totalBytes`
        self.`freeBytes` = `freeBytes`
        self.`availableToCallerBytes` = `availableToCallerBytes`
        self.`totalBytesForCaller` = `totalBytesForCaller`
        self.`readOnly` = `readOnly`
        self.`removable` = `removable`
        self.`encrypted` = `encrypted`
        self.`caseSensitive` = `caseSensitive`
        self.`availableForImportantUsageBytes` = `availableForImportantUsageBytes`
        self.`availableForOpportunisticUsageBytes` = `availableForOpportunisticUsageBytes`
        self.`allocatableBytes` = `allocatableBytes`
    }

    func collected() -> any DeviceSnapshot {
        return Self(name: self.`name`, fileSystem: self.`fileSystem`, totalBytes: self.`totalBytes`, freeBytes: self.`freeBytes`, availableToCallerBytes: self.`availableToCallerBytes`, totalBytesForCaller: self.`totalBytesForCaller`, readOnly: self.`readOnly`, removable: self.`removable`, encrypted: self.`encrypted`, caseSensitive: self.`caseSensitive`, availableForImportantUsageBytes: self.`availableForImportantUsageBytes`, availableForOpportunisticUsageBytes: self.`availableForOpportunisticUsageBytes`, allocatableBytes: self.`allocatableBytes`, collectedAt: Date())
    }
}

public struct OriginStorageSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// origin 저장 한도
    public let `quotaBytes`: UInt64?
    /// origin 사용량
    public let `usageBytes`: UInt64?
    /// 플랫폼이 공개하는 저장 유형별 사용량
    public let `usageByCategory`: [StorageCategory: UInt64]?
    /// 영구 저장 권한·상태
    public let `persistent`: Bool?

    public init(`quotaBytes`: UInt64? = nil, `usageBytes`: UInt64? = nil, `usageByCategory`: [StorageCategory: UInt64]? = nil, `persistent`: Bool? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`quotaBytes` = `quotaBytes`
        self.`usageBytes` = `usageBytes`
        self.`usageByCategory` = `usageByCategory`
        self.`persistent` = `persistent`
    }

    func collected() -> any DeviceSnapshot {
        return Self(quotaBytes: self.`quotaBytes`, usageBytes: self.`usageBytes`, usageByCategory: self.`usageByCategory`, persistent: self.`persistent`, collectedAt: Date())
    }
}

public struct AccelerometerSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 중력을 포함한 가속도
    public let `value`: Vector3?

    public init(`value`: Vector3? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField0 = SnapshotRules.vector(self.`value`)
        return Self(value: normalizedField0, collectedAt: Date())
    }
}

public struct LinearAccelerationSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 중력을 제외한 가속도
    public let `value`: Vector3?

    public init(`value`: Vector3? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField0 = SnapshotRules.vector(self.`value`)
        return Self(value: normalizedField0, collectedAt: Date())
    }
}

public struct GravitySnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 중력 벡터
    public let `value`: Vector3?

    public init(`value`: Vector3? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField0 = SnapshotRules.vector(self.`value`)
        return Self(value: normalizedField0, collectedAt: Date())
    }
}

public struct GyroscopeSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 각속도
    public let `value`: Vector3?

    public init(`value`: Vector3? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField0 = SnapshotRules.vector(self.`value`)
        return Self(value: normalizedField0, collectedAt: Date())
    }
}

public struct MagnetometerSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 자기장
    public let `value`: Vector3?

    public init(`value`: Vector3? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField0 = SnapshotRules.vector(self.`value`)
        return Self(value: normalizedField0, collectedAt: Date())
    }
}

public struct RelativeOrientationSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 수집 세션의 상대 기준에 대한 자세
    public let `value`: Quaternion?

    public init(`value`: Quaternion? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField0 = SnapshotRules.rotation(self.`value`)
        return Self(value: normalizedField0, collectedAt: Date())
    }
}

public struct AbsoluteOrientationSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 동쪽·자기북·위쪽 기준에 대한 자세
    public let `value`: Quaternion?

    public init(`value`: Quaternion? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField0 = SnapshotRules.rotation(self.`value`)
        return Self(value: normalizedField0, collectedAt: Date())
    }
}

public struct IlluminanceSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 조도
    public let `value`: Double?

    public init(`value`: Double? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField0 = SnapshotRules.finite(self.`value`)
        return Self(value: normalizedField0, collectedAt: Date())
    }
}

public struct PressureSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 기압
    public let `value`: Double?

    public init(`value`: Double? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField0 = SnapshotRules.finite(self.`value`)
        return Self(value: normalizedField0, collectedAt: Date())
    }
}

public struct AmbientTemperatureSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 주변 온도
    public let `value`: Double?

    public init(`value`: Double? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField0 = SnapshotRules.finite(self.`value`)
        return Self(value: normalizedField0, collectedAt: Date())
    }
}

public struct RelativeHumiditySnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 상대 습도
    public let `value`: Double?

    public init(`value`: Double? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField0 = SnapshotRules.ratio(self.`value`)
        return Self(value: normalizedField0, collectedAt: Date())
    }
}

public struct ProximityNearSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 근접 상태
    public let `value`: Bool?

    public init(`value`: Bool? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        return Self(value: self.`value`, collectedAt: Date())
    }
}

public struct ProximityDistanceSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 근접 대상까지의 거리
    public let `value`: Double?

    public init(`value`: Double? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField0 = SnapshotRules.finite(self.`value`)
        return Self(value: normalizedField0, collectedAt: Date())
    }
}

public struct RelativeAltitudeSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 수집 세션의 기준점 대비 상대 고도
    public let `value`: Double?

    public init(`value`: Double? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField0 = SnapshotRules.finite(self.`value`)
        return Self(value: normalizedField0, collectedAt: Date())
    }
}

public struct HingeAngleSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 힌지 각도
    public let `value`: Double?

    public init(`value`: Double? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField0 = SnapshotRules.finite(self.`value`)
        return Self(value: normalizedField0, collectedAt: Date())
    }
}

public struct StepCountSinceBootSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 부팅 기준 누적 걸음 수
    public let `value`: Int64?

    public init(`value`: Int64? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        return Self(value: self.`value`, collectedAt: Date())
    }
}

public struct StepDetectedSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 걸음 발생. false 초기 이벤트는 없음
    public let `value`: Bool?

    public init(`value`: Bool? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        return Self(value: self.`value`, collectedAt: Date())
    }
}

public struct SignificantMotionSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 큰 움직임 발생. false 초기 이벤트는 없음
    public let `value`: Bool?

    public init(`value`: Bool? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        return Self(value: self.`value`, collectedAt: Date())
    }
}

public struct HumanPresenceSnapshot: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 사람 존재 여부
    public let `value`: Bool?

    public init(`value`: Bool? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`value` = `value`
    }

    func collected() -> any DeviceSnapshot {
        return Self(value: self.`value`, collectedAt: Date())
    }
}

public struct SensorDescription: DeviceSnapshot, Equatable, CollectibleSnapshot {
    public let collectedAt: Date
    /// 센서 종류
    public let `kind`: SensorKind?
    /// 센서 이름
    public let `name`: String?
    /// 제조사
    public let `vendor`: String?
    /// 플랫폼이 보고하는 센서 버전
    public let `version`: String?
    /// 원본 센서의 보고 모드
    public let `reportingMode`: SensorReportingMode?
    /// 지원되는 최소 수집 간격
    public let `minimumInterval`: Duration?
    /// 지원되는 최대 수집 간격
    public let `maximumInterval`: Duration?
    /// 해당 센서 측정 단위의 최대 범위
    public let `maximumRange`: Double?
    /// 해당 센서 측정 단위의 분해능
    public let `resolution`: Double?
    /// 플랫폼이 보고하는 전류 소비 mA
    public let `powerMilliamps`: Double?
    /// 플랫폼이 공개하는 FIFO 샘플 수용량
    public let `fifoCapacity`: Int?

    public init(`kind`: SensorKind? = nil, `name`: String? = nil, `vendor`: String? = nil, `version`: String? = nil, `reportingMode`: SensorReportingMode? = nil, `minimumInterval`: Duration? = nil, `maximumInterval`: Duration? = nil, `maximumRange`: Double? = nil, `resolution`: Double? = nil, `powerMilliamps`: Double? = nil, `fifoCapacity`: Int? = nil, collectedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.collectedAt = collectedAt
        self.`kind` = `kind`
        self.`name` = `name`
        self.`vendor` = `vendor`
        self.`version` = `version`
        self.`reportingMode` = `reportingMode`
        self.`minimumInterval` = `minimumInterval`
        self.`maximumInterval` = `maximumInterval`
        self.`maximumRange` = `maximumRange`
        self.`resolution` = `resolution`
        self.`powerMilliamps` = `powerMilliamps`
        self.`fifoCapacity` = `fifoCapacity`
    }

    func collected() -> any DeviceSnapshot {
        let normalizedField5 = SnapshotRules.duration(self.`minimumInterval`)
        let normalizedField6 = SnapshotRules.duration(self.`maximumInterval`)
        let normalizedField7 = SnapshotRules.finite(self.`maximumRange`)
        let normalizedField8 = SnapshotRules.finite(self.`resolution`)
        let normalizedField9 = SnapshotRules.finite(self.`powerMilliamps`)
        return Self(kind: self.`kind`, name: self.`name`, vendor: self.`vendor`, version: self.`version`, reportingMode: self.`reportingMode`, minimumInterval: normalizedField5, maximumInterval: normalizedField6, maximumRange: normalizedField7, resolution: normalizedField8, powerMilliamps: normalizedField9, fifoCapacity: self.`fifoCapacity`, collectedAt: Date())
    }
}

public enum Entities {
    public static let deviceInfo = Entity<DeviceInfoSnapshot>(kind: .deviceInfo, requiresTarget: false, mode: .state)
    public static let os = Entity<OsSnapshot>(kind: .os, requiresTarget: false, mode: .state)
    public static let runtime = Entity<RuntimeSnapshot>(kind: .runtime, requiresTarget: false, mode: .state)
    public static let cpu = Entity<CpuSnapshot>(kind: .cpu, requiresTarget: false, mode: .state)
    public static let cpuCore = Entity<CpuCoreSnapshot>(kind: .cpuCore, requiresTarget: true, mode: .state)
    public static let ram = Entity<RamSnapshot>(kind: .ram, requiresTarget: false, mode: .state)
    public static let processMemory = Entity<ProcessMemorySnapshot>(kind: .processMemory, requiresTarget: false, mode: .state)
    public static let locale = Entity<LocaleSnapshot>(kind: .locale, requiresTarget: false, mode: .state)
    public static let timeZone = Entity<TimeZoneSnapshot>(kind: .timeZone, requiresTarget: false, mode: .state)
    public static let androidBuild = Entity<AndroidBuildSnapshot>(kind: .androidBuild, requiresTarget: false, mode: .state)
    public static let androidIdentity = Entity<AndroidIdentitySnapshot>(kind: .androidIdentity, requiresTarget: false, mode: .state)
    public static let appleVendorIdentity = Entity<AppleVendorIdentitySnapshot>(kind: .appleVendorIdentity, requiresTarget: false, mode: .state)
    public static let windowsPublisherIdentity = Entity<WindowsPublisherIdentitySnapshot>(kind: .windowsPublisherIdentity, requiresTarget: false, mode: .state)
    public static let macPlatformIdentity = Entity<MacPlatformIdentitySnapshot>(kind: .macPlatformIdentity, requiresTarget: false, mode: .state)
    public static let hardwareSerial = Entity<HardwareSerialSnapshot>(kind: .hardwareSerial, requiresTarget: false, mode: .state)
    public static let telephonyIdentity = Entity<TelephonyIdentitySnapshot>(kind: .telephonyIdentity, requiresTarget: true, mode: .state)
    public static let display = Entity<DisplaySnapshot>(kind: .display, requiresTarget: true, mode: .state)
    public static let viewport = Entity<ViewportSnapshot>(kind: .viewport, requiresTarget: true, mode: .state)
    public static let power = Entity<PowerSnapshot>(kind: .power, requiresTarget: false, mode: .state)
    public static let battery = Entity<BatterySnapshot>(kind: .battery, requiresTarget: true, mode: .state)
    public static let networkPath = Entity<NetworkPathSnapshot>(kind: .networkPath, requiresTarget: false, mode: .state)
    public static let networkPerformance = Entity<NetworkPerformanceSnapshot>(kind: .networkPerformance, requiresTarget: false, mode: .state)
    public static let networkInterface = Entity<NetworkInterfaceSnapshot>(kind: .networkInterface, requiresTarget: true, mode: .state)
    public static let wifiConnection = Entity<WifiConnectionSnapshot>(kind: .wifiConnection, requiresTarget: true, mode: .state)
    public static let cellularSubscription = Entity<CellularSubscriptionSnapshot>(kind: .cellularSubscription, requiresTarget: true, mode: .state)
    public static let storageVolume = Entity<StorageVolumeSnapshot>(kind: .storageVolume, requiresTarget: true, mode: .state)
    public static let originStorage = Entity<OriginStorageSnapshot>(kind: .originStorage, requiresTarget: false, mode: .state)
    public static let accelerometer = Entity<AccelerometerSnapshot>(kind: .accelerometer, requiresTarget: true, mode: .sample)
    public static let linearAcceleration = Entity<LinearAccelerationSnapshot>(kind: .linearAcceleration, requiresTarget: true, mode: .sample)
    public static let gravity = Entity<GravitySnapshot>(kind: .gravity, requiresTarget: true, mode: .sample)
    public static let gyroscope = Entity<GyroscopeSnapshot>(kind: .gyroscope, requiresTarget: true, mode: .sample)
    public static let magnetometer = Entity<MagnetometerSnapshot>(kind: .magnetometer, requiresTarget: true, mode: .sample)
    public static let relativeOrientation = Entity<RelativeOrientationSnapshot>(kind: .relativeOrientation, requiresTarget: true, mode: .sample)
    public static let absoluteOrientation = Entity<AbsoluteOrientationSnapshot>(kind: .absoluteOrientation, requiresTarget: true, mode: .sample)
    public static let illuminance = Entity<IlluminanceSnapshot>(kind: .illuminance, requiresTarget: true, mode: .sample)
    public static let pressure = Entity<PressureSnapshot>(kind: .pressure, requiresTarget: true, mode: .sample)
    public static let ambientTemperature = Entity<AmbientTemperatureSnapshot>(kind: .ambientTemperature, requiresTarget: true, mode: .sample)
    public static let relativeHumidity = Entity<RelativeHumiditySnapshot>(kind: .relativeHumidity, requiresTarget: true, mode: .sample)
    public static let proximityNear = Entity<ProximityNearSnapshot>(kind: .proximityNear, requiresTarget: true, mode: .sample)
    public static let proximityDistance = Entity<ProximityDistanceSnapshot>(kind: .proximityDistance, requiresTarget: true, mode: .sample)
    public static let relativeAltitude = Entity<RelativeAltitudeSnapshot>(kind: .relativeAltitude, requiresTarget: true, mode: .sample)
    public static let hingeAngle = Entity<HingeAngleSnapshot>(kind: .hingeAngle, requiresTarget: true, mode: .sample)
    public static let stepCountSinceBoot = Entity<StepCountSinceBootSnapshot>(kind: .stepCountSinceBoot, requiresTarget: true, mode: .sample)
    public static let stepDetected = Entity<StepDetectedSnapshot>(kind: .stepDetected, requiresTarget: true, mode: .event)
    public static let significantMotion = Entity<SignificantMotionSnapshot>(kind: .significantMotion, requiresTarget: true, mode: .event)
    public static let humanPresence = Entity<HumanPresenceSnapshot>(kind: .humanPresence, requiresTarget: true, mode: .sample)
}
