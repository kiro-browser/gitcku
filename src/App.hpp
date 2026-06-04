#pragma once

#include "Git.hpp"
#include "Models.hpp"

#include <string>
#include <vector>

class App {
public:
    explicit App(std::string repoPath);
    int run();

private:
    Git git_;
    Panel panel_ = Panel::Status;
    std::vector<StatusItem> status_;
    std::vector<std::string> diff_;
    std::vector<std::string> log_;
    std::vector<BranchItem> branches_;
    std::vector<StashItem> stashes_;
    std::vector<std::string> remotes_;
    std::vector<std::string> detail_;
    std::string branch_;
    std::string message_;
    std::string filter_;
    int selected_ = 0;
    int scroll_ = 0;

    void setupCurses();
    void refreshAll();
    void switchPanel(Panel panel);
    void draw();
    void drawHeader(int cols);
    void drawTabs(int cols);
    void drawContent(int rows, int cols);
    void drawFooter(int rows, int cols);
    std::vector<ViewLine> currentLines() const;
    std::string panelName() const;
    bool handleKey(int ch);
    int lineCount() const;
    void moveSelection(int delta);
    void clampSelection();
    void clampScroll(int height, int total);
    void setMessage(const std::string &message);
    std::string prompt(const std::string &label);
    bool confirm(const std::string &label, const std::string &expected);
    void runAndRefresh(const std::vector<std::string> &args, const std::string &success);
    void toggleStage();
    void commitPrompt();
    void checkoutSelectedBranch();
    void createBranchPrompt();
    void mergeSelectedBranch();
    void stashPushPrompt();
    void stashApply(bool pop);
    void stashDrop();
    void discardSelected();
    void openDetail();
};
