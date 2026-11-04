# Recover VMs after a disaster.
#
# Replicate the pool's database to shared storage, read it back as a separate database to see what it
# describes, and recover a VM out of it into a second, standby pool (dr_url).
#
# Run it:
#   ./workflows.sh disaster-recovery https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   dr_url ("")

# Disaster recovery works by writing the pool's own database out to a storage repository as a disk of type
# "metadata", then reading that back as a SEPARATE database to recover a VM out of it onto a second,
# standby pool. Recovering a VM back into the exact pool it was replicated from can't actually succeed with
# force=false (its uuid already exists there, so VM.recover always takes the replace-or-fail path and
# nothing replicated a moment ago from a live database can ever be "newer" than the live object it came
# from) - force=true would "fix" that by REPLACING (destroying and recreating) the live original, which is
# the one thing a DR demo must never do. A second pool is the only correct target, which is why this needs
# dr_url and has no default: pass dr_url=<url of a standby pool>. xe has no "session_to" argument to carry
# this (unlike the SDK languages' session-based VM.recover): instead, run the assert/recover calls on a
# connection opened to the standby pool itself, pointed at the metadata disk by uuid - the storage it lives
# on has to be reachable from the standby pool too, which is the whole premise of DR replication.
disaster_recovery() {
    local dr_url dr_host dr_hp dr_probe
    local -a dr_opts
    dr_url=$(param dr_url "")
    if [ -z "$dr_url" ]; then
        echo "disaster-recovery needs a second pool to recover into: pass dr_url=<url of a standby pool>" >&2
        exit 1
    fi
    dr_hp=${dr_url#*://}; dr_hp=${dr_hp%%/*}
    dr_host=${dr_hp%%:*}
    dr_opts=()
    if [ "$dr_hp" != "$dr_host" ] && [ "${dr_hp##*:}" != 443 ]; then dr_opts=(-p $((${dr_hp##*:} + 1))); fi
    case "${XE_EXE:-xe}" in *.exe | *.EXE) dr_opts+=(-no-warn-new-certificates -no-warn-certificates) ;; esac
    xe_dr() { command "${XE_EXE:-xe}" -s "$dr_host" "${dr_opts[@]}" -u "$user" -pw "$pass" "$@"; }
    # Follow HOST_IS_SLAVE on the standby pool too, the same one-time probe the main connection does.
    dr_probe=$(xe_dr pool-list --minimal 2>&1) || true
    if [[ $dr_probe =~ (Master|Coordinator)\ IP\ address:\ ([0-9A-Fa-f.:]+) ]]; then dr_host=${BASH_REMATCH[2]}; fi

    # Replication needs shared storage the standby pool can attach too, and only block storage (iSCSI,
    # HBA) supports it - an NFS SR fails SR_OPERATION_NOT_SUPPORTED. xe has no assert for it, so try each
    # shared SR in turn until one takes it.
    sr=""
    for candidate in $(each_csv "$(xe sr-list shared=true content-type=user --minimal)"); do
        if xe sr-enable-database-replication uuid=$candidate 2>/dev/null; then sr=$candidate; break; fi
    done
    if [ -z "$sr" ]; then
        echo "no shared SR here supports database replication (it needs iSCSI or HBA storage)" >&2
        exit 1
    fi
    echo "Replicating pool metadata to $(xe sr-param-get uuid=$sr param-name=name-label)"

    # Everything from here happens on the STANDBY pool, the way XenCenter's DR wizard works from the pool
    # you fail over to: it has the same SR attached, rescans it to see the metadata disk just written,
    # reads the database there, and recovers into itself.
    if [ -z "$(xe_dr sr-list uuid=$sr --minimal)" ]; then
        echo "the standby pool has not attached this SR: attach the same storage there first" >&2
        exit 1
    fi
    xe_dr sr-scan uuid=$sr
    # The type reads "Metadata" in xe's output, so compare it case-insensitively rather than filtering.
    vdi=""
    for v in $(each_csv "$(xe_dr vdi-list sr-uuid=$sr --minimal)"); do
        t=$(xe_dr vdi-param-get uuid=$v param-name=type)
        if [ "${t,,}" = metadata ]; then vdi=$v; break; fi
    done
    if [ -z "$vdi" ]; then
        echo "the standby pool sees no metadata disk on this SR after rescanning it" >&2
        exit 1
    fi
    echo "  metadata disk: $vdi"

    # `database:vdi-uuid=` runs the command against the replicated database instead of the live pool, so
    # this lists the VMs as they were written out rather than the ones running now - only real guest VMs
    # are recoverable, so exclude templates, control domains and snapshots.
    recoverable=$(xe_dr vm-list database:vdi-uuid=$vdi is-a-template=false is-control-domain=false \
        is-a-snapshot=false --minimal)
    echo "  the replicated database describes $(count_csv "$recoverable") recoverable VM(s)"

    # Only a VM whose disks are all on storage the standby pool can see can be recovered there. Take the
    # first that passes the check, as the DR wizard lists them.
    md=""
    for candidate in $(each_csv "$recoverable"); do
        if xe_dr vm-assert-can-be-recovered uuid=$candidate database:vdi-uuid=$vdi 2>/dev/null; then
            md=$candidate; break
        fi
    done
    if [ -z "$md" ]; then
        echo "no VM in the replicated database has all its disks on storage the standby pool can see" >&2
        exit 1
    fi
    name=$(xe_dr vm-list uuid=$md database:vdi-uuid=$vdi params=name-label --minimal)
    echo "  recovering $name"
    xe_dr vm-recover uuid=$md database:vdi-uuid=$vdi force=false

    # It is a real VM on the standby pool now, not merely a command that returned - look it up there, by
    # the uuid full_restore preserved, never by name (a name can coincidentally collide with something
    # already on the destination pool).
    echo "  $name is $(xe_dr vm-param-get uuid=$md param-name=power-state) on the standby pool"

    # Tidy up on the standby pool only, by uuid - never touch the source pool's VMs. vm-destroy, not
    # vm-uninstall: the disks are the protected pool's own disks on the shared SR, not copies.
    xe_dr vm-destroy uuid=$md
    xe sr-disable-database-replication uuid=$sr
    echo "OK: disaster-recovery"
}
