#ifndef DEVICE_READOUT_VIEWPORT_TEST_HOST_H_
#define DEVICE_READOUT_VIEWPORT_TEST_HOST_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

void RegisterViewportTestHost(flutter::BinaryMessenger* messenger, HWND window);

#endif
