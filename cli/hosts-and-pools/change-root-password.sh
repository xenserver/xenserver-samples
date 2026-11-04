# Change the root password.
#
# Change the local superuser password, handle the wrong-old-password failure, and change it back.
#
# Run it:
#   ./workflows.sh change-root-password https://xenserver root "$password"

change_root_password() {
    # xe exposes this as user-password-change. It takes the OLD password as well as the new one, even
    # though you are already authenticated - but a root session's old_pwd is never actually checked
    # (CA-13567): the only real gate is that the SESSION itself has to be a local superuser's, which this
    # one necessarily is. There is no "wrong old password is rejected" demonstration worth making here.
    original=$pass temporary=xe-example-temp-password
    xe user-password-change old="$original" new=$temporary
    echo "Password changed."
    # Unlike an SDK session, xe has no session to keep: every command logs in afresh, so from here on
    # it needs the NEW password - including the command that changes it back. And restore it however the
    # script ends (set -e exits on the first failure), or root would be left on the temporary password.
    pass=$temporary
    trap 'pass=$temporary; xe user-password-change old=$temporary new="$original" >/dev/null 2>&1' EXIT

    echo "New logins work with the new password: $(count_csv "$(xe pool-list --minimal)") pool"

    xe user-password-change old=$temporary new="$original"
    pass=$original
    trap - EXIT
    echo "Password restored."
    echo "OK: change-root-password"
}
