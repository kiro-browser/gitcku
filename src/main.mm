#include "App.hpp"

#include <limits.h>
#include <string>
#include <unistd.h>

static std::string initialRepoPath(int argc, char **argv) {
    if (argc > 1) return argv[1];
    char buffer[PATH_MAX] = {0};
    if (getcwd(buffer, sizeof(buffer))) return buffer;
    return ".";
}

int main(int argc, char **argv) {
    App app(initialRepoPath(argc, argv));
    return app.run();
}
