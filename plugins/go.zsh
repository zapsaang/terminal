# Go
[[ $(which brew) == "brew not found" ]] || BREWGODIR=$(brew --prefix golang)
if (( $BREWGODIR[(I)/go] > 0 )) {
    export GOROOT="$BREWGODIR/libexec"
} else {
    export GOROOT=/usr/local/go
}

export GOPATH=$HOME/Code/golang
export PATH=$PATH:$GOPATH/bin

alias gomt="go mod tidy"
alias gomv="go mod vendor"
alias gomtv="go mod tidy && go mod vendor"
