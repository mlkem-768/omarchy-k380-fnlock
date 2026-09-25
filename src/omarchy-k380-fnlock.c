#include <hidapi/hidapi.h>

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define VID 0x046d
#define PID 0xb342
#define USAGE_PAGE 0xff00
#define USAGE 1

#define APP_STATE_DIR "omarchy-k380-fnlock"

static char state_dir[PATH_MAX];
static char desired_file[PATH_MAX];
static char applied_file[PATH_MAX];

static const unsigned char fkeys_on[] = {
    0x10, 0xff, 0x0b, 0x1e, 0x00, 0x00, 0x00
};
static const unsigned char fkeys_off[] = {
    0x10, 0xff, 0x0b, 0x1e, 0x01, 0x00, 0x00
};

static int init_state_paths(void)
{
    const char *base = getenv("XDG_STATE_HOME");
    char fallback[PATH_MAX];

    if (!base || base[0] != '/') {
        const char *home = getenv("HOME");

        if (!home || home[0] != '/') {
            fprintf(stderr, "FnLock: HOME is not set to an absolute path\n");
            return -1;
        }

        int n = snprintf(fallback, sizeof(fallback), "%s/.local/state", home);
        if (n < 0 || (size_t)n >= sizeof(fallback)) {
            fprintf(stderr, "FnLock: State path is too long\n");
            return -1;
        }

        base = fallback;
    }

    int n = snprintf(state_dir, sizeof(state_dir), "%s/%s",
                     base, APP_STATE_DIR);
    if (n < 0 || (size_t)n >= sizeof(state_dir)) {
        fprintf(stderr, "FnLock: State path is too long\n");
        return -1;
    }

    n = snprintf(desired_file, sizeof(desired_file), "%s/desired", state_dir);
    if (n < 0 || (size_t)n >= sizeof(desired_file)) {
        fprintf(stderr, "FnLock: Desired-state path is too long\n");
        return -1;
    }

    n = snprintf(applied_file, sizeof(applied_file), "%s/applied", state_dir);
    if (n < 0 || (size_t)n >= sizeof(applied_file)) {
        fprintf(stderr, "FnLock: Applied-state path is too long\n");
        return -1;
    }

    return 0;
}

/* Create missing components without changing permissions of existing ones. */
static int mkdir_parents(const char *path)
{
    char copy[PATH_MAX];
    size_t len = strlen(path);

    if (len == 0 || len >= sizeof(copy) || path[0] != '/') {
        errno = EINVAL;
        return -1;
    }

    memcpy(copy, path, len + 1);

    for (char *p = copy + 1; ; p++) {
        if (*p != '/' && *p != '\0')
            continue;

        char saved = *p;
        *p = '\0';

        if (mkdir(copy, 0700) != 0 && errno != EEXIST)
            return -1;

        struct stat st;
        if (stat(copy, &st) != 0)
            return -1;
        if (!S_ISDIR(st.st_mode)) {
            errno = ENOTDIR;
            return -1;
        }

        *p = saved;
        if (saved == '\0')
            break;
    }

    return 0;
}

static int ensure_state_dir(void)
{
    if (mkdir_parents(state_dir) != 0)
        return -1;

    /* This directory contains only the current user's state. */
    if (chmod(state_dir, 0700) != 0)
        return -1;

    return 0;
}

/*
 * Return 0 on success and -1 on failure. ENOENT is preserved so callers can
 * distinguish an unset mode from an actual read error.
 */
static int read_mode(const char *path, char *mode, size_t size)
{
    FILE *f = fopen(path, "r");
    if (!f)
        return -1;

    if (!fgets(mode, (int)size, f)) {
        int saved_errno = ferror(f) ? errno : EINVAL;
        fclose(f);
        errno = saved_errno;
        return -1;
    }

    if (fclose(f) != 0)
        return -1;

    mode[strcspn(mode, "\r\n")] = '\0';
    return 0;
}

/* Write through a temporary file so a crash cannot leave a partial state. */
static int write_mode(const char *path, const char *mode)
{
    char temporary[PATH_MAX];

    int n = snprintf(temporary, sizeof(temporary), "%s.tmp.XXXXXX", path);
    if (n < 0 || (size_t)n >= sizeof(temporary)) {
        errno = ENAMETOOLONG;
        return -1;
    }

    int fd = mkstemp(temporary);
    if (fd < 0)
        return -1;

    int ok = 1;
    if (fchmod(fd, 0600) != 0)
        ok = 0;

    FILE *f = fdopen(fd, "w");
    if (!f) {
        int saved_errno = errno;
        close(fd);
        unlink(temporary);
        errno = saved_errno;
        return -1;
    }

    if (fprintf(f, "%s\n", mode) < 0)
        ok = 0;
    if (fflush(f) != 0)
        ok = 0;
    if (fsync(fileno(f)) != 0)
        ok = 0;
    if (fclose(f) != 0)
        ok = 0;

    if (ok && rename(temporary, path) != 0)
        ok = 0;

    if (!ok) {
        int saved_errno = errno ? errno : EIO;
        unlink(temporary);
        errno = saved_errno;
        return -1;
    }

    return 0;
}

static int send_mode(const char *mode)
{
    const unsigned char *command;

    if (strcmp(mode, "on") == 0) {
        command = fkeys_on;
    } else if (strcmp(mode, "off") == 0) {
        command = fkeys_off;
    } else {
        fprintf(stderr, "FnLock: Invalid mode '%s'\n", mode);
        return 1;
    }

    if (hid_init() != 0) {
        fprintf(stderr, "FnLock: HIDapi initialization failed\n");
        return 1;
    }

    struct hid_device_info *devices = hid_enumerate(VID, PID);
    int result = 1;

    for (struct hid_device_info *device = devices;
         device;
         device = device->next) {
        if (device->usage_page != USAGE_PAGE || device->usage != USAGE)
            continue;

        hid_device *handle = hid_open_path(device->path);
        if (!handle)
            continue;

        int written = hid_write(handle, command, sizeof(fkeys_on));
        hid_close(handle);

        if (written == (int)sizeof(fkeys_on)) {
            if (write_mode(applied_file, mode) == 0) {
                printf("FnLock: Fn-key mode %s applied\n", mode);
                result = 0;
            } else {
                perror("FnLock: Cannot write applied state");
            }
            break;
        }

        fprintf(stderr, "FnLock: HID write failed (%d)\n", written);
    }

    if (result != 0)
        fprintf(stderr, "FnLock: K380 HID interface not found or write failed\n");

    hid_free_enumeration(devices);
    hid_exit();
    return result;
}

static int set_mode(const char *mode)
{
    if (strcmp(mode, "on") != 0 && strcmp(mode, "off") != 0) {
        fprintf(stderr, "FnLock: Mode must be 'on' or 'off'\n");
        return 2;
    }

    if (write_mode(desired_file, mode) != 0) {
        perror("FnLock: Cannot save desired mode");
        return 1;
    }

    return send_mode(mode);
}

static int print_state(const char *label, const char *path)
{
    char mode[16];

    if (read_mode(path, mode, sizeof(mode)) == 0) {
        printf("%s: %s\n", label, mode);
        return 0;
    }

    if (errno == ENOENT) {
        printf("%s: Not set\n", label);
        return 0;
    }

    fprintf(stderr, "FnLock: Cannot read %s state: %s\n",
            label, strerror(errno));
    return 1;
}

int main(int argc, char **argv)
{
    if (init_state_paths() != 0) {
        return 1;
    }

    if (ensure_state_dir() != 0) {
        perror("FnLock: Cannot create state directory");
        return 1;
    }

    if (argc == 2 && strcmp(argv[1], "apply") == 0) {
        char mode[16];

        if (read_mode(desired_file, mode, sizeof(mode)) != 0) {
            if (errno == ENOENT)
                fprintf(stderr, "FnLock: Desired mode is not configured\n");
            else
                perror("FnLock: Cannot read desired mode");
            return 1;
        }

        return send_mode(mode);
    }

    /*
     * Used by the udev-triggered user service. No saved mode is a normal
     * first-run condition, not a service failure.
     */
    if (argc == 2 && strcmp(argv[1], "apply-if-configured") == 0) {
        char mode[16];

        if (read_mode(desired_file, mode, sizeof(mode)) != 0) {
            if (errno == ENOENT)
                return 0;

            perror("FnLock: Cannot read desired mode");
            return 1;
        }

        return send_mode(mode);
    }

    if (argc == 3 && strcmp(argv[1], "set") == 0)
        return set_mode(argv[2]);

    if (argc == 2 && strcmp(argv[1], "toggle") == 0) {
        char mode[16];
        const char *next = "on";

        if (read_mode(desired_file, mode, sizeof(mode)) == 0) {
            if (strcmp(mode, "on") == 0)
                next = "off";
            else if (strcmp(mode, "off") != 0) {
                fprintf(stderr, "FnLock: Invalid saved mode '%s'\n", mode);
                return 1;
            }
        } else if (errno != ENOENT) {
            perror("FnLock: Cannot read desired mode");
            return 1;
        }

        return set_mode(next);
    }

    if (argc == 2 && strcmp(argv[1], "status") == 0) {
        int result = print_state("Desired", desired_file);
        if (print_state("Applied", applied_file) != 0)
            result = 1;
        return result;
    }

    fprintf(stderr,
            "Usage: %s {apply|status|toggle|set on|set off}\n",
            argv[0]);
    return 2;
}