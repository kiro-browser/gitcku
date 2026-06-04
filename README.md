# gitcku

A native Objective-C++ terminal UI git client for macOS. It uses Foundation for process execution, ncurses for the interface, and the system `git` binary for repository operations.

## Interface

- Framed terminal layout with a persistent repository header
- Color-coded status and diff rows
- Context-aware command strip for each panel
- Split-pane previews on wide terminals
- Centered modal prompts for commit messages, filters, branch names, and confirmations
- Cached previews for selected files, commits, branches, and stashes
- File index and repository grep panels for IDE-like navigation

## Build

```sh
make
```

## Run

From any git repository:

```sh
./build/gitcku
```

Or point it at a repository:

```sh
./build/gitcku /path/to/repo
```

## Views

- `1`: Status
- `2`: Diff / detail
- `3`: Log
- `4`: Branches
- `5`: Stashes
- `6`: Remotes
- `7`: Files
- `8`: Search
- `?`: Help

## Keys

- `j` / `Down`: Move down
- `k` / `Up`: Move up
- `g`: Top
- `G`: Bottom
- `/`: Filter the current view
- `Esc`: Clear filter
- `Enter`: Open selected file, commit, or stash details in the diff panel
- `:`: Command palette
- `Space`: Stage or unstage selected file
- `a`: Stage all
- `u`: Unstage all
- `D`: Discard selected worktree change, after confirmation
- `c`: Commit staged changes
- `C`: Amend previous commit
- `b`: Checkout selected branch
- `n`: Create and checkout a new branch
- `N`: Create and checkout a new branch from the selected commit
- `m`: Merge selected branch into the current branch
- `R`: Rebase the current branch onto the selected branch, after confirmation
- `y`: Cherry-pick selected commit, after confirmation
- `s`: Stash changes, including untracked files
- `A`: Apply selected stash
- `S`: Pop selected stash
- `x`: Drop selected stash, after confirmation
- `f`: Fetch all remotes and prune stale references
- `F`: Search repository content with `git grep`
- `B`: Blame selected file
- `o`: Open selected file in `$EDITOR`
- `p`: Push
- `P`: Pull
- `r`: Refresh
- `q`: Quit

Git commands are run with argument arrays, not shell strings.

## Layout

- `src/main.mm`: entry point
- `src/App.mm`: ncurses application controller and key handling
- `src/Git.mm`: Objective-C++ `NSTask` git adapter and parsers
- `src/Models.hpp`: shared data models
- `src/TextUtils.cpp`: small text helpers
