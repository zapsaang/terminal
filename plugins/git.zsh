function grcp() {
  git add . && git commit -m "resolve conflict" && git push
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$current_branch" == "conflict"* ]]; then
    git checkout -
  fi
}

alias gs="git stash"
alias gsp="git stash pop"
alias gcp="git checkout -"
