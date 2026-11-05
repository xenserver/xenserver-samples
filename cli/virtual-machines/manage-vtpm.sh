# Manage a virtual TPM.
#
# Attach a virtual TPM to a halted VM, read it back and remove it again. A VM may have at most one, and only
# while it is halted.
#
# Run it:
#   ./workflows.sh manage-vtpm https://xenserver root "$password"

manage_vtpm() {
    # A halted VM with no vTPM yet. A VM may have at most one, and it can only be attached while halted
    # - the device is presented to the guest at boot. vTPM is not supported for a BIOS-mode VM, only a
    # UEFI one (HVM-boot-params:firmware = uefi), so pick one of those rather than any halted VM.
    vm=""
    for v in $(each_csv "$(xe vm-list power-state=halted --minimal)"); do
        [ -z "$(xe vm-param-get uuid=$v param-name=vtpms)" ] &&
        [ "$(xe vm-param-get uuid=$v param-name=HVM-boot-params param-key=firmware 2>/dev/null)" = "uefi" ] &&
            { vm=$v; break; }
    done
    [ -n "$vm" ] || { echo "no halted UEFI VM without a vTPM already attached was found" >&2; exit 1; }
    echo "Attaching a vTPM to $(xe vm-param-get uuid=$vm param-name=name-label)"

    vtpm=$(xe vtpm-create vm-uuid=$vm is-unique=false)
    echo "  unique to this VM:   $(xe vtpm-param-get uuid=$vtpm param-name=is_unique)"
    echo "  protected:           $(xe vtpm-param-get uuid=$vtpm param-name=is_protected)"
    echo "  VM now has $(count_csv "$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=vtpms)")") vTPM(s)"

    # The VM advertises whether another can be added; once it has one, it cannot.
    case "$(xe vm-param-get uuid=$vm param-name=allowed-operations)" in
        *create_vtpm*) echo "  can add another:     true" ;;
        *)             echo "  can add another:     false" ;;
    esac

    xe vtpm-destroy uuid=$vtpm --force       # xe insists: the vTPM's secrets are destroyed with it
    echo "  after removal:       $(count_csv "$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=vtpms)")") vTPM(s)"
    echo "OK: manage-vtpm"
}
