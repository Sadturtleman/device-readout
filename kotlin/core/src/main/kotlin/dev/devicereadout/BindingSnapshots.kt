// Generated from the shared DeviceReadout schema.
package dev.devicereadout

internal fun decodeBindingSnapshot(kind: EntityKind, values: Map<*, *>): DeviceSnapshot = when (kind) {
    EntityKind.DeviceInfo -> DeviceInfoSnapshot(
        manufacturer = BindingValues.string(values["manufacturer"]),
        brand = BindingValues.string(values["brand"]),
        modelCode = BindingValues.string(values["modelCode"]),
        modelName = BindingValues.string(values["modelName"]),
        deviceName = BindingValues.string(values["deviceName"]),
        formFactor = BindingValues.enum(values["formFactor"], FormFactor.entries),
        product = BindingValues.string(values["product"]),
        board = BindingValues.string(values["board"]),
    )
    EntityKind.Os -> OsSnapshot(
        family = BindingValues.enum(values["family"], OsFamily.entries),
        name = BindingValues.string(values["name"]),
        version = BindingValues.string(values["version"]),
        build = BindingValues.string(values["build"]),
        kernelName = BindingValues.string(values["kernelName"]),
        kernelVersion = BindingValues.string(values["kernelVersion"]),
    )
    EntityKind.Runtime -> RuntimeSnapshot(
        hostArchitecture = BindingValues.enum(values["hostArchitecture"], Architecture.entries),
        processArchitecture = BindingValues.enum(values["processArchitecture"], Architecture.entries),
        processBitness = BindingValues.integer(values["processBitness"]),
        supportedAbis = BindingValues.list(values["supportedAbis"]) { BindingValues.enum(it, Abi.entries) }?.toSet(),
    )
    EntityKind.Cpu -> CpuSnapshot(
        model = BindingValues.string(values["model"]),
        manufacturer = BindingValues.string(values["manufacturer"]),
        socModel = BindingValues.string(values["socModel"]),
        socManufacturer = BindingValues.string(values["socManufacturer"]),
        logicalProcessorCount = BindingValues.integer(values["logicalProcessorCount"]),
        availableLogicalProcessorCount = BindingValues.integer(values["availableLogicalProcessorCount"]),
        physicalCoreCount = BindingValues.integer(values["physicalCoreCount"]),
        processorPackageCount = BindingValues.integer(values["processorPackageCount"]),
    )
    EntityKind.CpuCore -> CpuCoreSnapshot(
        logicalIndex = BindingValues.integer(values["logicalIndex"]),
        coreIndex = BindingValues.integer(values["coreIndex"]),
        packageIndex = BindingValues.integer(values["packageIndex"]),
        online = BindingValues.boolean(values["online"]),
        currentClockHz = BindingValues.number(values["currentClockHz"]),
        maximumClockHz = BindingValues.number(values["maximumClockHz"]),
    )
    EntityKind.Ram -> RamSnapshot(
        physicalBytes = BindingValues.bytes(values["physicalBytes"]),
        kernelAccessibleBytes = BindingValues.bytes(values["kernelAccessibleBytes"]),
        advertisedBytes = BindingValues.bytes(values["advertisedBytes"]),
        availableBytes = BindingValues.bytes(values["availableBytes"]),
        freeBytes = BindingValues.bytes(values["freeBytes"]),
        lowMemory = BindingValues.boolean(values["lowMemory"]),
        lowMemoryThresholdBytes = BindingValues.bytes(values["lowMemoryThresholdBytes"]),
    )
    EntityKind.ProcessMemory -> ProcessMemorySnapshot(
        allocationRemainingBytes = BindingValues.bytes(values["allocationRemainingBytes"]),
    )
    EntityKind.Locale -> LocaleSnapshot(
        currentLanguageTag = BindingValues.string(values["currentLanguageTag"]),
        preferredLanguageTags = BindingValues.list(values["preferredLanguageTags"]) { BindingValues.string(it) },
        systemLanguageTags = BindingValues.list(values["systemLanguageTags"]) { BindingValues.string(it) },
        appLanguageTags = BindingValues.list(values["appLanguageTags"]) { BindingValues.string(it) },
        regionCode = BindingValues.string(values["regionCode"]),
        scriptCode = BindingValues.string(values["scriptCode"]),
        calendar = BindingValues.string(values["calendar"]),
        numberingSystem = BindingValues.string(values["numberingSystem"]),
        hourCycle = BindingValues.enum(values["hourCycle"], HourCycle.entries),
        firstWeekday = BindingValues.enum(values["firstWeekday"], Weekday.entries),
        measurementSystem = BindingValues.enum(values["measurementSystem"], MeasurementSystem.entries),
    )
    EntityKind.TimeZone -> TimeZoneSnapshot(
        ianaId = BindingValues.string(values["ianaId"]),
        windowsId = BindingValues.string(values["windowsId"]),
        utcOffsetSeconds = BindingValues.integer(values["utcOffsetSeconds"]),
        daylightSavingTime = BindingValues.boolean(values["daylightSavingTime"]),
    )
    EntityKind.AndroidBuild -> AndroidBuildSnapshot(
        apiLevel = BindingValues.integer(values["apiLevel"]),
        securityPatch = BindingValues.string(values["securityPatch"]),
        buildId = BindingValues.string(values["buildId"]),
        buildDisplay = BindingValues.string(values["buildDisplay"]),
        buildFingerprint = BindingValues.string(values["buildFingerprint"]),
        buildType = BindingValues.string(values["buildType"]),
        buildTags = BindingValues.list(values["buildTags"]) { BindingValues.string(it) },
        bootloaderVersion = BindingValues.string(values["bootloaderVersion"]),
    )
    EntityKind.AndroidIdentity -> AndroidIdentitySnapshot(
        androidId = BindingValues.string(values["androidId"]),
    )
    EntityKind.AppleVendorIdentity -> AppleVendorIdentitySnapshot(
        vendorId = BindingValues.string(values["vendorId"]),
    )
    EntityKind.WindowsPublisherIdentity -> WindowsPublisherIdentitySnapshot(
        publisherId = BindingValues.string(values["publisherId"]),
        source = BindingValues.enum(values["source"], WindowsIdentitySource.entries),
    )
    EntityKind.MacPlatformIdentity -> MacPlatformIdentitySnapshot(
        platformUuid = BindingValues.string(values["platformUuid"]),
    )
    EntityKind.HardwareSerial -> HardwareSerialSnapshot(
        serial = BindingValues.string(values["serial"]),
    )
    EntityKind.TelephonyIdentity -> TelephonyIdentitySnapshot(
        imei = BindingValues.string(values["imei"]),
        meid = BindingValues.string(values["meid"]),
    )
    EntityKind.Display -> DisplaySnapshot(
        label = BindingValues.string(values["label"]),
        primary = BindingValues.boolean(values["primary"]),
        internal = BindingValues.boolean(values["internal"]),
        state = BindingValues.enum(values["state"], DisplayState.entries),
        logicalBounds = BindingValues.rect(values["logicalBounds"]),
        workAreaBounds = BindingValues.rect(values["workAreaBounds"]),
        pixelSize = BindingValues.pixelSize(values["pixelSize"]),
        physicalSizeMillimeters = BindingValues.size(values["physicalSizeMillimeters"]),
        orientation = BindingValues.enum(values["orientation"], DisplayOrientation.entries),
        rotationDegrees = BindingValues.number(values["rotationDegrees"]),
        scaleFactor = BindingValues.number(values["scaleFactor"]),
        densityDpi = BindingValues.number(values["densityDpi"]),
        currentMode = BindingValues.displayMode(values["currentMode"]),
        supportedModes = BindingValues.list(values["supportedModes"]) { BindingValues.displayMode(it) },
        maximumRefreshRateHz = BindingValues.number(values["maximumRefreshRateHz"]),
        colorDepthBits = BindingValues.integer(values["colorDepthBits"]),
        colorGamut = BindingValues.enum(values["colorGamut"], ColorGamut.entries),
        hdrFormats = BindingValues.list(values["hdrFormats"]) { BindingValues.enum(it, HdrFormat.entries) }?.toSet(),
        brightness = BindingValues.number(values["brightness"]),
    )
    EntityKind.Viewport -> ViewportSnapshot(
        size = BindingValues.size(values["size"]),
        visualViewportSize = BindingValues.size(values["visualViewportSize"]),
        visualViewportScale = BindingValues.number(values["visualViewportScale"]),
        safeAreaInsets = BindingValues.insets(values["safeAreaInsets"]),
        textScaleFactor = BindingValues.number(values["textScaleFactor"]),
    )
    EntityKind.Power -> PowerSnapshot(
        powerSource = BindingValues.enum(values["powerSource"], PowerSource.entries),
        powerSaveMode = BindingValues.boolean(values["powerSaveMode"]),
        thermalState = BindingValues.thermal(values["thermalState"]),
    )
    EntityKind.Battery -> BatterySnapshot(
        present = BindingValues.boolean(values["present"]),
        level = BindingValues.number(values["level"]),
        charging = BindingValues.boolean(values["charging"]),
        state = BindingValues.enum(values["state"], BatteryState.entries),
        timeToFull = BindingValues.duration(values["timeToFull"]),
        timeToEmpty = BindingValues.duration(values["timeToEmpty"]),
        voltageMillivolts = BindingValues.number(values["voltageMillivolts"]),
        currentMicroamps = BindingValues.number(values["currentMicroamps"]),
        averageCurrentMicroamps = BindingValues.number(values["averageCurrentMicroamps"]),
        chargeRateMilliwatts = BindingValues.number(values["chargeRateMilliwatts"]),
        temperatureCelsius = BindingValues.number(values["temperatureCelsius"]),
        chargeCounterMicroampHours = BindingValues.counter(values["chargeCounterMicroampHours"]),
        remainingEnergyMilliwattHours = BindingValues.number(values["remainingEnergyMilliwattHours"]),
        fullChargeEnergyMilliwattHours = BindingValues.number(values["fullChargeEnergyMilliwattHours"]),
        designEnergyMilliwattHours = BindingValues.number(values["designEnergyMilliwattHours"]),
        technology = BindingValues.string(values["technology"]),
        health = BindingValues.enum(values["health"], BatteryHealth.entries),
        cycleCount = BindingValues.counter(values["cycleCount"]),
    )
    EntityKind.NetworkPath -> NetworkPathSnapshot(
        connectionState = BindingValues.enum(values["connectionState"], ConnectionState.entries),
        transports = BindingValues.list(values["transports"]) { BindingValues.enum(it, NetworkTransport.entries) }?.toSet(),
        metered = BindingValues.boolean(values["metered"]),
        expensive = BindingValues.boolean(values["expensive"]),
        constrained = BindingValues.boolean(values["constrained"]),
        saveData = BindingValues.boolean(values["saveData"]),
        supportsIpv4 = BindingValues.boolean(values["supportsIpv4"]),
        supportsIpv6 = BindingValues.boolean(values["supportsIpv6"]),
        supportsDns = BindingValues.boolean(values["supportsDns"]),
        internetValidated = BindingValues.boolean(values["internetValidated"]),
        captivePortal = BindingValues.boolean(values["captivePortal"]),
    )
    EntityKind.NetworkPerformance -> NetworkPerformanceSnapshot(
        downlinkBps = BindingValues.number(values["downlinkBps"]),
        uplinkBps = BindingValues.number(values["uplinkBps"]),
        roundTripTime = BindingValues.duration(values["roundTripTime"]),
        effectiveType = BindingValues.enum(values["effectiveType"], EffectiveConnectionType.entries),
        browserOnline = BindingValues.boolean(values["browserOnline"]),
    )
    EntityKind.NetworkInterface -> NetworkInterfaceSnapshot(
        name = BindingValues.string(values["name"]),
        interfaceType = BindingValues.enum(values["interfaceType"], NetworkInterfaceType.entries),
        operationalState = BindingValues.enum(values["operationalState"], NetworkOperationalState.entries),
        hardwareAddress = BindingValues.string(values["hardwareAddress"]),
        ipAddresses = BindingValues.list(values["ipAddresses"]) { BindingValues.address(it) },
        dnsServers = BindingValues.list(values["dnsServers"]) { BindingValues.string(it) },
        gateways = BindingValues.list(values["gateways"]) { BindingValues.string(it) },
        routes = BindingValues.list(values["routes"]) { BindingValues.route(it) },
        mtuBytes = BindingValues.bytes(values["mtuBytes"]),
    )
    EntityKind.WifiConnection -> WifiConnectionSnapshot(
        ssid = BindingValues.string(values["ssid"]),
        bssid = BindingValues.string(values["bssid"]),
        security = BindingValues.enum(values["security"], WifiSecurity.entries),
        rssiDbm = BindingValues.number(values["rssiDbm"]),
        frequencyHz = BindingValues.number(values["frequencyHz"]),
        receiveLinkSpeedBps = BindingValues.number(values["receiveLinkSpeedBps"]),
        transmitLinkSpeedBps = BindingValues.number(values["transmitLinkSpeedBps"]),
    )
    EntityKind.CellularSubscription -> CellularSubscriptionSnapshot(
        slotIndex = BindingValues.integer(values["slotIndex"]),
        carrierName = BindingValues.string(values["carrierName"]),
        countryCode = BindingValues.string(values["countryCode"]),
        mobileCountryCode = BindingValues.string(values["mobileCountryCode"]),
        mobileNetworkCode = BindingValues.string(values["mobileNetworkCode"]),
        radioTechnology = BindingValues.enum(values["radioTechnology"], RadioTechnology.entries),
        roaming = BindingValues.boolean(values["roaming"]),
    )
    EntityKind.StorageVolume -> StorageVolumeSnapshot(
        name = BindingValues.string(values["name"]),
        fileSystem = BindingValues.string(values["fileSystem"]),
        totalBytes = BindingValues.bytes(values["totalBytes"]),
        freeBytes = BindingValues.bytes(values["freeBytes"]),
        availableToCallerBytes = BindingValues.bytes(values["availableToCallerBytes"]),
        totalBytesForCaller = BindingValues.bytes(values["totalBytesForCaller"]),
        readOnly = BindingValues.boolean(values["readOnly"]),
        removable = BindingValues.boolean(values["removable"]),
        encrypted = BindingValues.boolean(values["encrypted"]),
        caseSensitive = BindingValues.boolean(values["caseSensitive"]),
        availableForImportantUsageBytes = BindingValues.bytes(values["availableForImportantUsageBytes"]),
        availableForOpportunisticUsageBytes = BindingValues.bytes(values["availableForOpportunisticUsageBytes"]),
        allocatableBytes = BindingValues.bytes(values["allocatableBytes"]),
    )
    EntityKind.OriginStorage -> OriginStorageSnapshot(
        quotaBytes = BindingValues.bytes(values["quotaBytes"]),
        usageBytes = BindingValues.bytes(values["usageBytes"]),
        usageByCategory = BindingValues.map(values["usageByCategory"], { BindingValues.enum(it, StorageCategory.entries) }, { BindingValues.bytes(it) }),
        persistent = BindingValues.boolean(values["persistent"]),
    )
    EntityKind.Accelerometer -> AccelerometerSnapshot(
        value = BindingValues.vector(values["value"]),
    )
    EntityKind.LinearAcceleration -> LinearAccelerationSnapshot(
        value = BindingValues.vector(values["value"]),
    )
    EntityKind.Gravity -> GravitySnapshot(
        value = BindingValues.vector(values["value"]),
    )
    EntityKind.Gyroscope -> GyroscopeSnapshot(
        value = BindingValues.vector(values["value"]),
    )
    EntityKind.Magnetometer -> MagnetometerSnapshot(
        value = BindingValues.vector(values["value"]),
    )
    EntityKind.RelativeOrientation -> RelativeOrientationSnapshot(
        value = BindingValues.rotation(values["value"]),
    )
    EntityKind.AbsoluteOrientation -> AbsoluteOrientationSnapshot(
        value = BindingValues.rotation(values["value"]),
    )
    EntityKind.Illuminance -> IlluminanceSnapshot(
        value = BindingValues.number(values["value"]),
    )
    EntityKind.Pressure -> PressureSnapshot(
        value = BindingValues.number(values["value"]),
    )
    EntityKind.AmbientTemperature -> AmbientTemperatureSnapshot(
        value = BindingValues.number(values["value"]),
    )
    EntityKind.RelativeHumidity -> RelativeHumiditySnapshot(
        value = BindingValues.number(values["value"]),
    )
    EntityKind.ProximityNear -> ProximityNearSnapshot(
        value = BindingValues.boolean(values["value"]),
    )
    EntityKind.ProximityDistance -> ProximityDistanceSnapshot(
        value = BindingValues.number(values["value"]),
    )
    EntityKind.RelativeAltitude -> RelativeAltitudeSnapshot(
        value = BindingValues.number(values["value"]),
    )
    EntityKind.HingeAngle -> HingeAngleSnapshot(
        value = BindingValues.number(values["value"]),
    )
    EntityKind.StepCountSinceBoot -> StepCountSinceBootSnapshot(
        value = BindingValues.counter(values["value"]),
    )
    EntityKind.StepDetected -> StepDetectedSnapshot(
        value = BindingValues.boolean(values["value"]),
    )
    EntityKind.SignificantMotion -> SignificantMotionSnapshot(
        value = BindingValues.boolean(values["value"]),
    )
    EntityKind.HumanPresence -> HumanPresenceSnapshot(
        value = BindingValues.boolean(values["value"]),
    )
}

internal fun decodeBindingSensorDescription(kind: EntityKind, values: Map<*, *>): SensorDescription = SensorDescription(
    kind = SensorKind.entries.firstOrNull {it.name == kind.name},
    name = BindingValues.string(values["name"]),
    vendor = BindingValues.string(values["vendor"]),
    version = BindingValues.string(values["version"]),
    reportingMode = BindingValues.enum(values["reportingMode"], SensorReportingMode.entries),
    minimumInterval = BindingValues.duration(values["minimumInterval"]),
    maximumInterval = BindingValues.duration(values["maximumInterval"]),
    maximumRange = BindingValues.number(values["maximumRange"]),
    resolution = BindingValues.number(values["resolution"]),
    powerMilliamps = BindingValues.number(values["powerMilliamps"]),
    fifoCapacity = BindingValues.integer(values["fifoCapacity"]),
)
