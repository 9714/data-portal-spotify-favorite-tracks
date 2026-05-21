Review the current branch's changes against main. Identify issues and categorize each finding by severity:

**[High]** — bugs, security vulnerabilities, data loss risks, incorrect logic that would cause failures in production  
**[Mid]** — code quality issues, missing error handling, performance concerns, unclear naming that affects maintainability  
**[Low]** — style inconsistencies, minor improvements, suggestions that are nice-to-have

For each finding, output:
- Severity label: `[High]` / `[Mid]` / `[Low]`
- File and line reference
- What the issue is and why it matters

End with a one-line summary: how many findings per severity level and whether the changes are safe to merge.
