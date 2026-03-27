#ifndef CLIBMTP_SHIM_H
#define CLIBMTP_SHIM_H

#include <libmtp.h>

// Helper to access device->storage since Swift can't access fields of
// incomplete struct pointers directly through the opaque wrapper.
static inline LIBMTP_devicestorage_t * _Nullable
clibmtp_device_get_storage(LIBMTP_mtpdevice_t * _Nonnull dev) {
    return dev->storage;
}

#endif
