### Added by Zinit's installer
if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
    print -P "%F{33} %F{220}Installing %F{33}ZDHARMA-CONTINUUM%F{220} Initiative Plugin Manager (%F{33}zdharma-continuum/zinit%F{220})…%f"
    command mkdir -p "$HOME/.local/share/zinit" && command chmod g-rwX "$HOME/.local/share/zinit"
    command git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git" && \
        print -P "%F{33} %F{34}Installation successful.%f%b" || \
        print -P "%F{160} The clone has failed.%f%b"
fi

source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

# Load a few important annexes, without Turbo
# (this is currently required for annexes)
zinit light-mode for \
    zdharma-continuum/zinit-annex-as-monitor \
    zdharma-continuum/zinit-annex-bin-gem-node \
    zdharma-continuum/zinit-annex-patch-dl \
    zdharma-continuum/zinit-annex-rust

### End of Zinit's installer chunk

ZINIT_1MAP[ZST::]=https://github.com/zapsaang/terminal/trunk/
ZINIT_1MAP[ZSTP::]=https://github.com/zapsaang/terminal/trunk/plugins/
ZINIT_1MAP[ZSTT::]=https://github.com/zapsaang/terminal/trunk/themes/

ZINIT_2MAP[ZST::]=https://raw.githubusercontent.com/zapsaang/terminal/master/
ZINIT_2MAP[ZSTP::]=https://raw.githubusercontent.com/zapsaang/terminal/master/plugins/
ZINIT_2MAP[ZSTT::]=https://raw.githubusercontent.com/zapsaang/terminal/master/themes/

# proxy
zinit snippet ZSTP::proxy.zsh

# zsh
zinit ice lucid wait='1' atinit='zpcompinit'
zinit light zdharma-continuum/fast-syntax-highlighting
zinit light Aloxaf/fzf-tab

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Powerlevel10k
zinit ice depth=1; zinit light romkatv/powerlevel10k

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

zinit light zsh-users/zsh-history-substring-search
zinit light zsh-users/zsh-autosuggestions

zinit snippet ZSTP::general.zsh
zinit snippet ZSTP::nvim.zsh
zinit snippet ZSTP::icloud.zsh
zinit snippet ZSTP::brew.zsh
zinit snippet ZSTP::go.zsh
zinit snippet ZSTP::git.zsh
zinit snippet ZSTT::fzf_dracula.zsh

zinit snippet OMZL::key-bindings.zsh
zinit snippet OMZL::git.zsh
zinit snippet OMZL::grep.zsh
zinit snippet OMZL::history.zsh
zinit snippet OMZL::clipboard.zsh
zinit snippet OMZL::theme-and-appearance.zsh
zinit snippet OMZP::colored-man-pages/colored-man-pages.plugin.zsh
zinit snippet OMZP::git/git.plugin.zsh
zinit snippet OMZP::sudo/sudo.plugin.zsh

zinit ice svn
zinit snippet OMZP::extract

# key binding
bindkey '^P' history-substring-search-up
bindkey '^N' history-substring-search-down
bindkey '^@' autosuggest-accept

# Others
zinit load djui/alias-tips
