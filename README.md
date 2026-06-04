# gitcku

A native Objective-C++ terminal UI git client for macOS. It uses Foundation for process execution, ncurses for the interface, and the system `git` binary for repository operations.

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
- `?`: Help

## Keys

- `j` / `Down`: Move down
- `k` / `Up`: Move up
- `g`: Top
- `G`: Bottom
- `/`: Filter the current view
- `Esc`: Clear filter
- `Enter`: Open selected file, commit, or stash details in the diff panel
- `Space`: Stage or unstage selected file
- `a`: Stage all
- `u`: Unstage all
- `D`: Discard selected worktree change, after confirmation
- `c`: Commit staged changes
- `b`: Checkout selected branch
- `n`: Create and checkout a new branch
- `m`: Merge selected branch into the current branch
- `s`: Stash changes, including untracked files
- `A`: Apply selected stash
- `S`: Pop selected stash
- `x`: Drop selected stash, after confirmation
- `f`: Fetch all remotes and prune stale references
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
