# Cross-pool copy a VM.
#
# Copy a VM from one pool to another: open a session to each pool, obtain a receiver token on the destination,
# then send a copy of the VM from the source. Takes the destination pool's URL as an extra argument after the
# password.
#
# Run it:
#   ./workflows.sh cross-pool-copy-vm https://xenserver root "$password" https://other-pool
#
# Optional key=value arguments (default):
#   transfer_network ("" - falls back to the destination's management network)

cross_pool_copy_vm() {
    # Copy a VM to another pool (Storage XenMotion copy). Real xe does the whole cross-pool dance
    # itself given the destination master's address + credentials; copy=true leaves the source intact.
    local dest_hp dest_master dest_net transfer_network v
    local -a dest_opts vif_map migrate_opts
    dest_hp=${desturl#*://}; dest_hp=${dest_hp%%/*}
    dest_host=${dest_hp%%:*}
    dest_opts=()
    if [ "$dest_hp" != "$dest_host" ] && [ "${dest_hp##*:}" != 443 ]; then dest_opts=(-p $((${dest_hp##*:} + 1))); fi
    case "${XE_EXE:-xe}" in *.exe | *.EXE) dest_opts+=(-no-warn-new-certificates -no-warn-certificates) ;; esac
    # Like xe() (connection.sh), but for the destination pool - and like it, pass a failure's output on to
    # stderr: captured by $(...), it would otherwise vanish and set -e would stop the script silently.
    xe_dest() {
        local out rc=0
        out=$(command "${XE_EXE:-xe}" -s "$dest_host" "${dest_opts[@]}" -u "$destuser" -pw "$destpass" "$@") || rc=$?
        if [ $rc -ne 0 ]; then [ -z "$out" ] || printf '%s\n' "$out" >&2; return $rc; fi
        [ -z "$out" ] || printf '%s\n' "$out"
    }
    vm=$(vm_uuid "$copy_vm")
    # Map every NIC to the destination coordinator's management network, one both pools can certainly
    # reach. Left unmapped, a real pool refuses the VIF ("not mapped to a destination Network") unless it
    # happens to find a same-named network there.
    dest_master=$(xe_dest pool-param-get uuid=$(xe_dest pool-list --minimal) param-name=master)
    dest_net=$(xe_dest pif-list host-uuid=$dest_master management=true params=network-uuid --minimal)
    vif_map=()
    for v in $(each_csv "$(xe vif-list vm-uuid=$vm --minimal)"); do vif_map+=("vif:$v=$dest_net"); done
    # And every disk to the destination pool's default SR. Left unmapped, xe picks an SR itself - on a real
    # pool a small shared one it happened to prefer, which ran out of space (SR_BACKEND_FAILURE_44).
    local dest_sr vbd vdi_map=()
    dest_sr=$(xe_dest pool-param-get uuid=$(xe_dest pool-list --minimal) param-name=default-SR)
    for vbd in $(each_csv "$(xe vbd-list vm-uuid=$vm type=Disk --minimal)"); do
        vdi=$(xe vbd-param-get uuid=$vbd param-name=vdi-uuid)
        [[ $vdi == *-* ]] && vdi_map+=("vdi:$vdi=$dest_sr")
    done
    # The migration traffic itself travels over remote-network if given, or (as here, left unset) xe
    # falls back to the destination's management network. For performance, production use should use a
    # dedicated migration network instead - pass transfer_network=<name|uuid> to set remote-network.
    transfer_network=$(param transfer_network "")
    migrate_opts=()
    [ -n "$transfer_network" ] && migrate_opts+=(remote-network="$transfer_network")

    # The VMs the destination already has, to tell the copy apart afterwards (never by name alone).
    local before copy
    before=",$(xe_dest vm-list is-control-domain=false --minimal),"
    xe vm-migrate uuid=$vm remote-master=$dest_host remote-username=$destuser remote-password=$destpass copy=true \
        "${migrate_opts[@]}" "${vif_map[@]}" "${vdi_map[@]}"
    still=$([ -n "$(vm_uuid "$copy_vm")" ] && echo True || echo False)
    echo "Sent '$copy_vm' to $dest_host (copy); source still present: $still"

    # Tidy up so the example is repeatable: the copy and its disks, on the destination pool.
    copy=""
    for v in $(each_csv "$(xe_dest vm-list is-control-domain=false --minimal)"); do
        [[ $before == *",$v,"* ]] || { copy=$v; break; }
    done
    if [ -n "$copy" ]; then
        echo "  the copy on the destination: $(xe_dest vm-param-get uuid=$copy param-name=name-label) ($copy)"
        xe_dest vm-uninstall uuid=$copy force=true
    else
        # No new VM on the destination: the copy did not arrive, so there is nothing to tidy up.
        echo "  the copy on the destination: not found (nothing to tidy up)"
    fi
    echo "OK: cross-pool-copy-vm"
}
