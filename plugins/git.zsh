function grcp() {
  git add . && git commit -m "resolve conflict" && git push
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$current_branch" == "conflict"* ]]; then
    git checkout -
  fi
}

function gplf() {
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  git pull --force origin "$current_branch":"$current_branch"
}

alias gs="git stash"
alias gsp="git stash pop"
alias gck="git checkout"
alias gckp="git checkout -"
