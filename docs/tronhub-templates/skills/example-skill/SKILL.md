# Example Skill

Use this skill when the user asks for the example workflow.

## Required Dependencies

- `example-tool-cli` is required.
- `example-model-provider` is optional and can be used for higher-quality natural-language generation.

## Workflow

1. Read the user's request and relevant project files.
2. Check that required CLIs are installed before running the workflow.
3. Call `example-tool-cli` with the smallest task payload that can complete the operation.
4. Return a concise Markdown response with outputs, file paths, and follow-up actions.

## Output

Return Markdown. Use links for created files and include command output only when it is useful to the user.
