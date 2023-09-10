# Clash Proxy
export https_proxy=http://127.0.0.1:7890;export http_proxy=http://127.0.0.1:7890;export all_proxy=socks5://127.0.0.1:7891
export HTTPS_PROXY=http://127.0.0.1:7890;export HTTP_PROXY=http://127.0.0.1:7890;export ALL_PROXY=socks5://127.0.0.1:7891

alias proxy="export https_proxy=http://127.0.0.1:7890;export http_proxy=http://127.0.0.1:7890;export all_proxy=socks5://127.0.0.1:7891;export HTTPS_PROXY=http://127.0.0.1:7890;export HTTP_PROXY=http://127.0.0.1:7890;export ALL_PROXY=socks5://127.0.0.1:7891"
alias unproxy="unset https_proxy; unset http_proxy; unset all_proxy; unset HTTPS_PROXY; unset HTTP_PROXY; unset ALL_PROXY"
