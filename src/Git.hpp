#pragma once

#include "Models.hpp"

#include <string>
#include <vector>

class Git {
public:
    explicit Git(std::string repoPath);

    const std::string &repoPath() const;
    GitResult run(const std::vector<std::string> &args) const;

    bool isRepo() const;
    std::string currentBranch() const;
    std::vector<StatusItem> status() const;
    std::vector<std::string> diff() const;
    std::vector<std::string> fileDiff(const StatusItem &item) const;
    std::vector<std::string> log() const;
    std::vector<std::string> showCommit(const std::string &line) const;
    std::vector<BranchItem> branches() const;
    std::vector<StashItem> stashes() const;
    std::vector<std::string> showStash(const StashItem &item) const;
    std::vector<std::string> remotes() const;
    std::vector<FileItem> files() const;
    std::vector<std::string> blame(const std::string &path) const;
    std::vector<std::string> grep(const std::string &term) const;
    std::string rootPath() const;
    std::string extractCommitHash(const std::string &line) const;

private:
    std::string repoPath_;
};
