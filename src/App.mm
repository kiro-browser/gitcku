#include "App.hpp"
#include "TextUtils.hpp"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <locale.h>
#include <ncurses.h>
#include <sstream>
#include <sys/wait.h>
#include <unistd.h>
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
    init_pair(7, COLOR_BLUE, -1);
    init_pair(8, COLOR_WHITE, COLOR_BLUE);
    init_pair(9, COLOR_BLACK, COLOR_GREEN);
}

void App::refreshAll() {
    branch_ = git_.currentBranch();
    status_ = git_.status();
    diff_ = git_.diff();
    log_ = git_.log();
    branches_ = git_.branches();
    stashes_ = git_.stashes();
    remotes_ = git_.remotes();
    files_ = git_.files();
    if (!lastSearch_.empty()) search_ = git_.grep(lastSearch_);
    clampSelection();
}

void App::switchPanel(Panel panel) {
    panel_ = panel;
    selected_ = 0;
    scroll_ = 0;
    if (panel != Panel::Diff) detail_.clear();
    preview_.clear();
    previewSelection_ = -1;
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
    attron(COLOR_PAIR(8) | A_BOLD);
    mvprintw(0, 0, "%-*s", cols, "");
    mvprintw(0, 2, " gitcku ");
    attroff(COLOR_PAIR(8) | A_BOLD);

    attron(A_BOLD);
    mvprintw(1, 2, "%s", shorten(git_.repoPath(), std::max(10, cols / 2)).c_str());
    attroff(A_BOLD);
    attron(COLOR_PAIR(3) | A_BOLD);
    mvprintw(1, std::max(2, cols / 2), "branch %s", shorten(branch_, std::max(8, cols / 4)).c_str());
    attroff(COLOR_PAIR(3) | A_BOLD);
    attron(COLOR_PAIR(2));
    mvprintw(1, std::max(2, cols - static_cast<int>(statusSummary().size()) - 2), "%s", statusSummary().c_str());
    attroff(COLOR_PAIR(2));

    if (!filter_.empty()) {
        attron(COLOR_PAIR(6));
        mvprintw(2, 2, "filter: %s", shorten(filter_, cols - 11).c_str());
        attroff(COLOR_PAIR(6));
    } else {
        attron(COLOR_PAIR(7));
        mvprintw(2, 2, "%s", shorten(commandHint(), cols - 4).c_str());
        attroff(COLOR_PAIR(7));
    }
}

void App::drawTabs(int cols) {
    struct Tab { Panel panel; const char *label; };
    std::vector<Tab> tabs = {
        {Panel::Status, "1 Status"}, {Panel::Diff, "2 Diff"}, {Panel::Log, "3 Log"},
        {Panel::Branches, "4 Branches"}, {Panel::Stashes, "5 Stash"},
        {Panel::Remotes, "6 Remotes"}, {Panel::Files, "7 Files"},
        {Panel::Search, "8 Search"}, {Panel::Help, "? Help"}
    };
    mvhline(3, 0, ACS_HLINE, cols);
    int x = 2;
    for (const Tab &tab : tabs) {
        std::string label = std::string(" ") + tab.label + " ";
        bool active = tab.panel == panel_;
        if (active) attron(COLOR_PAIR(9) | A_BOLD);
        else attron(COLOR_PAIR(7));
        mvprintw(3, x, "%s", label.c_str());
        if (active) attroff(COLOR_PAIR(9) | A_BOLD);
        else attroff(COLOR_PAIR(7));
        x += static_cast<int>(label.size()) + 1;
        if (x >= cols - 8) break;
    }
}

void App::drawContent(int rows, int cols) {
    std::vector<ViewLine> lines = currentLines();
    int top = 5;
    int bottom = rows - 4;
    int height = std::max(0, bottom - top + 1);

    bool split = cols >= 104 && rows >= 22 &&
        (panel_ == Panel::Status || panel_ == Panel::Log || panel_ == Panel::Branches ||
         panel_ == Panel::Stashes || panel_ == Panel::Files);
    if (split) {
        int leftW = std::max(42, cols * 45 / 100);
        int rightW = cols - leftW - 3;
        drawPanelFrame(top - 1, 1, height + 2, leftW, panelName());
        drawPanelFrame(top - 1, leftW + 2, height + 2, rightW, "Preview");
        drawList(top, 2, height, leftW - 2, lines);
        drawPreview(top, leftW + 3, height, rightW - 2);
    } else {
        drawPanelFrame(top - 1, 1, height + 2, cols - 2, panelName());
        drawList(top, 2, height, cols - 4, lines);
    }
}

void App::drawPanelFrame(int y, int x, int h, int w, const std::string &title) {
    if (h < 3 || w < 8) return;
    attron(COLOR_PAIR(7));
    mvaddch(y, x, ACS_ULCORNER);
    mvhline(y, x + 1, ACS_HLINE, w - 2);
    mvaddch(y, x + w - 1, ACS_URCORNER);
    mvvline(y + 1, x, ACS_VLINE, h - 2);
    mvvline(y + 1, x + w - 1, ACS_VLINE, h - 2);
    mvaddch(y + h - 1, x, ACS_LLCORNER);
    mvhline(y + h - 1, x + 1, ACS_HLINE, w - 2);
    mvaddch(y + h - 1, x + w - 1, ACS_LRCORNER);
    attroff(COLOR_PAIR(7));
    attron(A_BOLD);
    mvprintw(y, x + 2, " %s ", shorten(title, w - 6).c_str());
    attroff(A_BOLD);
}

void App::drawList(int y, int x, int h, int w, const std::vector<ViewLine> &lines) {
    clampScroll(h, static_cast<int>(lines.size()));
    for (int i = 0; i < h; i++) {
        int lineIndex = scroll_ + i;
        mvprintw(y + i, x, "%-*s", w, "");
        if (lineIndex >= static_cast<int>(lines.size())) continue;
        bool highlighted = lines[lineIndex].selectable && lineIndex == selected_;
        int pair = colorForLine(lines[lineIndex].text, highlighted);
        attron(COLOR_PAIR(pair) | (highlighted ? A_BOLD : 0));
        std::string prefix = highlighted ? "> " : "  ";
        mvprintw(y + i, x, "%-*s", w, shorten(prefix + lines[lineIndex].text, w).c_str());
        attroff(COLOR_PAIR(pair) | (highlighted ? A_BOLD : 0));
    }
}

void App::drawPreview(int y, int x, int h, int w) {
    std::vector<std::string> lines = previewLines();
    for (int i = 0; i < h; i++) {
        mvprintw(y + i, x, "%-*s", w, "");
        if (i >= static_cast<int>(lines.size())) continue;
        int pair = colorForLine(lines[i], false);
        attron(COLOR_PAIR(pair));
        mvprintw(y + i, x, "%-*s", w, shorten(lines[i], w).c_str());
        attroff(COLOR_PAIR(pair));
    }
}

void App::drawFooter(int rows, int cols) {
    attron(COLOR_PAIR(8));
    mvprintw(rows - 3, 0, "%-*s", cols, commandHint().substr(0, cols).c_str());
    attroff(COLOR_PAIR(8));
    attron(A_REVERSE);
    std::string keys = " q quit  r refresh  / filter  enter details  arrows/jk move  1-6 panels ";
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

std::vector<std::string> App::previewLines() {
    if (previewPanel_ == panel_ && previewSelection_ == selected_ && !preview_.empty()) return preview_;
    previewPanel_ = panel_;
    previewSelection_ = selected_;
    preview_.clear();

    std::vector<ViewLine> lines = currentLines();
    if (selected_ >= static_cast<int>(lines.size()) || lines[selected_].sourceIndex < 0) {
        preview_ = {"No selection."};
        return preview_;
    }

    if (panel_ == Panel::Status) {
        const StatusItem &item = status_[lines[selected_].sourceIndex];
        preview_.push_back(item.path);
        preview_.push_back(item.staged ? "Index change" : "Worktree change");
        preview_.push_back("");
        std::vector<std::string> diff = git_.fileDiff(item);
        preview_.insert(preview_.end(), diff.begin(), diff.end());
    } else if (panel_ == Panel::Log) {
        preview_ = git_.showCommit(log_[lines[selected_].sourceIndex]);
    } else if (panel_ == Panel::Branches) {
        const BranchItem &branch = branches_[lines[selected_].sourceIndex];
        preview_ = {
            branch.name,
            branch.current ? "Current branch" : (branch.remote ? "Remote branch" : "Local branch"),
            "",
            "b checkout",
            "m merge into " + branch_,
            "n create branch"
        };
    } else if (panel_ == Panel::Stashes) {
        preview_ = git_.showStash(stashes_[lines[selected_].sourceIndex]);
    } else if (panel_ == Panel::Files) {
        const FileItem &file = files_[lines[selected_].sourceIndex];
        preview_.push_back(file.path);
        preview_.push_back(file.tracked ? "Tracked file" : "Untracked file");
        preview_.push_back("");
        preview_.push_back("o open in $EDITOR");
        preview_.push_back("B blame");
        preview_.push_back("enter inspect current diff");
    }
    if (preview_.empty()) preview_.push_back("No preview.");
    return preview_;
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
    } else if (panel_ == Panel::Files) {
        for (size_t i = 0; i < files_.size(); i++) {
            add(std::string(files_[i].tracked ? "[tracked]   " : "[untracked] ") + files_[i].path, static_cast<int>(i), true);
        }
        if (lines.empty()) lines.push_back({files_.empty() ? "No files." : "No matching files.", -1, false});
    } else if (panel_ == Panel::Search) {
        if (lastSearch_.empty()) {
            lines.push_back({"Press F to search repository content.", -1, false});
        } else {
            for (size_t i = 0; i < search_.size(); i++) add(search_[i], static_cast<int>(i), false);
        }
    } else {
        std::vector<std::string> help = {
            "Navigation: j/k or arrows, g top, G bottom, 1-8 switch panels, ? help",
            "Inspect: enter opens selected file diff, commit show, or stash patch in the Diff panel",
            "Workspace: 7 file index, 8 repository grep, o open selected file in $EDITOR, B blame selected file",
            "Status: space stage/unstage file, a stage all, u unstage all, D discard selected worktree change",
            "Commit: c commits staged changes, C amends the previous commit",
            "History: y cherry-pick selected commit, N create branch from selected commit",
            "Branches: b checkout selected, n create branch, m merge selected, R rebase current branch onto selected",
            "Stash: s stash push, A apply selected stash, S pop selected stash, x drop selected stash",
            "Network: f fetch --all --prune, P pull --ff-only, p push",
            "Filtering: / set filter, esc clears filter, : opens a command palette"
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
        case Panel::Files: return "Files";
        case Panel::Search: return lastSearch_.empty() ? "Search" : "Search: " + lastSearch_;
        case Panel::Help: return "Help";
    }
    return "";
}

std::string App::commandHint() const {
    if (panel_ == Panel::Status) return "space stage/unstage  enter inspect  a stage all  u unstage all  D discard  c commit";
    if (panel_ == Panel::Diff) return "r refresh  1 status  3 log  o open file from file/status panels";
    if (panel_ == Panel::Log) return "enter show commit  y cherry-pick  N branch from commit  / filter";
    if (panel_ == Panel::Branches) return "b checkout  n new branch  m merge selected  R rebase onto selected  f fetch";
    if (panel_ == Panel::Stashes) return "s stash push  enter inspect  A apply  S pop  x drop";
    if (panel_ == Panel::Remotes) return "f fetch --all --prune  P pull --ff-only  p push";
    if (panel_ == Panel::Files) return "enter inspect diff  o open in $EDITOR  B blame  / filter";
    if (panel_ == Panel::Search) return "F grep repository  / filter results  7 files";
    return "q quit  r refresh  : commands  / filter  esc clear filter  1-8 switch views";
}

std::string App::statusSummary() const {
    int staged = 0;
    int changed = 0;
    int untracked = 0;
    for (const StatusItem &item : status_) {
        if (item.staged) staged++;
        if (item.worktreeCode != " " && item.worktreeCode != "?") changed++;
        if (item.indexCode == "?" && item.worktreeCode == "?") untracked++;
    }
    char buffer[96] = {0};
    std::snprintf(buffer, sizeof(buffer), "%d staged  %d changed  %d untracked", staged, changed, untracked);
    return buffer;
}

int App::colorForLine(const std::string &line, bool highlighted) const {
    if (highlighted) return 5;
    if (line.rfind("+", 0) == 0 && line.rfind("+++", 0) != 0) return 2;
    if (line.rfind("-", 0) == 0 && line.rfind("---", 0) != 0) return 4;
    if (line.find("[staged]") != std::string::npos) return 2;
    if (line.find("[tracked]") != std::string::npos) return 1;
    if (line.find("[untracked]") != std::string::npos) return 4;
    if (line.find("[worktree] ??") != std::string::npos) return 4;
    if (line.find("[worktree]") != std::string::npos) return 3;
    if (line.rfind("commit ", 0) == 0 || line.find("* ") != std::string::npos) return 1;
    if (line.find("@@") != std::string::npos) return 6;
    return 0;
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
        case '7': switchPanel(Panel::Files); break;
        case '8': switchPanel(Panel::Search); break;
        case '?': switchPanel(Panel::Help); break;
        case ':': runCommandPalette(); break;
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
        case 'C': amendCommitPrompt(); break;
        case 'b': checkoutSelectedBranch(); break;
        case 'n': createBranchPrompt(); break;
        case 'N': createBranchFromCommitPrompt(); break;
        case 'm': mergeSelectedBranch(); break;
        case 'R': rebaseOntoSelectedBranch(); break;
        case 'y': cherryPickSelectedCommit(); break;
        case 's': stashPushPrompt(); break;
        case 'A': stashApply(false); break;
        case 'S': stashApply(true); break;
        case 'x': stashDrop(); break;
        case 'f': runAndRefresh({"fetch", "--all", "--prune"}, "Fetch finished."); break;
        case 'F': searchPrompt(); break;
        case 'B': blameSelected(); break;
        case 'o': openSelectedInEditor(); break;
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
    int width = std::max(20, std::min(cols - 4, std::max(48, static_cast<int>(label.size()) + 34)));
    int height = 5;
    int y = std::max(1, rows / 2 - height / 2);
    int x = std::max(1, cols / 2 - width / 2);
    drawPanelFrame(y, x, height, width, "Input");
    attron(A_BOLD);
    mvprintw(y + 1, x + 2, "%s", shorten(label, width - 4).c_str());
    attroff(A_BOLD);
    mvhline(y + 3, x + 2, ACS_HLINE, width - 4);
    move(y + 2, x + 2);
    clrtoeol();
    refresh();
    echo();
    curs_set(1);
    char buffer[1024] = {0};
    move(y + 2, x + 2);
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

void App::runCommandPalette() {
    std::string command = prompt("Command: ");
    if (command == "status") switchPanel(Panel::Status);
    else if (command == "diff") switchPanel(Panel::Diff);
    else if (command == "log") switchPanel(Panel::Log);
    else if (command == "branches") switchPanel(Panel::Branches);
    else if (command == "stash") switchPanel(Panel::Stashes);
    else if (command == "remotes") switchPanel(Panel::Remotes);
    else if (command == "files") switchPanel(Panel::Files);
    else if (command == "search") searchPrompt();
    else if (command == "blame") blameSelected();
    else if (command == "open") openSelectedInEditor();
    else if (command == "amend") amendCommitPrompt();
    else if (command == "refresh") { refreshAll(); setMessage("Refreshed."); }
    else if (command.empty()) setMessage("Command cancelled.");
    else setMessage("Unknown command: " + command);
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

void App::amendCommitPrompt() {
    std::string message = prompt("Amend message (blank reuses previous): ");
    if (message.empty()) {
        runAndRefresh({"commit", "--amend", "--no-edit"}, "Amended previous commit.");
    } else {
        runAndRefresh({"commit", "--amend", "-m", message}, "Amended previous commit.");
    }
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

void App::createBranchFromCommitPrompt() {
    std::string hash = selectedCommitHash();
    if (hash.empty()) {
        setMessage("Select a commit first.");
        return;
    }
    std::string name = prompt("New branch from " + hash + ": ");
    if (name.empty()) {
        setMessage("Branch creation cancelled.");
        return;
    }
    runAndRefresh({"checkout", "-b", name, hash}, "Created " + name + " at " + hash);
}

void App::mergeSelectedBranch() {
    if (panel_ != Panel::Branches) return;
    std::vector<ViewLine> lines = currentLines();
    if (selected_ >= static_cast<int>(lines.size()) || lines[selected_].sourceIndex < 0) return;
    const BranchItem &branch = branches_[lines[selected_].sourceIndex];
    if (!branch.checkable || branch.current) return;
    runAndRefresh({"merge", "--no-edit", branch.name}, "Merged " + branch.name);
}

void App::rebaseOntoSelectedBranch() {
    if (panel_ != Panel::Branches) return;
    std::vector<ViewLine> lines = currentLines();
    if (selected_ >= static_cast<int>(lines.size()) || lines[selected_].sourceIndex < 0) return;
    const BranchItem &branch = branches_[lines[selected_].sourceIndex];
    if (!branch.checkable || branch.current) return;
    if (!confirm("Rebase " + branch_ + " onto " + branch.name + "?", "rebase")) {
        setMessage("Rebase cancelled.");
        return;
    }
    runAndRefresh({"rebase", branch.name}, "Rebased onto " + branch.name);
}

void App::cherryPickSelectedCommit() {
    std::string hash = selectedCommitHash();
    if (hash.empty()) {
        setMessage("Select a commit first.");
        return;
    }
    if (!confirm("Cherry-pick " + hash + "?", "pick")) {
        setMessage("Cherry-pick cancelled.");
        return;
    }
    runAndRefresh({"cherry-pick", hash}, "Cherry-picked " + hash);
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

void App::searchPrompt() {
    std::string term = prompt("Repository grep: ");
    if (term.empty()) {
        setMessage("Search cancelled.");
        return;
    }
    lastSearch_ = term;
    search_ = git_.grep(term);
    switchPanel(Panel::Search);
    setMessage("Search complete: " + term);
}

std::string App::selectedFilePath() const {
    std::vector<ViewLine> lines = currentLines();
    if (selected_ >= static_cast<int>(lines.size()) || lines[selected_].sourceIndex < 0) return "";
    if (panel_ == Panel::Status) return status_[lines[selected_].sourceIndex].path;
    if (panel_ == Panel::Files) return files_[lines[selected_].sourceIndex].path;
    return "";
}

std::string App::selectedCommitHash() const {
    std::vector<ViewLine> lines = currentLines();
    if (panel_ != Panel::Log || selected_ >= static_cast<int>(lines.size()) || lines[selected_].sourceIndex < 0) return "";
    return git_.extractCommitHash(log_[lines[selected_].sourceIndex]);
}

void App::blameSelected() {
    std::string path = selectedFilePath();
    if (path.empty()) {
        setMessage("Select a file first.");
        return;
    }
    detail_ = git_.blame(path);
    switchPanel(Panel::Diff);
    setMessage("Blame: " + path);
}

void App::openSelectedInEditor() {
    std::string path = selectedFilePath();
    if (path.empty()) {
        setMessage("Select a file first.");
        return;
    }
    std::string root = git_.rootPath();
    std::string fullPath = (root.empty() ? git_.repoPath() : root) + "/" + path;
    const char *envEditor = std::getenv("EDITOR");
    std::string editor = (envEditor && *envEditor) ? envEditor : "vi";
    size_t space = editor.find(' ');
    if (space != std::string::npos) editor = editor.substr(0, space);

    def_prog_mode();
    endwin();
    pid_t pid = fork();
    if (pid == 0) {
        execlp(editor.c_str(), editor.c_str(), fullPath.c_str(), static_cast<char *>(nullptr));
        _exit(127);
    }
    int status = 0;
    if (pid > 0) waitpid(pid, &status, 0);
    reset_prog_mode();
    refresh();
    refreshAll();
    setMessage("Returned from editor: " + path);
}

void App::openDetail() {
    std::vector<ViewLine> lines = currentLines();
    if (selected_ >= static_cast<int>(lines.size()) || lines[selected_].sourceIndex < 0) return;

    if (panel_ == Panel::Status) {
        detail_ = git_.fileDiff(status_[lines[selected_].sourceIndex]);
        switchPanel(Panel::Diff);
    } else if (panel_ == Panel::Files) {
        std::string path = files_[lines[selected_].sourceIndex].path;
        GitResult result = git_.run({"diff", "--", path});
        detail_ = splitLines(result.out.empty() ? result.err : result.out);
        if (detail_.empty()) detail_ = {"No worktree diff for " + path + ".", "Use o to open it or B to inspect blame."};
        switchPanel(Panel::Diff);
    } else if (panel_ == Panel::Log) {
        detail_ = git_.showCommit(log_[lines[selected_].sourceIndex]);
        switchPanel(Panel::Diff);
    } else if (panel_ == Panel::Stashes) {
        detail_ = git_.showStash(stashes_[lines[selected_].sourceIndex]);
        switchPanel(Panel::Diff);
    }
}
