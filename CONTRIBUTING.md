# Contributing

Contributions are welcome: a new workflow, a fix, or a clearer explanation. Questions and suggestions are
welcome too, on the [issues](https://github.com/xenserver/xenserver-samples/issues) page. Before starting
something big, open an issue to discuss it first.

## How the repository fits together

Each workflow is one task, done the same way in every language: PowerShell, the `xe` CLI, Python, C#,
Go and Java. [`workflows.json`](workflows.json) lists them all, with the description and cautions shown in
the docs. Each language's folder holds one file per workflow, a connection helper, shared helpers, and a
dispatcher that runs any workflow by name (see the folder's README). The pages in
[`docs/workflows/`](docs/workflows/README.md) are generated from those sources.

## Adding or changing a workflow

1. **List it in `workflows.json`**, in the right section: its `id`, `title` and `description`, plus
   `requires` and `caution` where they apply. If a language genuinely cannot do it, say why under
   `unsupported` rather than leaving it out.
2. **Write it in every language**, following the files around it, and register it in each language's
   dispatcher with placeholder defaults that `key=value` arguments override. The versions should do the
   same thing in the same order and print equivalent output, ending with `OK: <id>` when they succeed.
3. **Keep it self-contained.** Connect with the folder's connection helper and log out at the end. Remove
   what the workflow creates and put back what it changes, even when it fails partway (a `finally`, or a
   trap in the CLI), so it can run again on the same pool. Explain why in comments, not what: the reader
   is learning the API.
4. **Run it against a test pool, in every language.** Never a production pool: many workflows change
   pool-wide state. Check that it passes, that it leaves the pool as it found it, and that a second run
   passes too.
5. **Regenerate the docs** and commit them with the change, as [tools/README.md](tools/README.md#generating-the-workflow-docs)
   describes, passing your runs' output so the pages show it. `python3 tools/docs/generate_docs.py --check`
   must pass.

To try your change against an SDK that hasn't been released yet, see
[Running against an unreleased SDK](tools/README.md#running-against-an-unreleased-sdk).

## Pull requests

- Keep each pull request to one change that can be reviewed and merged on its own.
- Write commit messages that explain why the change is needed and why it works.
- Make sure every commit builds, so `git bisect` stays useful.
- Sign off every commit (`git commit -s`): submissions are accepted under the
  [Developer Certificate of Origin](https://developercertificate.org/). Make sure you have the right to
  submit the change; if you made it at work, your employer may own it.

For the list of maintainers, see [MAINTAINERS](MAINTAINERS.md).
