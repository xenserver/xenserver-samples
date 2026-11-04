# Fail over to the disaster recovery site.
#
# On the pool at the disaster recovery site, attach the storage array's replica of the protected pool's
# storage, read the pool metadata replicated to it, and recover the VMs and vApps it describes - as
# XenCenter's Disaster Recovery wizard does. By default this is a test failover, which removes what it
# recovered and detaches the storage again.
#
# Run it:
#   ./workflows.sh disaster-recovery-failover https://dr-site-pool root "$password" \
#       target=192.0.2.31 target_iqn=iqn.2009-01.com.example:replica-0 scsi_id=360a98...
#
# Optional key=value arguments (default):
#   target (192.0.2.31)
#   target_iqn (iqn.2009-01.com.example:replica-0)
#   scsi_id (360a980004265656d5f4a2d63764e5738)
#   port ("")
#   sr_type (lvmoiscsi)
#   test_failover (true)

# The replica is the LUN the storage array mirrors the protected pool's SR to: name it by the iSCSI target,
# IQN and SCSI id (sr_type lvmoiscsi), or by SCSI id alone for Fibre Channel/SAS (sr_type lvmohba). Before a
# real failover, break the mirror so that this site can write to the replica, and make sure no other pool
# has those LUNs attached: two pools using the same LUN corrupt it.
#
# drtask-create attaches every SR on the LUN that you name (by uuid) to this pool, keeping its uuid. The
# database: option (database:vdi-uuid=<metadata disk>) runs a command against the metadata replicated there
# - a separate, read-only database - instead of this pool, and vm-recover/appliance-recover recover out of
# it into this pool. A test failover then removes the recovered VMs and vApps - not their disks, which are
# the replica's - and detaches and forgets the SRs, as the wizard does.
disaster_recovery_failover() {
    local sr_type test_failover task sr vdi line uuid name has_metadata pool_name master vapp vm reason
    local -a dc uuids=() introduced=() recovered_vms=() recovered_vapps=() in_recovered_vapp=()
    sr_type=$(param sr_type lvmoiscsi)
    test_failover=$(param test_failover true)
    dc=(device-config:SCSIid=$(param scsi_id 360a980004265656d5f4a2d63764e5738))
    if [ "$sr_type" = lvmoiscsi ]; then
        dc+=(device-config:target=$(param target 192.0.2.31)
             device-config:targetIQN=$(param target_iqn iqn.2009-01.com.example:replica-0))
        [ -z "$(param port "")" ] || dc+=(device-config:port=$(param port ""))
    fi

    # Which SRs are on the LUN, and which of them hold pool metadata. sm-config:metadata=true asks for their
    # names and the pool_metadata_detected flag as well as their uuids. The probe answers one tag per line.
    uuid=""
    while IFS= read -r line; do
        case "$line" in
            *"<UUID>"*) uuid=$(xml_tag_text "$line" UUID); name=""; has_metadata="" ;;
            *"<name_label>"*) name=$(xml_tag_text "$line" name_label) ;;
            *"<pool_metadata_detected>true"*) has_metadata=", with pool metadata" ;;
            *"</SR>"*)
                echo "Found SR $name ($uuid)$has_metadata"
                uuids+=("$uuid") ;;
        esac
    done <<< "$(xe sr-probe type=$sr_type "${dc[@]}" sm-config:metadata=true)"
    if [ ${#uuids[@]} -eq 0 ]; then
        echo "there is no SR on that LUN" >&2
        exit 1
    fi

    task=$(xe drtask-create type=$sr_type "${dc[@]}" sr-whitelist=$(IFS=,; echo "${uuids[*]}"))
    for sr in $(each_csv "$(set_to_csv "$(xe drtask-param-get uuid=$task param-name=introduced-SRs)")"); do
        introduced+=("$sr")
    done
    echo "Attached $(for sr in "${introduced[@]}"; do xe sr-param-get uuid=$sr param-name=name-label; done | paste -sd, - | sed 's/,/, /g')"

    # Recover from every replicated database on the attached SRs: vApps first (their VMs come with them),
    # then the VMs not in a vApp. A VM whose disks are on storage this pool hasn't attached can't be
    # recovered - vm-assert-can-be-recovered says so - so skip it.
    for sr in "${introduced[@]}"; do
        for vdi in $(each_csv "$(xe vdi-list sr-uuid=$sr metadata-latest=true --minimal)"); do
            t=$(xe vdi-param-get uuid=$vdi param-name=type)
            [ "${t,,}" = metadata ] || continue
            db=database:vdi-uuid=$vdi

            # A pool often has no name of its own; XenCenter shows its coordinator's name instead.
            pool_name=$(xe pool-list $db params=name-label --minimal)
            if [ -z "$pool_name" ]; then
                master=$(xe pool-list $db params=master --minimal)
                pool_name=$(xe host-list $db uuid=$master params=name-label --minimal)
            fi
            echo "  pool metadata of $pool_name"

            in_recovered_vapp=()
            for vapp in $(each_csv "$(xe appliance-list $db --minimal)"); do
                name=$(xe appliance-list $db uuid=$vapp params=name-label --minimal)
                if ! reason=$(xe appliance-assert-can-be-recovered uuid=$vapp $db 2>&1); then
                    echo "  cannot recover vApp $name: ${reason%%$'\n'*}"
                    continue
                fi
                xe appliance-recover uuid=$vapp $db
                recovered_vapps+=("$vapp")
                for vm in $(each_csv "$(set_to_csv "$(xe appliance-list $db uuid=$vapp params=VMs --minimal)")"); do
                    recovered_vms+=("$vm"); in_recovered_vapp+=("$vm")
                done
                echo "  recovered vApp $name"
            done

            while IFS=$'\t' read -r name vm; do
                [ -n "$vm" ] || continue
                [[ " ${in_recovered_vapp[*]} " == *" $vm "* ]] && continue
                if ! reason=$(xe vm-assert-can-be-recovered uuid=$vm $db 2>&1); then
                    echo "  cannot recover $name: ${reason%%$'\n'*}"
                    continue
                fi
                xe vm-recover uuid=$vm $db
                recovered_vms+=("$vm")
                echo "  recovered $name"
            done <<< "$(for vm in $(each_csv "$(xe vm-list $db is-a-template=false is-control-domain=false \
                            is-a-snapshot=false --minimal)"); do
                            printf '%s\t%s\n' "$(xe vm-list $db uuid=$vm params=name-label --minimal)" "$vm"
                        done | sort)"
        done
    done

    # The recovered VMs keep their uuids, so look them up by uuid - a name may be taken here already.
    for vm in "${recovered_vms[@]}"; do
        echo "$(xe vm-param-get uuid=$vm param-name=name-label) is $(xe vm-param-get uuid=$vm param-name=power-state)"
    done

    if [ "$test_failover" = true ]; then
        for vm in "${recovered_vms[@]}"; do
            [ "$(xe vm-param-get uuid=$vm param-name=power-state)" = halted ] || xe vm-shutdown uuid=$vm force=true
            xe vm-destroy uuid=$vm
        done
        for vapp in "${recovered_vapps[@]}"; do xe appliance-destroy uuid=$vapp; done
    fi
    # Destroying the task detaches and forgets the SRs it attached that no recovered VM needs.
    xe drtask-destroy uuid=$task
    if [ "$test_failover" = true ]; then
        # The SRs the recovered VMs needed are no longer the task's: detach and forget those too.
        for sr in "${introduced[@]}"; do
            [ -z "$(xe sr-list uuid=$sr --minimal)" ] || detach_and_forget_sr $sr
        done
        echo "Test failover: removed the recovered VMs and detached the replica"
    else
        echo "Recovered VMs are halted: start them when you are ready"
    fi
    echo "OK: disaster-recovery-failover"
}
