//
//  ikshell-Bridging-Header.h
//  桥接 iSH C 内核引擎到 Swift
//

#ifndef ikshell_Bridging_Header_h
#define ikshell_Bridging_Header_h

#include <stdint.h>
#include <stddef.h>

// MARK: - Kernel lifecycle

/// Initialize the Linux kernel emulation engine with the given rootfs path.
/// Returns 0 on success, negative on error.
int kernel_boot(const char *rootfs_path, char *const argv[]);

/// Shutdown the kernel engine.
void kernel_shutdown(void);

// MARK: - PTY (pseudo-terminal)

/// Open a new PTY and spawn /bin/sh inside the Linux kernel.
/// Returns TTY handle on success, -1 on error.
int kernel_openpty(void);

/// Read from PTY (stdout from Linux). Returns bytes read, 0 on EOF, -1 on error.
int kernel_pty_read(int fd, void *buf, size_t count);

/// Write to PTY (stdin to Linux). Returns bytes written, -1 on error.
int kernel_pty_write(int fd, const void *buf, size_t count);

// MARK: - Filesystem

/// Get the path to the fakefs root directory.
const char *kernel_fakefs_path(void);

/// Create a bind mount from Linux path to host filesystem path.
/// Allows Linux processes to access iOS Documents directory.
int kernel_bind_mount(const char *linux_path, const char *host_path);

/// Remove a bind mount.
int kernel_bind_unmount(const char *linux_path);

#endif /* ikshell_Bridging_Header_h */
