//
//  ikshell_engine.c
//  Swift-facing bridge for the ARM64 iSH engine.
//

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#include "kernel/calls.h"
#include "kernel/fs.h"
#include "kernel/init.h"
#include "kernel/task.h"
#include "fs/fake.h"
#include "tools/fakefs.h"

static int kernel_initialized;
static int shell_started;
static int host_input_read = -1;
static int host_input_write = -1;
static int host_output_read = -1;
static int host_output_write = -1;
static pthread_mutex_t kernel_lock = PTHREAD_MUTEX_INITIALIZER;

static void close_io_pipes(void) {
    int *fds[] = {
        &host_input_read,
        &host_input_write,
        &host_output_read,
        &host_output_write,
    };
    for (size_t i = 0; i < sizeof(fds) / sizeof(fds[0]); i++) {
        if (*fds[i] >= 0) {
            close(*fds[i]);
            *fds[i] = -1;
        }
    }
}

static int set_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0)
        return -1;
    return 0;
}

static int setup_io_pipes(void) {
    int input_pipe[2] = {-1, -1};
    int output_pipe[2] = {-1, -1};

    if (pipe(input_pipe) < 0 || pipe(output_pipe) < 0)
        goto fail;
    if (set_nonblocking(input_pipe[1]) < 0 || set_nonblocking(output_pipe[0]) < 0)
        goto fail;

    host_input_read = input_pipe[0];
    host_input_write = input_pipe[1];
    host_output_read = output_pipe[0];
    host_output_write = output_pipe[1];
    return 0;

fail:
    if (input_pipe[0] >= 0) close(input_pipe[0]);
    if (input_pipe[1] >= 0) close(input_pipe[1]);
    if (output_pipe[0] >= 0) close(output_pipe[0]);
    if (output_pipe[1] >= 0) close(output_pipe[1]);
    return -1;
}

static char *pack_strings(const char *const strings[]) {
    size_t size = 0;
    for (size_t i = 0; strings[i] != NULL; i++)
        size += strlen(strings[i]) + 1;

    char *packed = malloc(size == 0 ? 1 : size);
    if (packed == NULL)
        return NULL;

    char *cursor = packed;
    for (size_t i = 0; strings[i] != NULL; i++) {
        size_t length = strlen(strings[i]) + 1;
        memcpy(cursor, strings[i], length);
        cursor += length;
    }
    return packed;
}

static int start_shell_locked(void) {
    if (become_new_init_child() != 0)
        return -1;
    if (create_stdio_from_fds(host_input_read, host_output_write, host_output_write) != 0)
        return -1;

    // The bridge uses pipes rather than a host PTY, so force interactive mode
    // or BusyBox ash will treat the shell as a non-interactive script runner.
    const char *argv[] = {"/bin/sh", "-il", NULL};
    const char *envp[] = {
        "PATH=/usr/local/bin:/usr/bin:/bin",
        "HOME=/root",
        "TERM=xterm-256color",
        NULL,
    };
    char *argv_buf = pack_strings(argv);
    char *envp_buf = pack_strings(envp);
    if (argv_buf == NULL || envp_buf == NULL) {
        free(argv_buf);
        free(envp_buf);
        return -1;
    }

    int result = do_execve("/bin/sh", 2, argv_buf, envp_buf);
    free(argv_buf);
    free(envp_buf);
    if (result < 0)
        return result;

    shell_started = 1;
    return 0;
}

// MARK: - Kernel lifecycle

int kernel_boot(const char *rootfs_path) {
    if (rootfs_path == NULL || rootfs_path[0] == '\0')
        return -1;

    pthread_mutex_lock(&kernel_lock);
    if (kernel_initialized) {
        pthread_mutex_unlock(&kernel_lock);
        return -1;
    }

    if (mount_root(&fakefs, rootfs_path) != 0)
        goto fail;

    lock(&mounts_lock);
    int result = do_mount(&devptsfs, "", "/dev/pts", "", 0);
    unlock(&mounts_lock);
    if (result < 0)
        goto fail;

    if (become_first_process() != 0)
        goto fail;
    if (setup_io_pipes() < 0)
        goto fail;
    if (create_stdio_from_fds(host_input_read, host_output_write, host_output_write) != 0)
        goto fail;

    kernel_initialized = 1;
    shell_started = 0;
    pthread_mutex_unlock(&kernel_lock);
    return 0;

fail:
    close_io_pipes();
    pthread_mutex_unlock(&kernel_lock);
    return -1;
}

int kernel_start_shell(void) {
    pthread_mutex_lock(&kernel_lock);
    if (!kernel_initialized || shell_started) {
        pthread_mutex_unlock(&kernel_lock);
        return -1;
    }
    int result = start_shell_locked();
    pthread_mutex_unlock(&kernel_lock);
    return result;
}

void kernel_run(void) {
    // task_run_current exits the host thread when the guest process exits.
    task_run_current();
}

void kernel_shutdown(void) {
    pthread_mutex_lock(&kernel_lock);
    if (!kernel_initialized) {
        pthread_mutex_unlock(&kernel_lock);
        return;
    }

    // Closing the host write end makes a guest read return EOF. Do not unmount
    // while the emulation thread may still be executing guest code.
    if (host_input_write >= 0) {
        close(host_input_write);
        host_input_write = -1;
    }
    kernel_initialized = 0;
    close_io_pipes();
    pthread_mutex_unlock(&kernel_lock);
}

// MARK: - Host pipe I/O

int kernel_send_input(const void *data, size_t length) {
    if (data == NULL || length == 0 || host_input_write < 0)
        return -1;
    ssize_t written = write(host_input_write, data, length);
    if (written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
        return 0;
    if (written < 0)
        return -1;
    return written > INT_MAX ? INT_MAX : (int)written;
}

int kernel_read_output(void *data, size_t capacity) {
    if (data == NULL || capacity == 0 || host_output_read < 0)
        return -1;
    ssize_t read_count = read(host_output_read, data, capacity);
    if (read_count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
        return 0;
    if (read_count < 0)
        return -1;
    return read_count > INT_MAX ? INT_MAX : (int)read_count;
}

int kernel_set_winsize(int cols, int rows) {
    (void)cols;
    (void)rows;
    // Pipes do not expose terminal geometry. Keep this API for Swift callers;
    // a real PTY can replace the transport later without changing the UI.
    return 0;
}

// MARK: - Rootfs import

int kernel_import_rootfs(const char *archive_path, const char *rootfs_path) {
    if (archive_path == NULL || rootfs_path == NULL)
        return -1;

    struct fakefsify_error error = {};
    bool imported = fakefs_import(archive_path, rootfs_path, &error, (struct progress) {});
    int result = imported ? 0 : -1;
    free(error.message);
    return result;
}

// MARK: - Filesystem

const char *kernel_fakefs_path(void) {
    lock(&mounts_lock);
    struct mount *root = mount_find("/");
    const char *path = root ? root->source : NULL;
    unlock(&mounts_lock);
    return path;
}

int kernel_bind_mount(const char *linux_path, const char *host_path) {
    if (!kernel_initialized || linux_path == NULL || host_path == NULL)
        return -1;
    return fakefs_bind_mount(linux_path, host_path, false);
}

int kernel_bind_unmount(const char *linux_path) {
    if (!kernel_initialized || linux_path == NULL)
        return -1;
    return fakefs_bind_unmount(linux_path);
}
