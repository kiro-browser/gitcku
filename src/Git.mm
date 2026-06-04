#include "Git.hpp"
#include "TextUtils.hpp"

#import <Foundation/Foundation.h>

#include <cctype>
#include <set>
#include <utility>

static NSString *toNSString(const std::string &value) {
    return [NSString stringWithUTF8String:value.c_str()];
}

static std::string toString(NSString *value) {
    if (!value) return "";
    const char *utf8 = [value UTF8String];
    return utf8 ? std::string(utf8) : "";
}

Git::Git(std::string repoPath) : repoPath_(std::move(repoPath)) {}

const std::string &Git::repoPath() const {
    return repoPath_;
}

GitResult Git::run(const std::vector<std::string> &args) const {
    @autoreleasepool {
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/git";
        task.currentDirectoryPath = toNSString(repoPath_);

        NSMutableArray<NSString *> *arguments = [NSMutableArray array];
        for (const std::string &arg : args) {
            [arguments addObject:toNSString(arg)];
        }
        task.arguments = arguments;

        NSPipe *stdoutPipe = [NSPipe pipe];
        NSPipe *stderrPipe = [NSPipe pipe];
        task.standardOutput = stdoutPipe;
        task.standardError = stderrPipe;

        @try {
            [task launch];
            [task waitUntilExit];
        } @catch (NSException *exception) {
            return {127, "", toString(exception.reason)};
        }

        NSData *stdoutData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
        NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
        NSString *stdoutText = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding];
        NSString *stderrText = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding];
        return {task.terminationStatus, toString(stdoutText), toString(stderrText)};
    }
}

bool Git::isRepo() const {
    return run({"rev-parse", "--is-inside-work-tree"}).status == 0;
}

std::string Git::currentBranch() const {
    std::string branch = trim(run({"branch", "--show-current"}).out);
    return branch.empty() ? "detached" : branch;
}

std::vector<StatusItem> Git::status() const {
    std::vector<StatusItem> items;
    GitResult result = run({"status", "--porcelain=v1"});
    for (const std::string &line : splitLines(result.out)) {
        if (line.size() < 4) continue;
        StatusItem item;
        item.indexCode = line.substr(0, 1);
        item.worktreeCode = line.substr(1, 1);
        item.path = line.substr(3);
        item.staged = item.indexCode != " " && item.indexCode != "?";
        items.push_back(item);
    }
    return items;
}

std::vector<std::string> Git::diff() const {
    GitResult result = run({"diff", "--stat", "--patch"});
    std::vector<std::string> lines = splitLines(result.out.empty() ? result.err : result.out);
    if (lines.empty()) lines.push_back("No unstaged diff.");
    return lines;
}

std::vector<std::string> Git::fileDiff(const StatusItem &item) const {
    GitResult result = item.staged
        ? run({"diff", "--cached", "--", item.path})
        : run({"diff", "--", item.path});
    std::vector<std::string> lines = splitLines(result.out.empty() ? result.err : result.out);
    if (lines.empty()) lines.push_back("No diff for " + item.path + ".");
    return lines;
}

std::vector<std::string> Git::log() const {
    GitResult result = run({"log", "--graph", "--decorate", "--oneline", "-n", "120"});
    std::vector<std::string> lines = splitLines(result.out.empty() ? result.err : result.out);
    if (lines.empty()) lines.push_back("No commits yet.");
    return lines;
}

std::vector<std::string> Git::showCommit(const std::string &line) const {
    std::string hash = extractCommitHash(line);
    if (hash.empty()) return {"Could not parse commit hash."};
    GitResult result = run({"show", "--stat", "--patch", "--decorate", hash});
    std::vector<std::string> lines = splitLines(result.out.empty() ? result.err : result.out);
    if (lines.empty()) lines.push_back("No details for commit " + hash + ".");
    return lines;
}

std::vector<BranchItem> Git::branches() const {
    std::vector<BranchItem> items;
    GitResult result = run({"branch", "--all", "--sort=-committerdate"});
    for (const std::string &raw : splitLines(result.out)) {
        std::string line = trim(raw);
        if (line.empty()) continue;
        BranchItem item;
        item.current = line[0] == '*';
        if (item.current) line = trim(line.substr(1));
        item.display = (item.current ? "* " : "  ") + line;
        item.remote = line.rfind("remotes/", 0) == 0;
        item.name = item.remote ? line.substr(8) : line;
        item.checkable = line.find("HEAD ->") == std::string::npos;
        items.push_back(item);
    }
    return items;
}

std::vector<StashItem> Git::stashes() const {
    std::vector<StashItem> items;
    GitResult result = run({"stash", "list"});
    for (const std::string &line : splitLines(result.out)) {
        size_t sep = line.find(':');
        if (sep == std::string::npos) continue;
        items.push_back({line.substr(0, sep), trim(line.substr(sep + 1))});
    }
    return items;
}

std::vector<std::string> Git::showStash(const StashItem &item) const {
    GitResult result = run({"stash", "show", "--stat", "--patch", item.ref});
    std::vector<std::string> lines = splitLines(result.out.empty() ? result.err : result.out);
    if (lines.empty()) lines.push_back("No details for " + item.ref + ".");
    return lines;
}

std::vector<std::string> Git::remotes() const {
    GitResult result = run({"remote", "-v"});
    std::vector<std::string> lines = splitLines(result.out.empty() ? result.err : result.out);
    if (lines.empty()) lines.push_back("No remotes configured.");
    return lines;
}

std::vector<FileItem> Git::files() const {
    std::vector<FileItem> items;
    std::set<std::string> seen;
    GitResult tracked = run({"ls-files"});
    for (const std::string &line : splitLines(tracked.out)) {
        if (line.empty() || seen.count(line)) continue;
        seen.insert(line);
        items.push_back({line, true});
    }
    GitResult untracked = run({"ls-files", "--others", "--exclude-standard"});
    for (const std::string &line : splitLines(untracked.out)) {
        if (line.empty() || seen.count(line)) continue;
        seen.insert(line);
        items.push_back({line, false});
    }
    return items;
}

std::vector<std::string> Git::blame(const std::string &path) const {
    GitResult result = run({"blame", "--date=short", "--", path});
    std::vector<std::string> lines = splitLines(result.out.empty() ? result.err : result.out);
    if (lines.empty()) lines.push_back("No blame data for " + path + ".");
    return lines;
}

std::vector<std::string> Git::grep(const std::string &term) const {
    GitResult result = run({"grep", "-n", "--heading", "--break", "--", term});
    std::vector<std::string> lines = splitLines(result.out.empty() ? result.err : result.out);
    if (lines.empty()) lines.push_back("No matches for " + term + ".");
    return lines;
}

std::string Git::rootPath() const {
    return trim(run({"rev-parse", "--show-toplevel"}).out);
}

std::string Git::extractCommitHash(const std::string &line) const {
    size_t pos = line.find_first_of("0123456789abcdef");
    if (pos == std::string::npos) return "";
    size_t end = pos;
    while (end < line.size() && std::isxdigit(static_cast<unsigned char>(line[end]))) end++;
    if (end - pos < 7) return "";
    return line.substr(pos, end - pos);
}
