using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace DeviceReadout.Windows;

[UnmanagedFunctionPointer(CallingConvention.Winapi)]
internal delegate uint DeviceInterfaceCallback(nint registration, nint context, uint action, nint data, uint size);

// Configuration Manager boundary. Filters and callback payloads retain their native binary layouts.
internal interface IConfigurationNotifications
{
    uint Register(byte[] filter, nint context, DeviceInterfaceCallback callback, out nint registration);
    uint Unregister(nint registration);
}

[SupportedOSPlatform("windows")]
internal sealed class WindowsDeviceInterfaces(IConfigurationNotifications? platform = null)
{
    private readonly IConfigurationNotifications platform = platform ?? new ConfigurationNotifications();

    internal IDisposable? Subscribe(Guid interfaceClass, Action<WindowsDeviceInterfaceChange> changed, Action<Exception> fail)
        => Registration.Create(platform, interfaceClass, changed, fail);

    private sealed class Registration(IConfigurationNotifications platform, Guid interfaceClass,
        Action<WindowsDeviceInterfaceChange> changed, Action<Exception> fail) : IDisposable
    {
        private static readonly ConcurrentDictionary<nint, Registration> Active = new();
        private static readonly DeviceInterfaceCallback Callback = Dispatch;
        private static long sequence;
        private readonly Guid interfaceClass = interfaceClass;
        private Action<WindowsDeviceInterfaceChange>? changed = changed;
        private Action<Exception>? fail = fail;
        private nint id, handle;
        private int closed;

        internal static Registration? Create(IConfigurationNotifications platform, Guid interfaceClass,
            Action<WindowsDeviceInterfaceChange> changed, Action<Exception> fail)
        {
            var registration = new Registration(platform, interfaceClass, changed, fail) {id = checked((nint)Interlocked.Increment(ref sequence))};
            Active.TryAdd(registration.id, registration);
            try {
                // CM_NOTIFY_FILTER: four DWORDs plus a 400-byte union (WCHAR InstanceId[200]).
                // Flags, DEVICEINTERFACE filter type and Reserved are zero; ClassGuid is at offset 16.
                var filter = new byte[416];BinaryPrimitives.WriteUInt32LittleEndian(filter, (uint)filter.Length);
                interfaceClass.TryWriteBytes(filter.AsSpan(16));
                var result = platform.Register(filter, registration.id, Callback, out registration.handle);
                if (result == 0) return registration;
                registration.Detach();
                if (result == 0x34) return null;
                throw Failure("CM_Register_Notification", result);
            } catch {registration.Detach();throw;}
        }
        private static uint Dispatch(nint handle, nint context, uint action, nint data, uint size)
        {
            if (action > 1 || !Active.TryGetValue(context, out var registration)) return 0;
            try {
                if (Volatile.Read(ref registration.closed) != 0) return 0;
                if (data == 0 || size is < 26 or > 65560 || (size & 1) != 0)
                    throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid device-interface notification size.");
                if (Marshal.ReadInt32(data) != 0 || Marshal.ReadInt32(data, 4) != 0)
                    throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid device-interface notification header.");
                if (Marshal.PtrToStructure<Guid>(data + 8) != registration.interfaceClass) return 0;
                var path = Marshal.PtrToStringUni(data + 24, ((int)size - 24) / 2)!;
                var terminator = path.IndexOf('\0');
                if (terminator <= 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid device-interface notification path.");
                Volatile.Read(ref registration.changed)?.Invoke(new(path[..terminator], action == 1));
            } catch (Exception error) {
                try {Volatile.Read(ref registration.fail)?.Invoke(error);} catch (Exception) { /* Never unwind into Configuration Manager. */ }
            }
            return 0;
        }
        private void Detach()
        {
            Interlocked.Exchange(ref closed, 1);Active.TryRemove(id, out _);
            Interlocked.Exchange(ref changed, null);Interlocked.Exchange(ref fail, null);
        }
        public void Dispose()
        {
            if (Interlocked.Exchange(ref closed, 1) != 0) return;
            Detach();
            var native = Interlocked.Exchange(ref handle, 0);
            if (native == 0) return;
            // Called on the collection worker, never on the CM callback which this API waits for.
            var result = platform.Unregister(native);
            if (result != 0) throw Failure("CM_Unregister_Notification", result);
        }
    }
    private static DeviceReadoutException Failure(string api, uint error)
        => new(error == 0x33 ? ErrorCode.PermissionDenied : ErrorCode.ReadFailed, $"{api} failed (CONFIGRET {error}).");

    private sealed class ConfigurationNotifications : IConfigurationNotifications
    {
        public uint Register(byte[] filter, nint context, DeviceInterfaceCallback callback, out nint registration)
            => CM_Register_Notification(filter, context, callback, out registration);
        public uint Unregister(nint registration) => CM_Unregister_Notification(registration);
        [DllImport("cfgmgr32.dll")]
        private static extern uint CM_Register_Notification([In] byte[] filter, nint context, DeviceInterfaceCallback callback, out nint registration);
        [DllImport("cfgmgr32.dll")]
        private static extern uint CM_Unregister_Notification(nint registration);
    }
}
