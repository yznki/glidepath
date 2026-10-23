# Security policy

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately: open the repository's **Security** tab
and choose **Report a vulnerability**. GitHub keeps the report visible only to the maintainer and you.

Include the Glidepath version, the steps to reproduce, and what an attacker could do. A small proof of concept helps.
You will get a reply as soon as the maintainer can look at it. Fixes ship in a normal release, and the advisory
credits you unless you ask not to be named.

## In scope

- **Prompt injection from PR content.** Titles, descriptions, diffs, comments or branch names that make Claude run a
  command, read a file or post something it should not.
- **Token handling.** GitHub tokens reaching the model, the logs, the state files or a posted comment.
- **Posting without consent.** Reviews posted to repos or PRs that were not selected, or from a run the user did not
  start or approve.

Bugs with no security impact belong in a regular issue.

## Threat model

The design and the layers that defend against these cases are in [docs/security.md](docs/security.md). The adversarial
test is in [docs/security-test.md](docs/security-test.md).
