_quality_manager()
{
    local current commands formats
    COMPREPLY=()
    current="${COMP_WORDS[COMP_CWORD]}"
    commands="doctor maintenance daemon status queue approvals history events recover campaign-create campaign-start campaign-pause campaign-resume campaign-reconcile release-create release-qualify release-export approve reject help version"
    formats="terminal json markdown"

    if [[ "${COMP_WORDS[COMP_CWORD-1]}" == "--format" ]]; then
        COMPREPLY=( $(compgen -W "${formats}" -- "${current}") )
    elif [[ "${COMP_WORDS[COMP_CWORD-1]}" == "--config" || "${COMP_WORDS[COMP_CWORD-1]}" == "campaign-create" || "${COMP_WORDS[COMP_CWORD-1]}" == "approve" || "${COMP_WORDS[COMP_CWORD-1]}" == "reject" ]]; then
        COMPREPLY=( $(compgen -f -- "${current}") )
    elif [[ "${current}" == -* ]]; then
        COMPREPLY=( $(compgen -W "--config --format --project --dry-run --once --help --version" -- "${current}") )
    else
        COMPREPLY=( $(compgen -W "${commands}" -- "${current}") )
    fi
}
complete -F _quality_manager quality-manager
