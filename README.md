# gitcku

A native Objective-C++ terminal UI git client for macOS.

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

## Keys

- `1`: Status
- `2`: Diff
- `3`: Log
- `4`: Branches
- `j` / `Down`: Move down
- `k` / `Up`: Move up
- `g`: Top
- `G`: Bottom
- `Space`: Stage or unstage selected file
- `a`: Stage all
- `u`: Unstage all
- `c`: Commit staged changes
- `b`: Checkout selected branch
- `p`: Push
- `P`: Pull
- `r`: Refresh
- `q`: Quit

The client shells out to the system `git` binary and runs commands with argument arrays, not shell strings.
