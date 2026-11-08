# Security

Please **don't** open a public issue for a security problem. Use GitHub's private vulnerability reporting ("Report a vulnerability" on the Security tab), or email **support@untrustedtech.dev**.

Useful details to include: your device and Android version, the OpenWear version (shown at the bottom of Settings), and the steps that reproduce the problem.

## Fixed issues

- **pairing-test-33 and pairing-test-34 (test builds):** tapping "Found it" on the Find phone screen could unlock a phone that Android treated as trusted, without a PIN or biometrics. Fixed in pairing-test-35 and in every later build, including 1.0.0. The affected builds were withdrawn.
