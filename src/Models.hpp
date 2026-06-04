#pragma once

#include <string>
#include <vector>

struct GitResult {
    int status = 0;
    std::string out;
    std::string err;
};

struct StatusItem {
    std::string indexCode;
    std::string worktreeCode;
    std::string path;
    bool staged = false;
};

struct BranchItem {
    std::string name;
    std::string display;
    bool current = false;
    bool remote = false;
    bool checkable = true;
};

struct StashItem {
    std::string ref;
    std::string message;
};

struct FileItem {
    std::string path;
    bool tracked = true;
};

enum class Panel {
    Status,
    Diff,
    Log,
    Branches,
    Stashes,
    Remotes,
    Files,
    Search,
    Help
};

struct ViewLine {
    std::string text;
    int sourceIndex = -1;
    bool selectable = false;
};
