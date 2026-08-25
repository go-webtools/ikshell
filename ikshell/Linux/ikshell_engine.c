//
//  ikshell_engine.c
//  真实的 iSH 内核桥接层
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <limits.h>
#include <errno.h>

// iSH 内核头文件
#include "kernel/init.h"
#include "kernel/task.h"
#include "kernel/fs.h"
#include "kernel/calls.h"
#include "fs/fd.h"
#include "fs/tty.h"
#include "fs/fake.h"
#include "fs/dev.h"
#include "platform/platform.h"

// 全局状态
static int kernel_initialized = 0;
static struct tty *main_tty = NULL;
static pthread_mutex_t kernel_lock = PTHREAD_MUTEX_INITIALIZER;

// MARK: - Kernel lifecycle

int kernel_boot(const char *rootfs_path, char *const argv[]) {
    pthread_mutex_lock(&kernel_lock);

    if (kernel_initialized) {
        pthread_mutex_unlock(&kernel_lock);
        return -1;
    }

    printf("ikshell: booting Linux kernel with rootfs=%s\n", rootfs_path);

    // 1. 挂载 fakefs 作为根文件系统
    if (mount_root(&fakefs, rootfs_path) != 0) {
        fprintf(stderr, "ikshell: failed to mount rootfs\n");
        pthread_mutex_unlock(&kernel_lock);
        return -1;
    }

    // 2. 挂载 devpts (PTY 从设备文件系统)
    lock(&mounts_lock);
    int ret = do_mount(&devptsfs, "", "/dev/pts", "", 0);
    unlock(&mounts_lock);
    if (ret < 0) {
        fprintf(stderr, "ikshell: failed to mount devpts: %d\n", ret);
        pthread_mutex_unlock(&kernel_lock);
        return -1;
    }

    // 3. 创建 init 进程 (PID 1)
    if (become_first_process() != 0) {
        fprintf(stderr, "ikshell: failed to create init process\n");
        pthread_mutex_unlock(&kernel_lock);
        return -1;
    }

    // 4. 创建 stdio (使用管道连接到主机)
    if (create_piped_stdio() != 0) {
        fprintf(stderr, "ikshell: failed to create stdio\n");
        pthread_mutex_unlock(&kernel_lock);
        return -1;
    }

    kernel_initialized = 1;
    printf("ikshell: kernel boot complete\n");

    pthread_mutex_unlock(&kernel_lock);
    return 0;
}

void kernel_shutdown(void) {
    pthread_mutex_lock(&kernel_lock);

    if (!kernel_initialized) {
        pthread_mutex_unlock(&kernel_lock);
        return;
    }

    printf("ikshell: shutting down kernel\n");

    // 清理 TTY
    if (main_tty != NULL) {
        tty_hangup(main_tty);
        main_tty = NULL;
    }

    // 卸载文件系统
    lock(&mounts_lock);
    do_umount("/dev/pts");
    unlock(&mounts_lock);

    kernel_initialized = 0;
    pthread_mutex_unlock(&kernel_lock);
}

// MARK: - PTY (pseudo-terminal)

int kernel_openpty(void) {
    pthread_mutex_lock(&kernel_lock);

    if (!kernel_initialized) {
        pthread_mutex_unlock(&kernel_lock);
        return -1;
    }

    // 使用 iSH 的 pty_open_fake 创建 PTY
    extern struct tty_driver pty_slave;
    struct tty *tty = pty_open_fake(&pty_slave);
    if (tty == NULL) {
        fprintf(stderr, "ikshell: failed to create PTY\n");
        pthread_mutex_unlock(&kernel_lock);
        return -1;
    }

    main_tty = tty;

    // 创建一个新的 init 子进程来运行 shell
    if (become_new_init_child() != 0) {
        fprintf(stderr, "ikshell: failed to create init child\n");
        pthread_mutex_unlock(&kernel_lock);
        return -1;
    }

    // 打开 PTY 作为 stdio
    struct fd *fd = fd_create(NULL);
    if (tty_open(tty, fd) != 0) {
        fprintf(stderr, "ikshell: failed to open TTY\n");
        pthread_mutex_unlock(&kernel_lock);
        return -1;
    }

    // 复制 fd 到 stdin/stdout/stderr
    current->files->files[0] = fd;
    current->files->files[1] = fd;
    current->files->files[2] = fd;
    fd->refcount = 3;

    // 执行 shell
    const char *shell_argv[] = {"/bin/sh", "-l", NULL};
    const char *shell_envp[] = {
        "PATH=/usr/local/bin:/usr/bin:/bin",
        "HOME=/root",
        "TERM=xterm-256color",
        NULL
    };

    // 将参数转换为 iSH 期望的格式
    size_t argv_size = 0;
    for (int i = 0; shell_argv[i]; i++) {
        argv_size += strlen(shell_argv[i]) + 1;
    }
    char *argv_buf = malloc(argv_size);
    char *p = argv_buf;
    for (int i = 0; shell_argv[i]; i++) {
        strcpy(p, shell_argv[i]);
        p += strlen(shell_argv[i]) + 1;
    }

    size_t envp_size = 0;
    for (int i = 0; shell_envp[i]; i++) {
        envp_size += strlen(shell_envp[i]) + 1;
    }
    char *envp_buf = malloc(envp_size);
    p = envp_buf;
    for (int i = 0; shell_envp[i]; i++) {
        strcpy(p, shell_envp[i]);
        p += strlen(shell_envp[i]) + 1;
    }

    int exec_ret = do_execve("/bin/sh", 2, argv_buf, envp_buf);
    free(argv_buf);
    free(envp_buf);

    if (exec_ret < 0) {
        fprintf(stderr, "ikshell: failed to exec shell: %d\n", exec_ret);
        pthread_mutex_unlock(&kernel_lock);
        return -1;
    }

    // 启动任务执行
    task_run_current();

    printf("ikshell: PTY opened, shell started\n");
    pthread_mutex_unlock(&kernel_lock);

    // 返回一个虚拟 fd（Swift 层用来标识这个 TTY）
    return (int)(intptr_t)tty;
}

int kernel_pty_read(int fd, void *buf, size_t count) {
    if (fd <= 0 || !kernel_initialized || main_tty == NULL) {
        return -1;
    }

    struct tty *tty = (struct tty *)(intptr_t)fd;

    // 从 TTY 输出缓冲区读取
    pthread_mutex_lock(&kernel_lock);

    // TTY 输出在 tty->buf 中
    if (tty->bufsize == 0) {
        pthread_mutex_unlock(&kernel_lock);
        return 0; // 无数据
    }

    size_t to_read = (count < tty->bufsize) ? count : tty->bufsize;
    memcpy(buf, tty->buf, to_read);

    // 移动剩余数据
    memmove(tty->buf, tty->buf + to_read, tty->bufsize - to_read);
    tty->bufsize -= to_read;

    pthread_mutex_unlock(&kernel_lock);

    if (to_read > INT_MAX) {
        return INT_MAX;
    }
    return (int)to_read;
}

int kernel_pty_write(int fd, const void *buf, size_t count) {
    if (fd <= 0 || !kernel_initialized || main_tty == NULL) {
        return -1;
    }

    struct tty *tty = (struct tty *)(intptr_t)fd;

    pthread_mutex_lock(&kernel_lock);

    // 将输入写入 TTY（相当于用户键盘输入）
    ssize_t n = tty_input(tty, (const char *)buf, count, false);

    pthread_mutex_unlock(&kernel_lock);

    if (n < 0) {
        return -1;
    }
    if (n > INT_MAX) {
        return INT_MAX;
    }
    return (int)n;
}

// MARK: - Filesystem

const char *kernel_fakefs_path(void) {
    // 返回当前挂载的 rootfs 路径
    lock(&mounts_lock);
    struct mount *root = mount_find("/");
    const char *path = root ? root->source : NULL;
    unlock(&mounts_lock);
    return path;
}

// MARK: - Bind Mount (用于访问 iOS Documents 目录)

int kernel_bind_mount(const char *linux_path, const char *host_path) {
    if (!kernel_initialized) {
        return -1;
    }

    return fakefs_bind_mount(linux_path, host_path, false);
}

int kernel_bind_unmount(const char *linux_path) {
    if (!kernel_initialized) {
        return -1;
    }

    return fakefs_bind_unmount(linux_path);
}
