"""VM boot configuration.

Set a VM's vCPU counts and boot order, then read them back.

Run it::

    vm_boot_config("https://xenserver", "root", password, "Rocky Linux 8")
"""

from connection import connect
from helpers import destroy_vm_and_disks, provision, template_by_name


def vm_boot_config(url, username, password, template_name, new_vm_name="sdk-example-boot"):
    """Provision a throwaway VM, then set its vCPU counts and boot order (HVM_boot_params)."""
    session = connect(url, username, password)
    vm = session.xenapi.VM.clone(template_by_name(session, template_name), new_vm_name)
    provision(session, vm)

    session.xenapi.VM.set_VCPUs_max(vm, "4")
    session.xenapi.VM.set_VCPUs_at_startup(vm, "2")
    print("vCPUs: %s/%s" %
          (session.xenapi.VM.get_VCPUs_at_startup(vm), session.xenapi.VM.get_VCPUs_max(vm)))

    # Boot mode: firmware ("bios"/"uefi") lives in HVM_boot_params; Secure Boot in
    # platform["secureboot"]. "auto" (not a hard-coded "true") is the real xe/XenCenter
    # convention: xapi resolves it against whether the pool actually holds Secure Boot
    # certificates, at VM.start time - a hard "true" would claim Secure Boot is on even on a
    # template that was never set up for it, since set_platform does no validation of its own.
    session.xenapi.VM.set_HVM_boot_params(vm, {"order": "cdn", "firmware": "uefi"})
    platform = session.xenapi.VM.get_platform(vm)
    platform["secureboot"] = "auto"
    session.xenapi.VM.set_platform(vm, platform)
    print("Boot order: %s" % session.xenapi.VM.get_HVM_boot_params(vm)["order"])
    print("Boot mode: firmware=%s, secureboot=%s (resolved against pool certificates at boot)" %
          (session.xenapi.VM.get_HVM_boot_params(vm)["firmware"],
           session.xenapi.VM.get_platform(vm)["secureboot"]))

    destroy_vm_and_disks(session, vm)
    print("OK: vm-boot-config")
    session.xenapi.session.logout()
