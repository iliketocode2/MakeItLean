/* LeanKV trusted C leaf: the real-file operations behind `LogFile` (Stage 5).
 * TRUSTED, NOT PROVEN: listed in TRUST.md; exercised by the real-file differential tests and the
 * kill tests. Every function returns a Lean IO result; failures become IO errors, which the Lean
 * shell turns into `false`/`none` (an I/O error in the store's terms). */
#include <lean/lean.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#include <libgen.h>
#include <stdlib.h>

static lean_obj_res io_err(const char *what) {
  return lean_io_result_mk_error(lean_mk_io_user_error(
      lean_mk_string(what)));
}

/* Open (creating if needed) the log at `path`, take an exclusive non-blocking lock, and fsync
 * the parent directory if the file was created. Returns the fd. */
LEAN_EXPORT lean_obj_res lkv_open(b_lean_obj_arg path, lean_obj_arg w) {
  const char *p = lean_string_cstr(path);
  struct stat st;
  int existed = stat(p, &st) == 0;
  int fd = open(p, O_RDWR | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
  if (fd < 0) return io_err(strerror(errno));
  if (flock(fd, LOCK_EX | LOCK_NB) != 0) { close(fd); return io_err("log is locked by another process"); }
  if (!existed) {
    if (fsync(fd) != 0) { close(fd); return io_err(strerror(errno)); }
    char *dup = strdup(p);
    int dfd = open(dirname(dup), O_RDONLY | O_DIRECTORY);
    free(dup);
    if (dfd >= 0) { fsync(dfd); close(dfd); }
  }
  return lean_io_result_mk_ok(lean_box_uint32((uint32_t)fd));
}

/* Read the whole file. */
LEAN_EXPORT lean_obj_res lkv_read_all(uint32_t fd, lean_obj_arg w) {
  struct stat st;
  if (fstat((int)fd, &st) != 0) return io_err(strerror(errno));
  size_t n = (size_t)st.st_size;
  lean_object *arr = lean_alloc_sarray(1, n, n);
  uint8_t *buf = lean_sarray_cptr(arr);
  size_t got = 0;
  while (got < n) {
    ssize_t r = pread((int)fd, buf + got, n - got, (off_t)got);
    if (r < 0) { if (errno == EINTR) continue; lean_dec(arr); return io_err(strerror(errno)); }
    if (r == 0) break;
    got += (size_t)r;
  }
  lean_to_sarray(arr)->m_size = got;
  return lean_io_result_mk_ok(arr);
}

/* Append all bytes (O_APPEND). A failure may leave a prefix written, as the model allows. */
LEAN_EXPORT lean_obj_res lkv_append(uint32_t fd, b_lean_obj_arg bytes, lean_obj_arg w) {
  const uint8_t *buf = lean_sarray_cptr(bytes);
  size_t n = lean_sarray_size(bytes), done = 0;
  while (done < n) {
    ssize_t r = write((int)fd, buf + done, n - done);
    if (r < 0) { if (errno == EINTR) continue; return io_err(strerror(errno)); }
    done += (size_t)r;
  }
  return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res lkv_fsync(uint32_t fd, lean_obj_arg w) {
  if (fsync((int)fd) != 0) return io_err(strerror(errno));
  return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res lkv_truncate(uint32_t fd, b_lean_obj_arg len, lean_obj_arg w) {
  if (!lean_is_scalar(len)) return io_err("length too large");
  if (ftruncate((int)fd, (off_t)lean_unbox(len)) != 0) return io_err(strerror(errno));
  return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res lkv_close(uint32_t fd, lean_obj_arg w) {
  close((int)fd);
  return lean_io_result_mk_ok(lean_box(0));
}
