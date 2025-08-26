function grcsp() {
  grc && sleep $1 && gprc
}

function grc() {
  git add . && git commit -m "resolve conflict"
}

function gprc() {
  git push
  if [ $? -eq 0 ]; then
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$current_branch" == conflict* ]]; then
      echo "On conflict branch, switching back..."
      git checkout -
    else
      echo "Not on a conflict branch, staying on $current_branch."
    fi
  else
    echo "git push failed, please check the error."
    return 1
  fi
}

function gplf() {
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  git pull --force origin "$current_branch":"$current_branch"
}

gck() {
  if [ -z "$1" ]; then
    echo "Usage: gck <branch>"
    return 1
  fi

  local branch="$1"

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "Switching to existing local branch '$branch'"
    git checkout "$branch"

    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      git pull --ff-only
    fi
    return $?
  fi

  if ! git ls-remote --exit-code --heads origin "$branch" > /dev/null 2>&1; then
    echo "Fetching remote branches because '$branch' not found locally..."
    git fetch --all --prune > /dev/null 2>&1
  fi

  if git ls-remote --heads origin "$branch" | grep -q "$branch"; then
    echo "Local branch not found, creating and tracking remote branch '$branch'"
    git checkout -b "$branch" "origin/$branch"
    git pull --ff-only
    return $?
  fi

  local candidates
  candidates=$(git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/remotes/origin/ refs/heads/ | grep "$branch")

  if [ -n "$candidates" ]; then
    local target_branch=$(echo "$candidates" | head -n 1)
    echo "Branch '$branch' not found. Switching to latest matching branch '$target_branch'"

    if [[ "$target_branch" == origin/* ]]; then
      local local_branch="${target_branch#origin/}"
      git checkout -b "$local_branch" "$target_branch"
      git pull --ff-only
    else
      git checkout "$target_branch"

      if git show-ref --verify --quiet "refs/remotes/origin/$target_branch"; then
        git pull --ff-only
      fi
    fi
    return $?
  fi

  echo "No branch matching '$branch'. Creating new branch '$branch'."
  git checkout -b "$branch"
}


alias gs="git stash"
alias gsp="git stash pop"
alias gckp="git checkout -"
alias gpgp="gp & gckp"
