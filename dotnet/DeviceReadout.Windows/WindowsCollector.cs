using System.Globalization;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;
using BclArchitecture = System.Runtime.InteropServices.Architecture;

namespace DeviceReadout.Windows;

[SupportedOSPlatform("windows")]
public static class WindowsDeviceAccess
{
    /// <summary>Creates an inert SDK context. Native collection starts only with reads or subscriptions.</summary>
    public static DeviceAccess Create() => new(new WindowsCollector());
}

[SupportedOSPlatform("windows")]
internal sealed class WindowsCollector : IDeviceCollector
{
    private const string AggregateBatteryTarget = "system-aggregate-battery";
    private readonly ResourceCatalog volumes = new();
    private readonly WindowsBatteries batteries;
    private readonly IWindowsPowerPlatform power;
    private readonly IWindowsAggregateBatteryPlatform aggregate;
    private readonly WindowsCpus cpus;
    private readonly WindowsCpuAvailability cpuAvailability;
    private readonly WindowsNetworkInterfaces networks;
    private readonly WindowsPublisherIdentity publisherIdentity;
    private readonly WindowsConnectivity connectivity;
    private readonly WindowsSensors sensors;
    internal WindowsCollector(IWindowsBatteryPlatform? batteryPlatform = null, IWindowsPowerPlatform? powerPlatform = null, IWindowsAggregateBatteryPlatform? aggregatePlatform = null, IWindowsCpuPlatform? cpuPlatform = null, IWindowsCpuAvailabilityPlatform? cpuAvailabilityPlatform = null, IWindowsNetworkPlatform? networkPlatform = null, IWindowsRoutePlatform? routePlatform = null, IWindowsIdentityRuntime? identityRuntime = null, IWindowsConnectivityRuntime? connectivityRuntime = null, IWindowsWlanApi? wlanApi = null, IWindowsSensorPlatform? sensorPlatform = null)
    {batteries = new(batteryPlatform ?? new WindowsBatteryPlatform());power = powerPlatform ?? new WindowsPowerPlatform();aggregate = aggregatePlatform ?? new WindowsAggregateBatteryPlatform();cpus = new(cpuPlatform ?? new WindowsCpuPlatform());cpuAvailability = new(cpuAvailabilityPlatform ?? new WindowsCpuAvailabilityPlatform());networks = new(networkPlatform ?? new WindowsNetworkPlatform(), routePlatform ?? new WindowsRoutePlatform());publisherIdentity = new(identityRuntime);connectivity = new(connectivityRuntime, wlanApi);sensors = new(sensorPlatform ?? new WindowsSensorPlatform());}
    public void Dispose() {try {batteries.Dispose();} finally {try {aggregate.Dispose();} finally {try {networks.Dispose();} finally {try {publisherIdentity.Dispose();} finally {try {connectivity.Dispose();} finally {sensors.Dispose();}}}}}}
    public DeviceSnapshot Read(EntityAddress entity, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return entity.Kind switch {
            EntityKind.Ram => Memory(),
            EntityKind.ProcessMemory => new ProcessMemorySnapshot {AllocationRemainingBytes = MemoryStatus().AvailablePageFile},
            EntityKind.Runtime => new RuntimeSnapshot {HostArchitecture = Architecture(RuntimeInformation.OSArchitecture),
                ProcessArchitecture = Architecture(RuntimeInformation.ProcessArchitecture), ProcessBitness = Environment.Is64BitProcess ? 64 : 32},
            EntityKind.Os => new OsSnapshot {Family = OsFamily.Windows, Name = "Windows", Version = Environment.OSVersion.Version.ToString(),
                Build = Environment.OSVersion.Version.Build.ToString(CultureInfo.InvariantCulture), KernelName = "Windows NT", KernelVersion = Environment.OSVersion.Version.ToString()},
            EntityKind.DeviceInfo => new DeviceInfoSnapshot {Manufacturer = RegistryString(@"HARDWARE\DESCRIPTION\System\BIOS", "SystemManufacturer"),
                ModelName = RegistryString(@"HARDWARE\DESCRIPTION\System\BIOS", "SystemProductName"), DeviceName = Environment.MachineName},
            EntityKind.Cpu => Cpu(cancellationToken),
            EntityKind.CpuCore => cpus.Read(entity.TargetId, cancellationToken),
            EntityKind.Locale => Locale(),
            EntityKind.TimeZone => TimeZone(),
            EntityKind.Power => Power(),
            EntityKind.Battery => entity.TargetId == AggregateBatteryTarget ? AggregateBattery() : batteries.Read(entity.TargetId, cancellationToken),
            EntityKind.StorageVolume => Volume(entity.TargetId),
            EntityKind.NetworkInterface => networks.Read(entity.TargetId, cancellationToken),
            EntityKind.WindowsPublisherIdentity => publisherIdentity.Read(cancellationToken),
            EntityKind.NetworkPath => connectivity.Read(cancellationToken),
            EntityKind.NetworkPerformance => connectivity.ReadPerformance(cancellationToken),
            EntityKind.WifiConnection => connectivity.ReadWifi(entity.TargetId, cancellationToken),
            EntityKind.CellularSubscription => connectivity.ReadCellular(entity.TargetId, cancellationToken),
            _ => throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "This Windows collector is not available for the entity.")
        };
    }

    public EntityCapabilities Capabilities(EntityAddress entity)
        => Capabilities(entity, CancellationToken.None);
    public EntityCapabilities Capabilities(EntityAddress entity, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (WindowsSensors.Supports(entity.Kind)) return sensors.Capabilities(entity, token);
        if (entity.Kind == EntityKind.Battery) return entity.TargetId == AggregateBatteryTarget ? new(true, true) : batteries.Capabilities(entity.TargetId);
        if (entity.Kind == EntityKind.CpuCore) return cpus.Capabilities(entity.TargetId);
        if (entity.Kind == EntityKind.NetworkInterface) return networks.Capabilities(entity.TargetId);
        if (entity.Kind == EntityKind.WindowsPublisherIdentity) return publisherIdentity.Capabilities;
        if (entity.Kind is EntityKind.NetworkPath or EntityKind.NetworkPerformance) return connectivity.Capabilities;
        if (entity.Kind == EntityKind.WifiConnection) return connectivity.WifiCapabilities(entity.TargetId);
        if (entity.Kind == EntityKind.CellularSubscription) return connectivity.CellularCapabilities(entity.TargetId);
        var readable = entity.Kind is EntityKind.Ram or EntityKind.ProcessMemory or EntityKind.Runtime or EntityKind.Os
            or EntityKind.DeviceInfo or EntityKind.Cpu or EntityKind.Locale or EntityKind.TimeZone or EntityKind.Power
            or EntityKind.StorageVolume or EntityKind.NetworkInterface or EntityKind.Battery;
        return new(readable, readable);
    }

    public ICollectorSubscription? ObserveChanges(EntityAddress entity, Action<Func<CancellationToken, DeviceSnapshot>> changed,
        Action<Exception> fail, CancellationToken cancellationToken)
    {
        if (entity.Kind == EntityKind.NetworkInterface) return networks.Observe(entity.TargetId, changed, fail, cancellationToken);
        if (entity.Kind == EntityKind.NetworkPath) return connectivity.Observe(connectivity.Read, changed, fail, cancellationToken);
        if (entity.Kind == EntityKind.NetworkPerformance) return connectivity.Observe(connectivity.ReadPerformance, changed, fail, cancellationToken);
        if (entity.Kind == EntityKind.WifiConnection) return connectivity.Observe(token => connectivity.ReadWifi(entity.TargetId, token), changed, fail, cancellationToken);
        if (entity.Kind == EntityKind.CellularSubscription) return connectivity.ObserveCellular(entity.TargetId, changed, fail, cancellationToken);
        if (entity.Kind is not (EntityKind.Power or EntityKind.Battery)) return null;
        var observation = new PowerObservation();
        try {
            if (entity.Kind == EntityKind.Battery) {
                if (entity.TargetId == AggregateBatteryTarget) {
                    var reports = aggregate.Observe(() => changed(token => {token.ThrowIfCancellationRequested();return AggregateBattery();}), fail);
                    if (reports is not null) observation.Subscriptions.Add(reports);
                } else {
                    observation.Subscriptions.Add(batteries.ObserveRemoval(entity.TargetId, fail));
                    observation.Subscriptions.Add(batteries.ObserveStatus(entity.TargetId, changed, fail, cancellationToken));
                }
            }
            var settings = entity.Kind == EntityKind.Power
                ? new[] {WindowsPowerSettings.Source, WindowsPowerSettings.Saving}
                : new[] {WindowsPowerSettings.Source, WindowsPowerSettings.BatteryPercentage};
            foreach(var setting in settings) {
                cancellationToken.ThrowIfCancellationRequested();
                var subscription = power.Subscribe(setting, value => {
                    if (cancellationToken.IsCancellationRequested) return;
                    changed(token => {
                        token.ThrowIfCancellationRequested();
                        if (entity.Kind == EntityKind.Battery) return entity.TargetId == AggregateBatteryTarget ? AggregateBattery() : batteries.Read(entity.TargetId, token);
                        var state = Power();
                        return setting == WindowsPowerSettings.Source
                            ? state with {PowerSource = value switch {0 => DeviceReadout.PowerSource.External, 1 => DeviceReadout.PowerSource.Battery, 2 => DeviceReadout.PowerSource.Ups, _ => null}}
                            : state with {PowerSaveMode = value switch {0 => false, 1 => true, _ => null}};
                    });
                }, fail);
                if (subscription is not null) observation.Subscriptions.Add(subscription);
            }
            return observation;
        } catch {observation.Dispose();throw;}
    }

    private sealed class PowerObservation : ICollectorSubscription
    {
        internal readonly List<IDisposable> Subscriptions = [];
        public bool PollingRequired => true;
        public void Dispose()
        {
            Exception? failure = null;
            foreach(var subscription in Subscriptions) {
                try {subscription.Dispose();} catch (Exception error) {failure ??= error;}
            }
            Subscriptions.Clear();
            if (failure is not null) throw failure;
        }
    }

    public IReadOnlyList<string> List(EntityKind kind, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (WindowsSensors.Supports(kind)) return sensors.List(kind, cancellationToken);
        return kind switch {
            EntityKind.StorageVolume => RefreshVolumes(),
            EntityKind.Battery => BatteryTargets(cancellationToken),
            EntityKind.CpuCore => cpus.List(cancellationToken),
            EntityKind.NetworkInterface => networks.List(cancellationToken),
            EntityKind.WifiConnection => connectivity.ListWifi(cancellationToken),
            EntityKind.CellularSubscription => connectivity.ListCellular(cancellationToken),
            _ => throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Target discovery is unavailable for this Windows entity.")
        };
    }

    public string? Current(EntityKind kind, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (kind == EntityKind.Battery) return aggregate.Read() is null ? null : AggregateBatteryTarget;
        if (kind == EntityKind.WifiConnection) return connectivity.CurrentWifi(cancellationToken);
        if (kind == EntityKind.CellularSubscription) return connectivity.CurrentCellular(cancellationToken);
        if (kind == EntityKind.RelativeAltitude) return sensors.List(kind, cancellationToken).SingleOrDefault();
        if (kind != EntityKind.StorageVolume) return null;
        var volume = new char[32768];
        if (!Native.GetVolumePathName(AppContext.BaseDirectory, volume, (uint)volume.Length)) return null;
        var guid = new char[64];
        if (!Native.GetVolumeNameForVolumeMountPoint(new string(volume).TrimEnd('\0'), guid, (uint)guid.Length)) return null;
        RefreshVolumes();return volumes.Find(new string(guid).TrimEnd('\0'));
    }

    public SensorDescription Describe(EntityAddress entity, CancellationToken token)
        => WindowsSensors.Supports(entity.Kind) ? sensors.Describe(entity, token)
            : throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "This Windows sensor description is unavailable.");
    public ICollectorSubscription? Observe(EntityAddress entity, SensorSamplingRate rate, Action<DeviceSnapshot> emit, Action<Exception> fail, CancellationToken token)
        => WindowsSensors.Supports(entity.Kind) ? sensors.Observe(entity, rate, emit, fail, token) : null;

    private IReadOnlyList<string> BatteryTargets(CancellationToken token)
    {
        var individual = batteries.List(token);
        return aggregate.Read() is null ? individual : individual.Append(AggregateBatteryTarget).ToArray();
    }
    private BatterySnapshot AggregateBattery()
    {
        var report = aggregate.Read() ?? throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "The OS aggregate battery is unavailable.");
        if (report.Status == 0) return new BatterySnapshot {Present = false};
        var design = report.DesignCapacity is >= 0 ? report.DesignCapacity : null;
        var full = report.FullChargeCapacity is >= 0 ? report.FullChargeCapacity : null;
        var remaining = report.RemainingCapacity is >= 0 ? report.RemainingCapacity : null;
        return new BatterySnapshot {
            Present = report.Status is >= 1 and <= 3 ? true : null,
            Charging = report.Status switch {1 or 2 => false, 3 => true, _ => null},
            State = report.Status switch {1 => BatteryState.Discharging, 2 => BatteryState.Idle, 3 => BatteryState.Charging, _ => null},
            Level = full > 0 ? (double?)remaining / full : null,
            ChargeRateMilliwatts = report.ChargeRate,
            DesignEnergyMilliwattHours = design,
            FullChargeEnergyMilliwattHours = full,
            RemainingEnergyMilliwattHours = remaining,
            TimeToEmpty = AggregateRemainingTime()
        };
    }
    private TimeSpan? AggregateRemainingTime()
    {
        try {
            var state = power.Read();
            var absent = state.BatteryFlag != 255 && (state.BatteryFlag & 128) != 0;
            return state.AcLineStatus != 1 && !absent && state.BatteryLifeTime != uint.MaxValue
                ? TimeSpan.FromSeconds(state.BatteryLifeTime) : null;
        } catch (DeviceReadoutException) {return null;}
    }

    private IReadOnlyList<string> RefreshVolumes()
    {
        var paths = new List<string>();var buffer = new char[64];
        var find = Native.FindFirstVolume(buffer, (uint)buffer.Length);
        if (find == new IntPtr(-1)) {
            if (Marshal.GetLastPInvokeError() == 18) return volumes.Update([]);
            throw Failed(nameof(Native.FindFirstVolume));
        }
        try {
            do {paths.Add(new string(buffer).TrimEnd('\0'));} while (Native.FindNextVolume(find, buffer, (uint)buffer.Length));
            if (Marshal.GetLastPInvokeError() != 18) throw Failed(nameof(Native.FindNextVolume));
        } finally {Native.FindVolumeClose(find);}
        return volumes.Update(paths);
    }

    private static DeviceReadoutException Failed(string api) => new(ErrorCode.ReadFailed, $"{api} failed (Win32 {Marshal.GetLastPInvokeError()}).");
    private static Native.MemoryStatus MemoryStatus()
    {
        var status = new Native.MemoryStatus {Length = (uint)Marshal.SizeOf<Native.MemoryStatus>()};
        if (!Native.GlobalMemoryStatusEx(ref status)) throw Failed(nameof(Native.GlobalMemoryStatusEx));
        return status;
    }
    private static RamSnapshot Memory()
    {
        var status = MemoryStatus();
        ulong? installed = Native.GetPhysicallyInstalledSystemMemory(out var kibibytes) ? checked(kibibytes * 1024) : null;
        bool? low = null;
        using var handle = Native.CreateMemoryResourceNotification(0);
        if (!handle.IsInvalid && Native.QueryMemoryResourceNotification(handle, out var state)) low = state;
        return new RamSnapshot {PhysicalBytes = installed, KernelAccessibleBytes = status.TotalPhysical,
            AvailableBytes = status.AvailablePhysical, LowMemory = low};
    }

    private CpuSnapshot Cpu(CancellationToken token)
    {
        var count = Native.GetActiveProcessorCount(ushort.MaxValue);
        (int Logical, int Physical, int? Packages)? topology = null;
        try {topology = cpus.Counts(token);} catch (DeviceReadoutException) { /* Other CPU fields remain independently available. */ }
        return new CpuSnapshot {AvailableLogicalProcessorCount = cpuAvailability.Read(token),
            LogicalProcessorCount = topology?.Logical ?? (count is > 0 and <= int.MaxValue ? (int)count : null),
            PhysicalCoreCount = topology?.Physical, ProcessorPackageCount = topology?.Packages,
            Model = RegistryString(@"HARDWARE\DESCRIPTION\System\CentralProcessor\0", "ProcessorNameString"),
            Manufacturer = RegistryString(@"HARDWARE\DESCRIPTION\System\CentralProcessor\0", "VendorIdentifier")};
    }

    private static Architecture? Architecture(BclArchitecture value) => value switch {
        BclArchitecture.X86 => DeviceReadout.Architecture.X86, BclArchitecture.X64 => DeviceReadout.Architecture.X64,
        BclArchitecture.Arm => DeviceReadout.Architecture.Arm32, BclArchitecture.Arm64 => DeviceReadout.Architecture.Arm64,
        BclArchitecture.Wasm => DeviceReadout.Architecture.Wasm32, BclArchitecture.RiscV64 => DeviceReadout.Architecture.RiscV64,
        _ => null
    };

    private static string? RegistryString(string path, string name)
    {
        try {using var key = Registry.LocalMachine.OpenSubKey(path, writable:false);return key?.GetValue(name) as string;}
        catch (System.Security.SecurityException) {return null;}
        catch (UnauthorizedAccessException) {return null;}
        catch (IOException) {return null;}
    }

    private static LocaleSnapshot Locale()
    {
        var name = new char[85];
        var size = Native.GetUserDefaultLocaleName(name, name.Length);
        if (size == 0) throw Failed(nameof(Native.GetUserDefaultLocaleName));
        var culture = CultureInfo.GetCultureInfo(new string(name, 0, size - 1));
        RegionInfo? region = null;
        try {region = new RegionInfo(culture.Name);} catch (ArgumentException) { }
        return new LocaleSnapshot {CurrentLanguageTag = culture.Name, RegionCode = region?.TwoLetterISORegionName,
            FirstWeekday = culture.DateTimeFormat.FirstDayOfWeek switch {
                DayOfWeek.Monday => Weekday.Monday, DayOfWeek.Tuesday => Weekday.Tuesday, DayOfWeek.Wednesday => Weekday.Wednesday,
                DayOfWeek.Thursday => Weekday.Thursday, DayOfWeek.Friday => Weekday.Friday, DayOfWeek.Saturday => Weekday.Saturday, DayOfWeek.Sunday => Weekday.Sunday, _ => null
            }};
    }

    private static TimeZoneSnapshot TimeZone()
    {
        // Get fresh OS state through the registry-backed lookup; never clear the app's global timezone cache.
        var data = new Native.DynamicTimeZoneInformation();
        var result = Native.GetDynamicTimeZoneInformation(out data);
        if (result == uint.MaxValue) throw Failed(nameof(Native.GetDynamicTimeZoneInformation));
        var windowsId = data.TimeZoneKeyName;
        string? ianaId = null;
        if (!string.IsNullOrEmpty(windowsId)) TimeZoneInfo.TryConvertWindowsIdToIanaId(windowsId, out ianaId);
        var bias = data.Bias + (result == 2 ? data.DaylightBias : result == 1 ? data.StandardBias : 0);
        return new TimeZoneSnapshot {WindowsId = string.IsNullOrEmpty(windowsId) ? null : windowsId,
            IanaId = ianaId, UtcOffsetSeconds = -bias * 60, DaylightSavingTime = result == 2};
    }

    private PowerSnapshot Power()
    {
        var state = power.Read();
        return new PowerSnapshot {PowerSource = state.AcLineStatus switch {
                0 when state.BatteryCapabilities is {SystemBatteriesPresent: 1, UpsPresent: 0, BatteriesAreShortTerm: 0} => DeviceReadout.PowerSource.Battery,
                1 => DeviceReadout.PowerSource.External, _ => null},
            PowerSaveMode = state.SystemStatusFlag switch {0 => false, 1 => true, _ => null}};
    }

    private StorageVolumeSnapshot Volume(string? target)
    {
        RefreshVolumes();var id = volumes.Resolve(target);
        ulong? available = null, callerTotal = null, free = null, total = null;
        if (Native.GetDiskFreeSpaceEx(id, out var a, out var t, out var f)) (available, callerTotal, free) = (a, t, f);
        if (Native.GetDiskSpaceInformation(id, out var space) == 0)
            total = checked(space.ActualTotalAllocationUnits * space.SectorsPerAllocationUnit * space.BytesPerSector);
        var label = new char[261];var fs = new char[261];
        uint? flags = Native.GetVolumeInformation(id, label, (uint)label.Length, out _, out _, out var bits, fs, (uint)fs.Length) ? bits : null;
        if (flags is null && available is null) throw Failed("Volume query");
        return new StorageVolumeSnapshot {Name = flags is null ? null : new string(label).TrimEnd('\0'),
            FileSystem = flags is null ? null : new string(fs).TrimEnd('\0'),
            TotalBytes = total, FreeBytes = free, AvailableToCallerBytes = available, TotalBytesForCaller = callerTotal,
            ReadOnly = flags.HasValue ? (flags & 0x00080000) != 0 : null,
            Removable = Native.GetDriveType(id) switch {2 => true, 3 => false, _ => null}};
    }

}

[SupportedOSPlatform("windows")]
internal static class Native
{
    [StructLayout(LayoutKind.Sequential)] internal struct MemoryStatus {
        public uint Length, MemoryLoad;
        public ulong TotalPhysical, AvailablePhysical, TotalPageFile, AvailablePageFile, TotalVirtual, AvailableVirtual, AvailableExtendedVirtual;
    }
    [StructLayout(LayoutKind.Sequential)] internal struct SystemPowerStatus {
        public byte AcLineStatus, BatteryFlag, BatteryLifePercent, SystemStatusFlag;
        public uint BatteryLifeTime, BatteryFullLifeTime;
    }
    [StructLayout(LayoutKind.Sequential)] internal struct DiskSpaceInformation {
        public ulong ActualTotalAllocationUnits, ActualAvailableAllocationUnits, ActualPoolUnavailableAllocationUnits,
            CallerTotalAllocationUnits, CallerAvailableAllocationUnits, CallerPoolUnavailableAllocationUnits,
            UsedAllocationUnits, TotalReservedAllocationUnits, VolumeStorageReserveAllocationUnits, AvailableCommittedAllocationUnits, PoolAvailableAllocationUnits;
        public uint SectorsPerAllocationUnit, BytesPerSector;
    }
    [StructLayout(LayoutKind.Sequential)] internal struct SystemTime {public ushort Year, Month, DayOfWeek, Day, Hour, Minute, Second, Milliseconds;}
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] internal struct DynamicTimeZoneInformation {
        public int Bias;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string StandardName;
        public SystemTime StandardDate;public int StandardBias;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DaylightName;
        public SystemTime DaylightDate;public int DaylightBias;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string TimeZoneKeyName;
        [MarshalAs(UnmanagedType.U1)] public bool DynamicDaylightTimeDisabled;
    }
    [DllImport("kernel32.dll", SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool GlobalMemoryStatusEx(ref MemoryStatus value);
    [DllImport("kernel32.dll", SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool GetPhysicallyInstalledSystemMemory(out ulong kibibytes);
    [DllImport("kernel32.dll", SetLastError=true)] internal static extern SafeWaitHandle CreateMemoryResourceNotification(int type);
    [DllImport("kernel32.dll", SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool QueryMemoryResourceNotification(SafeWaitHandle handle, [MarshalAs(UnmanagedType.Bool)] out bool state);
    [DllImport("kernel32.dll", SetLastError=true)] internal static extern uint GetActiveProcessorCount(ushort group);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] internal static extern int GetUserDefaultLocaleName([Out] char[] name, int count);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] internal static extern uint GetDynamicTimeZoneInformation(out DynamicTimeZoneInformation data);
    [DllImport("kernel32.dll", SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool GetSystemPowerStatus(out SystemPowerStatus status);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool GetDiskFreeSpaceEx(string path, out ulong available, out ulong total, out ulong free);
    [DllImport("kernel32.dll", EntryPoint="GetDiskSpaceInformationW", SetLastError=true, CharSet=CharSet.Unicode)] internal static extern int GetDiskSpaceInformation(string path, out DiskSpaceInformation information);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool GetVolumePathName(string file, [Out] char[] volume, uint length);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool GetVolumeNameForVolumeMountPoint(string mount, [Out] char[] volume, uint length);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] internal static extern IntPtr FindFirstVolume([Out] char[] volume, uint length);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool FindNextVolume(IntPtr find, [Out] char[] volume, uint length);
    [DllImport("kernel32.dll", SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool FindVolumeClose(IntPtr find);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] internal static extern uint GetDriveType(string path);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool GetVolumeInformation(string path, [Out] char[] name, uint nameSize, out uint serial, out uint maxComponent, out uint flags, [Out] char[] fileSystem, uint fileSystemSize);
}
