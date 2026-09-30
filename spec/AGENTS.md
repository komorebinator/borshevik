# Borshevik

This project is built with the [Duckspec](https://github.com/komorebinator/duckspec) framework — its structure, guidelines, and conventions live in `@Term` files, not just this document. DuckTools reads them, available both as an MCP server and as the `ducktools` CLI; both expose the same operations.

Before any work, load this project's spec:

- MCP: `load_project(project_path="Borshevik")`
- CLI: `ducktools load-project Borshevik`

If the project is not registered in your active workspace yet, run the same command from the repository root with the project file's path instead: `spec/Borshevik.yaml`.

To see every project registered across all your workspaces, not just this one:

- MCP: `list_projects()`
- CLI: `ducktools list-projects`
