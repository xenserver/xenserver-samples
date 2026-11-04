# Conventions and extensions

[Guide](README.md) · [Workflow examples](workflows/README.md)

A handful of conventions extend the core API without changing its shape. They're worth knowing because
the management tools rely on them, and so can you.

## other_config and metadata

Most classes carry an `other_config` map for client-owned metadata. Management tools use keyed entries
here: for example a VM's folder placement lives in `other_config["folder"]`, and custom fields under
`other_config["XenCenter.CustomFields.<name>"]`. See [Custom fields](workflows/custom-fields.md) and
[Tag and organize objects](workflows/tags-and-folders.md).

## Tags

Every object has a `tags` list with `add_tags` / `remove_tags` accessors, used to group objects across
the pool independently of the tree. They work on any object type, including the pool itself (see
[Pool tags](workflows/pool-tags.md)).

## API versions

The API is versioned, and newer releases add classes, fields and messages. A client can read the host's
`API_version_major` / `API_version_minor` to decide which features are available before calling them.
