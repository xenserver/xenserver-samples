# Tag and organize objects.
#
# Organize a pool with tags and folders: add tags to a VM and a host (tags work on any object type), place the
# VM in a folder, read it all back, then tidy up.
#
# Run it:
#   ./workflows.sh tags-and-folders https://xenserver root "$password"

tags_and_folders() {
    vm=$(vm_uuid web-01); h=$(first_host)
    xe vm-param-add uuid=$vm param-name=tags param-key=web
    xe host-param-add uuid=$h param-name=tags param-key=gold
    echo "VM tags:   $(xe vm-param-get uuid=$vm param-name=tags)"
    echo "Host tags: $(xe host-param-get uuid=$h param-name=tags)"
    xe vm-param-set uuid=$vm other-config:folder=/Production/Web
    echo "VM folder: $(xe vm-param-get uuid=$vm param-name=other-config param-key=folder)"
    xe vm-param-remove uuid=$vm param-name=tags param-key=web
    xe host-param-remove uuid=$h param-name=tags param-key=gold
    xe vm-param-remove uuid=$vm param-name=other-config param-key=folder
    echo "OK: tags-and-folders"
}
