# Go
export GOPATH=$HOME/go
export GOROOT=/usr/local/opt/go/libexec
export PATH=$PATH:$GOPATH/bin

alias gomt="go mod tidy"
alias gomv="go mod vendor"
alias gomtv="go mod tidy && go mod vendor"
