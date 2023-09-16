# Go
[[ ! $(which brew) ]] || BREWGODIR=$(brew --prefix golang)
if (( $BREWGODIR[(I)/go] > 0 )) {
    export GOROOT="$BREWGODIR/libexec"
} else {
    export GOROOT=/usr/local/go
}

export GOPATH=$HOME/code/go
export PATH=$PATH:$GOPATH/bin

alias gomt="go mod tidy"
alias gomv="go mod vendor"
alias gomtv="go mod tidy && go mod vendor"
