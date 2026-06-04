#include "App.hpp"
#include "TextUtils.hpp"

#include <algorithm>
#include <locale.h>
#include <ncurses.h>
#include <utility>

App::App(std::string repoPath) : git_(std::move(repoPath)) {}

int App::run() {
    if (!git_.isRepo()) {
        fprintf(stderr, "gitcku: not a git repository: %s\n", git_.repoPath().c_str());
        return 2;
    }

    setupCurses();
    refreshAll();
    bool active = true;
    while (active) {
        draw();
        active = handleKey(getch());
    }

    endwin();
    return 0;
}

void App::setupCurses() {
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
    init_pair(6, COLOR_MAGENTA, -1);
}

void App::refreshAll() {
    branch_ = git_.currentBranch();
    status_ = git_.status();
    diff_ = git_.diff();
    log_ = git_.log();
    branches_ = git_.branches();
    stashes_ = git_.stashes();
    remotes_ = git_.remotes();
    clampSelection();
}

void App::switchPanel(Panel panel) {
    panel_ = panel;
    selected_ = 0;
    scroll_ = 0;
    if (panel != Panel::Diff) detail_.clear();
}

void App::draw() {
    erase();
    int rows = 0;
    int cols = 0;
    getmaxyx(stdscr, rows, cols);
    drawHeader(cols);
    drawTabs(cols);
    drawContent(rows, cols);
    drawFooter(rows, cols);
    refresh();
}

void App::drawHeader(int cols) {
    attron(COLOR_PAIR(1) | A_BOLD);
    mvprintw(0, 0, "gitcku");
    attroff(COLOR_PAIR(1) | A_BOLD);
    mvprintw(0, 8, "%s", shorten(git_.repoPath(), cols - 9).c_str());
    attron(COLOR_PAIR(3));
    mvprintw(1, 0, "branch: %s", shorten(branch_, cols - 10).c_str());
    attroff(COLOR_PAIR(3));
    std::string right = "[" + panelName() + "]";
    mvprintw(1, std::max(0, cols - static_cast<int>(right.size()) - 1), "%s", right.c_str());
    if (!filter_.empty()) {
        attron(COLOR_PAIR(6));
        mvprintw(2, 0, "filter: %s", shorten(filter_, cols - 9).c_str());
        attroff(COLOR_PAIR(6));
    }
}

void App::drawTabs(int cols) {
    std::string tabs = " 1 Status   2 Diff   3 Log   4 Branches   5 Stash   6 Remotes   ? Help ";
    attron(A_REVERSE);
    mvprintw(3, 0, "%-*s", cols, tabs.substr(0, cols).c_str());
    attroff(A_REVERSE);
}

void App::drawContent(int rows, int cols) {
    std::vector<ViewLine> lines = currentLines();
    int top = 5;
    int bottom = rows - 3;
    int height = std::max(0, bottom - top + 1);
    clampScroll(height, static_cast<int>(lines.size()));

    for (int i = 0; i < height; i++) {
        int lineIndex = scroll_ + i;
        if (lineIndex >= static_cast<int>(lines.size())) break;
        bool highlighted = lines[lineIndex].selectable && lineIndex == selected_;
        if (highlighted) attron(COLOR_PAIR(5));
        mvprintw(top + i, 0, "%-*s", cols, shorten(lines[lineIndex].text, cols - 1).c_str());
        if (highlighted) attroff(COLOR_PAIR(5));
    }
}

void App::drawFooter(int rows, int cols) {
    attron(A_REVERSE);
    std::string keys = " q quit  r refresh  / filter  enter details  space stage  c commit  n branch  m merge  f fetch  P pull  p push ";
    mvprintw(rows - 2, 0, "%-*s", cols, keys.substr(0, cols).c_str());
    attroff(A_REVERSE);
    move(rows - 1, 0);
    clrtoeol();
    if (!message_.empty()) {
        attron(COLOR_PAIR(2));
        mvprintw(rows - 1, 0, "%s", shorten(message_, cols - 1).c_str());
        attroff(COLOR_PAIR(2));
    }
}

std::vector<ViewLine> App::currentLines() const {
    std::vector<ViewLine> lines;
    auto add = [&](const std::string &text, int index = -1, bool selectable = false) {
        if (containsCaseInsensitive(text, filter_)) lines.push_back({text, index, selectable});
    };

    if (panel_ == Panel::Status) {
        for (size_t i = 0; i < status_.size(); i++) {
            const StatusItem &item = status_[i];
            std::string marker = item.staged ? "[staged]   " : "[worktree] ";
            add(marker + item.indexCode + item.worktreeCode + " " + item.path, static_cast<int>(i), true);
        }
        if (lines.empty()) lines.push_back({status_.empty() ? "Working tree clean." : "No matching files.", -1, false});
    } else if (panel_ == Panel::Diff) {
        const std::vector<std::string> &source = detail_.empty() ? diff_ : detail_;
        for (size_t i = 0; i < source.size(); i++) add(source[i], static_cast<int>(i), false);
    } else if (panel_ == Panel::Log) {
        for (size_t i = 0; i < log_.size(); i++) add(log_[i], static_cast<int>(i), true);
    } else if (panel_ == Panel::Branches) {
        for (size_t i = 0; i < branches_.size(); i++) add(branches_[i].display, static_cast<int>(i), branches_[i].checkable);
        if (lines.empty()) lines.push_back({"No matching branches.", -1, false});
    } else if (panel_ == Panel::Stashes) {
        for (size_t i = 0; i < stashes_.size(); i++) add(stashes_[i].ref + " " + stashes_[i].message, static_cast<int>(i), true);
        if (lines.empty()) lines.push_back({stashes_.empty() ? "No stashes." : "No matching stashes.", -1, false});
    } else if (panel_ == Panel::Remotes) {
        for (size_t i = 0; i < remotes_.size(); i++) add(remotes_[i], static_cast<int>(i), false);
    } else {
        std::vector<std::string> help = {
            "Navigation: j/k or arrows, g top, G bottom, 1-6 switch panels, ? help",
            "Inspect: enter opens selected file diff, commit show, or stash patch in the Diff panel",
            "Status: space stage/unstage file, a stage all, u unstage all, D discard selected worktree change",
            "Commit: c commits staged changes with a prompt",
            "Branches: b checkout selected, n create branch, m merge selected into current branch",
            "Stash: s stash push, A apply selected stash, S pop selected stash, x drop selected stash",
            "Network: f fetch --all --prune, P pull --ff-only, p push",
            "Filtering: / set filter, esc clears filter"
        };
        for (const std::string &line : help) lines.push_back({line, -1, false});
    }
    return lines;
}

std::string App::panelName() const {
    switch (panel_) {
        case Panel::Status: return "Status";
        case Panel::Diff: return detail_.empty() ? "Diff" : "Detail";
        case Panel::Log: return "Log";
        case Panel::Branches: return "Branches";
        case Panel::Stashes: return "Stashes";
        case Panel::Remotes: return "Remotes";
        case Panel::Help: return "Help";
    }
    return "";
}

bool App::handleKey(int ch) {
    switch (ch) {
        case 'q': return false;
        case '1': switchPanel(Panel::Status); break;
        case '2': switchPanel(Panel::Diff); break;
        case '3': switchPanel(Panel::Log); break;
        case '4': switchPanel(Panel::Branches); break;
        case '5': switchPanel(Panel::Stashes); break;
        case '6': switchPanel(Panel::Remotes); break;
        case '?': switchPanel(Panel::Help); break;
        case 27: filter_.clear(); selected_ = scroll_ = 0; break;
        case 'j':
        case KEY_DOWN: moveSelection(1); break;
        case 'k':
        case KEY_UP: moveSelection(-1); break;
        case 'g': selected_ = 0; scroll_ = 0; break;
        case 'G': selected_ = std::max(0, lineCount() - 1); break;
        case 'r': refreshAll(); setMessage("Refreshed."); break;
        case '/': filter_ = prompt("Filter: "); selected_ = scroll_ = 0; break;
        case '\n':
        case KEY_ENTER: openDetail(); break;
        case ' ': toggleStage(); break;
        case 'a': runAndRefresh({"add", "--all"}, "Staged all changes."); break;
        case 'u': runAndRefresh({"reset", "--"}, "Unstaged all changes."); break;
        case 'D': discardSelected(); break;
        case 'c': commitPrompt(); break;
        case 'b': checkoutSelectedBranch(); break;
        case 'n': createBranchPrompt(); break;
        case 'm': mergeSelectedBranch(); break;
        case 's': stashPushPrompt(); break;
        case 'A': stashApply(false); break;
        case 'S': stashApply(true); break;
        case 'x': stashDrop(); break;
        case 'f': runAndRefresh({"fetch", "--all", "--prune"}, "Fetch finished."); break;
        case 'p': runAndRefresh({"push"}, "Push finished."); break;
        case 'P': runAndRefresh({"pull", "--ff-only"}, "Pull finished."); break;
        default: break;
    }
    return true;
}

int App::lineCount() const {
    return std::max(1, static_cast<int>(currentLines().size()));
}

void App::moveSelection(int delta) {
    selected_ = std::clamp(selected_ + delta, 0, lineCount() - 1);
}

void App::clampSelection() {
    selected_ = std::clamp(selected_, 0, lineCount() - 1);
}

void App::clampScroll(int height, int total) {
    if (selected_ < scroll_) scroll_ = selected_;
    if (selected_ >= scroll_ + height) scroll_ = selected_ - height + 1;
    int maxScroll = std::max(0, total - height);
    scroll_ = std::clamp(scroll_, 0, maxScroll);
}

void App::setMessage(const std::string &message) {
    message_ = message;
}

std::string App::prompt(const std::string &label) {
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

bool App::confirm(const std::string &label, const std::string &expected) {
    return prompt(label + " Type '" + expected + "': ") == expected;
}

void App::runAndRefresh(const std::vector<std::string> &args, const std::string &success) {
    GitResult result = git_.run(args);
    refreshAll();
    setMessage(result.status == 0 ? success : trim(result.err.empty() ? result.out : result.err));
}

void App::toggleStage() {
    if (panel_ != Panel::Status) return;
    std::vector<ViewLine> lines = currentLines();
    if (selected_ >= static_cast<int>(lines.size()) || lines[selected_].sourceIndex < 0) return;
    const StatusItem &item = status_[lines[selected_].sourceIndex];
    runAndRefresh(item.staged ? std::vector<std::string>{"reset", "--", item.path}
                              : std::vector<std::string>{"add", "--", item.path},
                  (item.staged ? "Unstaged " : "Staged ") + item.path);
}

void App::commitPrompt() {
    std::string message = prompt("Commit message: ");
    if (message.empty()) {
        setMessage("Commit cancelled.");
        return;
    }
    runAndRefresh({"commit", "-m", message}, "Commit created.");
}

void App::checkoutSelectedBranch() {
    if (panel_ != Panel::Branches) return;
    std::vector<ViewLine> lines = currentLines();
    if (selected_ >= static_cast<int>(lines.size()) || lines[selected_].sourceIndex < 0) return;
    const BranchItem &branch = branches_[lines[selected_].sourceIndex];
    if (!branch.checkable) return;
    runAndRefresh({"checkout", branch.name}, "Checked out " + branch.name);
}

void App::createBranchPrompt() {
    std::string name = prompt("New branch name: ");
    if (name.empty()) {
        setMessage("Branch creation cancelled.");
        return;
    }
    runAndRefresh({"checkout", "-b", name}, "Created and checked out " + name);
}

void App::mergeSelectedBranch() {
    if (panel_ != Panel::Branches) return;
    std::vector<ViewLine> lines = currentLines();
    if (selected_ >= static_cast<int>(lines.size()) || lines[selected_].sourceIndex < 0) return;
    const BranchItem &branch = branches_[lines[selected_].sourceIndex];
    if (!branch.checkable || branch.current) return;
    runAndRefresh({"merge", "--no-edit", branch.name}, "Merged " + branch.name);
}

void App::stashPushPrompt() {
    std::string message = prompt("Stash message: ");
    if (message.empty()) message = "gitcku stash";
    runAndRefresh({"stash", "push", "-u", "-m", message}, "Created stash.");
}

void App::stashApply(bool pop) {
    if (panel_ != Panel::Stashes) return;
    std::vector<ViewLine> lines = currentLines();
    if (selected_ >= static_cast<int>(lines.size()) || lines[selected_].sourceIndex < 0) return;
    const StashItem &stash = stashes_[lines[selected_].sourceIndex];
    runAndRefresh({"stash", pop ? "pop" : "apply", stash.ref}, (pop ? "Popped " : "Applied ") + stash.ref);
}

void App::stashDrop() {
    if (panel_ != Panel::Stashes) return;
    std::vector<ViewLine> lines = currentLines();
    if (selected_ >= static_cast<int>(lines.size()) || lines[selected_].sourceIndex < 0) return;
    const StashItem &stash = stashes_[lines[selected_].sourceIndex];
    if (!confirm("Drop " + stash.ref + "?", "drop")) {
        setMessage("Drop cancelled.");
        return;
    }
    runAndRefresh({"stash", "drop", stash.ref}, "Dropped " + stash.ref);
}

void App::discardSelected() {
    if (panel_ != Panel::Status) return;
    std::vector<ViewLine> lines = currentLines();
    if (selected_ >= static_cast<int>(lines.size()) || lines[selected_].sourceIndex < 0) return;
    const StatusItem &item = status_[lines[selected_].sourceIndex];
    if (item.worktreeCode == " " || item.worktreeCode.empty()) {
        setMessage("Selected file has no worktree change to discard.");
        return;
    }
    if (!confirm("Discard worktree changes in " + item.path + "?", "discard")) {
        setMessage("Discard cancelled.");
        return;
    }
    if (item.indexCode == "?" && item.worktreeCode == "?") {
        runAndRefresh({"clean", "-f", "--", item.path}, "Removed untracked " + item.path);
    } else {
        runAndRefresh({"checkout", "--", item.path}, "Discarded " + item.path);
    }
}

void App::openDetail() {
    std::vector<ViewLine> lines = currentLines();
    if (selected_ >= static_cast<int>(lines.size()) || lines[selected_].sourceIndex < 0) return;

    if (panel_ == Panel::Status) {
        detail_ = git_.fileDiff(status_[lines[selected_].sourceIndex]);
        switchPanel(Panel::Diff);
    } else if (panel_ == Panel::Log) {
        detail_ = git_.showCommit(log_[lines[selected_].sourceIndex]);
        switchPanel(Panel::Diff);
    } else if (panel_ == Panel::Stashes) {
        detail_ = git_.showStash(stashes_[lines[selected_].sourceIndex]);
        switchPanel(Panel::Diff);
    }
}
