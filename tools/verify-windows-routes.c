/* Independent read-only ABI/count check using the Windows networking headers. */
#define _WIN32_WINNT 0x0600
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <netioapi.h>
#include <stddef.h>
#include <stdio.h>

int main(void) {
    PMIB_IPFORWARD_TABLE2 table = NULL;
    DWORD result = GetIpForwardTable2(AF_UNSPEC, &table);
    if (result != NO_ERROR) {fprintf(stderr, "GetIpForwardTable2 failed: %lu\n", result);return 1;}
    unsigned ipv4 = 0, ipv6 = 0;
    for (ULONG index = 0; index < table->NumEntries; index++) {
        if (table->Table[index].DestinationPrefix.Prefix.si_family == AF_INET) ipv4++;
        else if (table->Table[index].DestinationPrefix.Prefix.si_family == AF_INET6) ipv6++;
    }
    printf("{\"rowSize\":%zu,\"tableOffset\":%zu,\"destinationOffset\":%zu,\"prefixLengthOffset\":%zu,\"nextHopOffset\":%zu,\"count\":%lu,\"ipv4\":%u,\"ipv6\":%u}\n",
        sizeof(MIB_IPFORWARD_ROW2), offsetof(MIB_IPFORWARD_TABLE2, Table), offsetof(MIB_IPFORWARD_ROW2, DestinationPrefix),
        offsetof(MIB_IPFORWARD_ROW2, DestinationPrefix) + offsetof(IP_ADDRESS_PREFIX, PrefixLength),
        offsetof(MIB_IPFORWARD_ROW2, NextHop), table->NumEntries, ipv4, ipv6);
    FreeMibTable(table);return 0;
}
