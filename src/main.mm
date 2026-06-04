#import <Foundation/Foundation.h>
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <locale.h>
#include <ncurses.h>
#include <sstream>
#include <string>
#include <vector>

using std::string;
using std::vector;

struct GitResult {
    int status = 0;
    string out;
    string err;
};

struct StatusItem {
    string indexCode;
    string worktreeCode;
    string path;
    bool staged = false;
};

static NSString *toNSString(const string &value) {
    return [NSString stringWithUTF8String:value.c_str()];
}

static string toString(NSString *value) {
    if (!value) return "";
    const char *utf8 = [value UTF8String];
    return utf8 ? string(utf8) : "";
}

static vector<string> splitLines(const string &text) {
    vector<string> lines;
    std::stringstream stream(text);
    string line;
    while (std::getline(stream, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        lines.push_back(line);
    }
    return lines;
}

static string trim(const string &value) {
    size_t first = 0;
    while (first < value.size() && std::isspace(static_cast<unsigned char>(value[first]))) first++;
    size_t last = value.size();
    while (last > first && std::isspace(static_cast<unsigned char>(value[last - 1]))) last--;
    return value.substr(first, last - first);
}

class Git {
public:
    explicit Git(string repoPath) : repoPath_(std::move(repoPath)) {}

    GitResult run(const vector<string> &args) const {
        @autoreleasepool {
            NSTask *task = [[NSTask alloc] init];
            task.launchPath = @"/usr/bin/git";
            task.currentDirectoryPath = toNSString(repoPath_);

            NSMutableArray<NSString *> *arguments = [NSMutableArray array];
            for (const string &arg : args) {
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

    bool isRepo() const {
        return run({"rev-parse", "--is-inside-work-tree"}).status == 0;
    }

private:
    string repoPath_;
};

enum class Panel {
    Status,
    Diff,
    Log,
    Branches
};

class App {
public:
    explicit App(string repoPath) : repoPath_(std::move(repoPath)), git_(repoPath_) {}

    int run() {
        if (!git_.isRepo()) {
            fprintf(stderr, "gitcku: not a git repository: %s\n", repoPath_.c_str());
            return 2;
        }

        setlocale(LC_ALL, "");
        initscr();
        cbreak();
        noecho();
        keypad(stdscr, TRUE);
        curs_set(0);
        start_color();
        use_default_colors();
        init_pair(1, COLOR_CYAN, -1);
        init_pair(2, COLOR_GREEN, -1);
        init_pair(3, COLOR_YELLOW, -1);
        init_pair(4, COLOR_RED, -1);
        init_pair(5, COLOR_BLACK, COLOR_CYAN);

        refreshAll();
        bool active = true;
        while (active) {
            draw();
            int ch = getch();
            active = handleKey(ch);
        }

        endwin();
        return 0;
    }

private:
    string repoPath_;
    Git git_;
    Panel panel_ = Panel::Status;
    vector<StatusItem> status_;
    vector<string> diff_;
    vector<string> log_;
    vector<string> branches_;
    string branch_;
    string message_;
    int selected_ = 0;
    int scroll_ = 0;

    void refreshAll() {
        GitResult branchResult = git_.run({"branch", "--show-current"});
        branch_ = trim(branchResult.out);
        if (branch_.empty()) branch_ = "detached";

        loadStatus();
        loadDiff();
        loadLog();
        loadBranches();
    }

    void loadStatus() {
        status_.clear();
        GitResult result = git_.run({"status", "--porcelain=v1"});
        for (const string &line : splitLines(result.out)) {
            if (line.size() < 4) continue;
            StatusItem item;
            item.indexCode = line.substr(0, 1);
            item.worktreeCode = line.substr(1, 1);
            item.path = line.substr(3);
            item.staged = item.indexCode != " " && item.indexCode != "?";
            status_.push_back(item);
        }
        clampSelection();
    }

    void loadDiff() {
        GitResult result = git_.run({"diff", "--stat", "--patch"});
        diff_ = splitLines(result.out.empty() ? result.err : result.out);
        if (diff_.empty()) diff_.push_back("No unstaged diff.");
    }

    void loadLog() {
        GitResult result = git_.run({"log", "--graph", "--decorate", "--oneline", "-n", "80"});
        log_ = splitLines(result.out.empty() ? result.err : result.out);
        if (log_.empty()) log_.push_back("No commits yet.");
    }

    void loadBranches() {
        GitResult result = git_.run({"branch", "--all", "--sort=-committerdate"});
        branches_ = splitLines(result.out.empty() ? result.err : result.out);
        if (branches_.empty()) branches_.push_back("No branches.");
        clampSelection();
    }

    vector<string> currentLines() const {
        if (panel_ == Panel::Diff) return diff_;
        if (panel_ == Panel::Log) return log_;
        if (panel_ == Panel::Branches) return branches_;

        vector<string> lines;
        for (const StatusItem &item : status_) {
            string marker = item.staged ? "[staged]   " : "[worktree] ";
            lines.push_back(marker + item.indexCode + item.worktreeCode + " " + item.path);
        }
        if (lines.empty()) lines.push_back("Working tree clean.");
        return lines;
    }

    string panelName() const {
        switch (panel_) {
            case Panel::Status: return "Status";
            case Panel::Diff: return "Diff";
            case Panel::Log: return "Log";
            case Panel::Branches: return "Branches";
        }
        return "";
    }

    void draw() {
        erase();
        int rows = 0;
        int cols = 0;
        getmaxyx(stdscr, rows, cols);

        attron(COLOR_PAIR(1) | A_BOLD);
        mvprintw(0, 0, "gitcku");
        attroff(COLOR_PAIR(1) | A_BOLD);
        mvprintw(0, 8, "%s", repoPath_.c_str());
        attron(COLOR_PAIR(3));
        mvprintw(1, 0, "branch: %s", branch_.c_str());
        attroff(COLOR_PAIR(3));
        mvprintw(1, std::max(0, cols - 24), "[%s]", panelName().c_str());

        drawTabs(cols);
        drawContent(rows, cols);
        drawFooter(rows, cols);
        refresh();
    }

    void drawTabs(int cols) {
        string tabs = " 1 Status   2 Diff   3 Log   4 Branches ";
        attron(A_REVERSE);
        mvprintw(3, 0, "%-*s", cols, tabs.c_str());
        attroff(A_REVERSE);
    }

    void drawContent(int rows, int cols) {
        vector<string> lines = currentLines();
        int top = 5;
        int bottom = rows - 3;
        int height = std::max(0, bottom - top + 1);
        clampScroll(height, static_cast<int>(lines.size()));

        for (int i = 0; i < height; i++) {
            int lineIndex = scroll_ + i;
            if (lineIndex >= static_cast<int>(lines.size())) break;
            bool highlighted = lineIndex == selected_ && (panel_ == Panel::Status || panel_ == Panel::Branches);
            if (highlighted) attron(COLOR_PAIR(5));

            string line = lines[lineIndex];
            if (static_cast<int>(line.size()) > cols - 1) {
                line = line.substr(0, std::max(0, cols - 2));
            }
            mvprintw(top + i, 0, "%-*s", cols, line.c_str());

            if (highlighted) attroff(COLOR_PAIR(5));
        }
    }

    void drawFooter(int rows, int cols) {
        attron(A_REVERSE);
        string keys = " q quit  r refresh  space stage/unstage  a stage-all  u unstage-all  c commit  b checkout  P pull  p push ";
        mvprintw(rows - 2, 0, "%-*s", cols, keys.substr(0, cols).c_str());
        attroff(A_REVERSE);
        move(rows - 1, 0);
        clrtoeol();
        if (!message_.empty()) {
            attron(COLOR_PAIR(2));
            mvprintw(rows - 1, 0, "%s", message_.substr(0, cols - 1).c_str());
            attroff(COLOR_PAIR(2));
        }
    }

    bool handleKey(int ch) {
        switch (ch) {
            case 'q': return false;
            case '1': switchPanel(Panel::Status); break;
            case '2': switchPanel(Panel::Diff); break;
            case '3': switchPanel(Panel::Log); break;
            case '4': switchPanel(Panel::Branches); break;
            case 'j':
            case KEY_DOWN: moveSelection(1); break;
            case 'k':
            case KEY_UP: moveSelection(-1); break;
            case 'g': selected_ = 0; scroll_ = 0; break;
            case 'G': selected_ = std::max(0, lineCount() - 1); break;
            case 'r': refreshAll(); setMessage("Refreshed."); break;
            case ' ': toggleStage(); break;
            case 'a': runAndRefresh({"add", "--all"}, "Staged all changes."); break;
            case 'u': runAndRefresh({"reset", "--"}, "Unstaged all changes."); break;
            case 'c': commitPrompt(); break;
            case 'b': checkoutSelectedBranch(); break;
            case 'p': runAndRefresh({"push"}, "Push finished."); break;
            case 'P': runAndRefresh({"pull", "--ff-only"}, "Pull finished."); break;
            default: break;
        }
        return true;
    }

    void switchPanel(Panel panel) {
        panel_ = panel;
        selected_ = 0;
        scroll_ = 0;
        if (panel_ == Panel::Diff) loadDiff();
        if (panel_ == Panel::Log) loadLog();
        if (panel_ == Panel::Branches) loadBranches();
    }

    int lineCount() const {
        if (panel_ == Panel::Status) return std::max(1, static_cast<int>(status_.size()));
        if (panel_ == Panel::Branches) return std::max(1, static_cast<int>(branches_.size()));
        if (panel_ == Panel::Diff) return std::max(1, static_cast<int>(diff_.size()));
        return std::max(1, static_cast<int>(log_.size()));
    }

    void moveSelection(int delta) {
        selected_ = std::clamp(selected_ + delta, 0, lineCount() - 1);
    }

    void clampSelection() {
        selected_ = std::clamp(selected_, 0, lineCount() - 1);
    }

    void clampScroll(int height, int total) {
        if (selected_ < scroll_) scroll_ = selected_;
        if (selected_ >= scroll_ + height) scroll_ = selected_ - height + 1;
        int maxScroll = std::max(0, total - height);
        scroll_ = std::clamp(scroll_, 0, maxScroll);
    }

    void setMessage(const string &message) {
        message_ = message;
    }

    void runAndRefresh(const vector<string> &args, const string &success) {
        GitResult result = git_.run(args);
        refreshAll();
        setMessage(result.status == 0 ? success : trim(result.err.empty() ? result.out : result.err));
    }

    void toggleStage() {
        if (panel_ != Panel::Status || status_.empty() || selected_ >= static_cast<int>(status_.size())) return;
        const StatusItem &item = status_[selected_];
        if (item.staged) {
            runAndRefresh({"reset", "--", item.path}, "Unstaged " + item.path);
        } else {
            runAndRefresh({"add", "--", item.path}, "Staged " + item.path);
        }
    }

    string prompt(const string &label) {
        int rows = 0;
        int cols = 0;
        getmaxyx(stdscr, rows, cols);
        echo();
        curs_set(1);
        move(rows - 1, 0);
        clrtoeol();
        attron(A_REVERSE);
        mvprintw(rows - 1, 0, "%s", label.c_str());
        attroff(A_REVERSE);
        char buffer[1024] = {0};
        getnstr(buffer, sizeof(buffer) - 1);
        noecho();
        curs_set(0);
        return trim(buffer);
    }

    void commitPrompt() {
        string message = prompt("Commit message: ");
        if (message.empty()) {
            setMessage("Commit cancelled.");
            return;
        }
        runAndRefresh({"commit", "-m", message}, "Commit created.");
    }

    string selectedBranchName() const {
        if (panel_ != Panel::Branches || branches_.empty() || selected_ >= static_cast<int>(branches_.size())) return "";
        string line = trim(branches_[selected_]);
        if (!line.empty() && line[0] == '*') line = trim(line.substr(1));
        const string remotePrefix = "remotes/";
        if (line.rfind(remotePrefix, 0) == 0) line = line.substr(remotePrefix.size());
        if (line.find("HEAD ->") != string::npos) return "";
        return line;
    }

    void checkoutSelectedBranch() {
        string branch = selectedBranchName();
        if (branch.empty()) {
            setMessage("Select a branch first.");
            return;
        }
        runAndRefresh({"checkout", branch}, "Checked out " + branch);
    }
};

static string initialRepoPath(int argc, char **argv) {
    if (argc > 1) return argv[1];
    char buffer[PATH_MAX] = {0};
    if (getcwd(buffer, sizeof(buffer))) return buffer;
    return ".";
}

int main(int argc, char **argv) {
    @autoreleasepool {
        App app(initialRepoPath(argc, argv));
        return app.run();
    }
}
