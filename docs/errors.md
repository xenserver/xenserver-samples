# Errors

[Guide](README.md) · [Workflow examples](workflows/README.md)

When a call fails, the API returns a structured error that every binding surfaces in a language-natural
way: an exception, or an error value in Go.

## The shape of an error

An error is an array: `[CODE, param1, param2, …]`. The first element is a stable **error code**; the
rest give context. For example `UUID_INVALID` is followed by the class and the offending UUID, and
`VM_LACKS_FEATURE` by the VM. Branch on the code, not on the message text, which is for humans and may
change.

## In each binding

- **C#**: a `Failure` whose `ErrorDescription` is the array; `ErrorDescription[0]` is the code.
- **Python**: an `XenAPI.Failure` whose `details` is the array.
- **Java**: a `Types.XenAPIException`; specific errors are typed subclasses (for example `UuidInvalid`).
- **Go**: a returned `error` value carrying the code.
- **PowerShell**: a terminating error you catch with `try`/`catch`.
- **xe**: a non-zero exit status, with the error code and its parameters printed (on standard output).

[Handle an API error](workflows/error-handling.md) shows the idiom in each language, side by side.
