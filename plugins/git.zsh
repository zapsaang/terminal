alias gp="git push"
alias gs="git stash"
alias gsp="git stash pop"
alias gckp="git checkout -"
alias gckb="git checkout -b"
alias gpgp="gp & gckp"


function grcsp() {
  grc && sleep $1 && gprc || sleep $1 && gprc
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

function gck() {
  if [ -z "$1" ]; then
    echo "Usage: gck <branch>"
    return 1
  fi

  local branch="$1"
  local remote="origin"

  # 1. 尝试本地精确匹配
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "Checking out existing local branch '$branch'..."
    git checkout "$branch"
    # 只有当前分支有上游时才拉取
    if git rev-parse --abbrev-ref "$branch@{u}" >/dev/null 2>&1; then
        git pull --ff-only
    fi
    return $?
  fi

  # 2. 尝试远程精确匹配 (利用本地缓存)
  if git show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
    echo "Found '$branch' on remote (cached). Creating local tracking branch..."
    git checkout -b "$branch" --track "$remote/$branch"
    git pull --ff-only
    return $?
  fi

  # 3. 尝试联网 Fetch 特定分支
  # 只有在前两步都失败时，才尝试去服务器确认一下 "是不是我本地缓存过期了？"
  # 注意：这里只 fetch 这一个分支，而不是 --all，速度极快。
  echo "Branch not found locally. Checking remote '$remote' for '$branch'..."
  if git fetch "$remote" "$branch:$remote/$branch" >/dev/null 2>&1; then
    echo "Found '$branch' on remote. Checkout..."
    git checkout -b "$branch" --track "$remote/$branch"
    return $?
  fi

  # 4. 模糊匹配 (Fuzzy Match)
  # 只有当前面都失败时才进行。
  # 使用 grep -F 避免正则歧义
  local candidates
  candidates=$(git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/heads/ refs/remotes/$remote/ | grep -F "$branch" | head -n 1)

  if [ -n "$candidates" ]; then
    local local_target="${candidates#$remote/}"
    
    echo "⚠️  Exact match not found. Assuming you meant recent branch: '$candidates'"
    
    if [ "$candidates" != "$local_target" ]; then
        # 这是一个远程分支
        if git show-ref --verify --quiet "refs/heads/$local_target"; then
            git checkout "$local_target"
        else
            git checkout -b "$local_target" --track "$candidates"
        fi
    else
        # 本地分支
        git checkout "$candidates"
    fi
    
    # 尝试拉取
    git pull --ff-only >/dev/null 2>&1
    return $?
  fi

  # 5. 彻底放弃治疗，创建新分支
  echo "No matching branch found. Creating new branch '$branch'..."
  git checkout -b "$branch"
}
