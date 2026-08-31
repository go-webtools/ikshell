//
//  ikshell-Bridging-Header.h
//  Swift/C API for the ARM64 iSH engine bridge.
//

#ifndef ikshell_Bridging_Header_h
#define ikshell_Bridging_Header_h

#include <stddef.h>

// Kernel lifecycle. The shell is started after boot on the same background
// thread that calls kernel_run(), so the emulator's TLS current task is valid.
int kernel_boot(const char *rootfs_path);
int kernel_start_shell(void);
void kernel_run(void);
void kernel_shutdown(void);

// Host pipe transport used by the Swift terminal.
int kernel_send_input(const void *data, size_t length);
int kernel_read_output(void *data, size_t capacity);
int kernel_set_winsize(int cols, int rows);

// Convert an Alpine tar.gz archive to the engine's fakefs format.
int kernel_import_rootfs(const char *archive_path, const char *rootfs_path);

// Filesystem helpers.
const char *kernel_fakefs_path(void);
int kernel_bind_mount(const char *linux_path, const char *host_path);
int kernel_bind_unmount(const char *linux_path);

#endif /* ikshell_Bridging_Header_h */
