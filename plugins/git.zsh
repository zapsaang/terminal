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

alias gs="git stash"
alias gsp="git stash pop"
alias gck="git checkout"
alias gckp="git checkout -"
alias gpgp="gp & gckp"
