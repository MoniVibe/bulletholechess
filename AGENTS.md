Always consider maintainability, reliability, security, and performance.
Ensure all code is human-readable, has comments with reasoning, and is as simple as possible.

Maintainability:
- Create new functions and files for any code that can be better maintained.
- Remove unnecessary and stale code.
- Define variables for constants.
- Refactor existing code you encounter to approach best practices. Refactor for DRY when applicable, in the file and across files.
- Be wary of altering existing logic - don't break anything

Reliability:
- Design any tests you see fit and add them to the CI/CD, only if they are relevant long-term (not prone to change). CI/CD run time is limited so optimize for short-running scripts. Ensure caching and artifacts are used only when necessary, as to avoid organization limits across all repos.

Scalability:
- This app is expected to support tens of thousands of concurrent games and interactions

Security:
- Treat data and code as protected information. Assume harmful actors will try to destory our app and steal our data.