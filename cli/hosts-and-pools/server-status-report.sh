# Collect a server status report.
#
# Gather a host's diagnostic bundle: read the catalogue of sections it can report on, download the whole
# bundle, then download a smaller one covering only the sections you pick.
#
# Run it:
#   ./workflows.sh server-status-report https://xenserver root "$password"

server_status_report() {
    # Each host answers for itself, so which one you ask decides whose logs you get - support normally
    # wants one report per host. Here, the coordinator.
    pool=$(first_csv "$(xe pool-list --minimal)")
    target=$(xe pool-param-get uuid=$pool param-name=master)
    echo "Status report for $(xe host-param-get uuid=$target param-name=name-label)"

    # The host publishes a catalogue of the sections it can report on, each with a size estimate and
    # whether it may contain personal data, so you can decide what to collect before collecting it.
    capabilities=$(xe host-get-system-status-capabilities uuid=$target)
    keys=""
    defaults=""
    # Split the XML on '<' with bash's own field splitting rather than spawning a parser: each element
    # starts a field, and the ones we want begin `capability key="..."`.
    old_ifs=$IFS; IFS='<'
    for element in $capabilities; do
        case "$element" in
            capability\ *)
                key=$(xml_attr "$element" key)
                keys="${keys:+$keys,}$key"
                default_checked=$(xml_attr "$element" default-checked)
                [ "$default_checked" = "yes" ] && defaults="${defaults:+$defaults,}$key"
                printf '  %-22s max %9s bytes  default=%-3s pii=%s\n' \
                    "$key" "$(xml_attr "$element" max-size)" \
                    "$default_checked" "$(xml_attr "$element" pii)"
                ;;
        esac
    done
    IFS=$old_ifs

    rm -f cli-status-all.tar cli-status-config.tar
    # Take the sections the host marks default-checked, as XenCenter's dialog does: asking for every
    # section can mean gigabytes (VM memory dumps, every log) and a long wait while the host builds it.
    xe host-get-system-status uuid=$target filename=cli-status-all.tar entries="$defaults"
    whole=$(stat -c %s cli-status-all.tar)
    echo "default sections ($(count_csv "$defaults") of $(count_csv "$keys")): $whole bytes"

    # Pick a real, small section from the host's own catalogue rather than assuming a name: the catalogue
    # is server-defined (xen-bugtool's own --capabilities output), not a fixed client list, and
    # "xenserver-config" isn't one of the real keys any host actually publishes.
    subset_key=""
    for preferred in firstboot network-status; do
        case ",$keys," in *",$preferred,"*) subset_key=$preferred; break ;; esac
    done
    [ -n "$subset_key" ] || subset_key=$(first_csv "$keys")

    # Worth checking rather than assuming: a server that ignored the selection would look identical from
    # here until someone opened the archive and found the whole thing.
    xe host-get-system-status uuid=$target filename=cli-status-config.tar entries="$subset_key"
    subset=$(stat -c %s cli-status-config.tar)
    echo "$subset_key only:   $subset bytes"
    if [ "$subset" -ge "$whole" ]; then
        echo "  ERROR: selecting fewer sections did not produce a smaller bundle"
    fi

    rm -f cli-status-all.tar cli-status-config.tar
    echo "OK: server-status-report"
}

# The value of a named attribute in an XML element, using parameter expansion only - no xmllint, and no
# sed/grep process per attribute. Name the attribute in full: a prefix match would make `size` collect
# `min-size` as well.
xml_attr() {
    case "$1" in
        *"$2=\""*) local rest=${1#*$2=\"}; echo "${rest%%\"*}" ;;
        *) echo "" ;;
    esac
}
