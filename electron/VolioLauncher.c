#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static void show_dialog(const char *message) {
  char command[4096];
  snprintf(
    command,
    sizeof(command),
    "/usr/bin/osascript -e 'display dialog \"%s\" with title \"Volio Desktop\" buttons {\"OK\"} default button \"OK\"' >/dev/null 2>&1",
    message
  );
  system(command);
}

int main(void) {
  char executable_path[PATH_MAX];
  uint32_t size = sizeof(executable_path);

#ifdef __APPLE__
  extern int _NSGetExecutablePath(char *buf, uint32_t *bufsize);
  if (_NSGetExecutablePath(executable_path, &size) != 0) {
    show_dialog("Volio Desktop could not locate its launcher path.");
    return 1;
  }
#else
  if (!getcwd(executable_path, sizeof(executable_path))) {
    return 1;
  }
#endif

  char *macos_dir = strrchr(executable_path, '/');
  if (!macos_dir) return 1;
  *macos_dir = '\0';

  char root[PATH_MAX];
  snprintf(root, sizeof(root), "%s/../../..", executable_path);

  char script[8192];
  snprintf(
    script,
    sizeof(script),
    "set -u\n"
    "ROOT=\"$(cd '%s' && pwd)\"\n"
    "LOG=\"/tmp/volio-electron-launch.log\"\n"
    "export PATH=\"$HOME/.local/bin:$HOME/.hermes/node/bin:$HOME/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH\"\n"
    "NPM=\"\"\n"
    "for candidate in \"$HOME/.local/bin/npm\" \"$HOME/.hermes/node/bin/npm\" \"$HOME/.npm-global/bin/npm\" /opt/homebrew/bin/npm /usr/local/bin/npm /usr/bin/npm; do\n"
    "  if [ -x \"$candidate\" ]; then NPM=\"$candidate\"; break; fi\n"
    "done\n"
    "if [ -z \"$NPM\" ]; then NPM=\"$(/usr/bin/which npm 2>/dev/null || true)\"; fi\n"
    "if [ -n \"$NPM\" ] && [ -f \"$ROOT/package.json\" ]; then\n"
    "  cd \"$ROOT\" || exit 1\n"
    "  if [ ! -f \"$ROOT/frontend/dist/index.html\" ]; then\n"
    "    \"$NPM\" run build:frontend >\"$LOG\" 2>&1 || exit 2\n"
    "  fi\n"
    "  exec \"$NPM\" run electron:launch >\"$LOG\" 2>&1\n"
    "fi\n"
    "exit 3\n",
    root
  );

  const char *argv[] = {"/bin/zsh", "-lc", script, NULL};
  int status = 0;
  pid_t pid = fork();
  if (pid == 0) {
    execv(argv[0], (char *const *)argv);
    _exit(127);
  }
  if (pid < 0 || waitpid(pid, &status, 0) < 0) {
    show_dialog("Volio Desktop could not start. Check /tmp/volio-electron-launch.log for details.");
    return 1;
  }
  if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
    return 0;
  }
  show_dialog("Volio Desktop could not start. Check /tmp/volio-electron-launch.log for details.");
  return 1;
}
