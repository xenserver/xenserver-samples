# Tag and organize objects.
#
# Organize a pool with tags and folders: add tags to a VM and a host (tags work on any object type), place the
# VM in a folder, read it all back, then tidy up.
#
# Run it:
#   ./workflows.sh tags-and-folders https://xenserver root "$password"

tags_and_folders() {
    vm=$(vm_uuid web-01); h=$(first_host)
    remote_xe vm-param-add uuid=$vm param-name=tags param-key=web
    remote_xe host-param-add uuid=$h param-name=tags param-key=gold
    echo "VM tags:   $(remote_xe vm-param-get uuid=$vm param-name=tags)"
    echo "Host tags: $(remote_xe host-param-get uuid=$h param-name=tags)"
    remote_xe vm-param-set uuid=$vm other-config:folder=/Production/Web
    echo "VM folder: $(remote_xe vm-param-get uuid=$vm param-name=other-config param-key=folder)"
    remote_xe vm-param-remove uuid=$vm param-name=tags param-key=web
    remote_xe host-param-remove uuid=$h param-name=tags param-key=gold
    remote_xe vm-param-remove uuid=$vm param-name=other-config param-key=folder
    ok tags-and-folders
}
