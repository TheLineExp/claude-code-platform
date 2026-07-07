# graphify — optional exports (wiki / neo4j / svg / graphml / mcp)

Reached two ways (the dispatcher decides by whether `graphify-out/graph.json` already exists):

1. **Fast path — graph already exists (most common):** the dispatcher routes the export flag
   straight here. These exports read only *permanent* build artifacts — `graphify-out/graph.json`
   (all of them) and `.graphify_labels.json` (`--wiki`, written at Step 5) — and BOTH survive
   Step 9 cleanup, so there is nothing to rebuild. Run only the matching export command(s)
   below directly; do NOT re-run the build. (The "Step 6b / Step 7…" labels and the
   "before Step 8/9 cleanup" ordering only apply when this file is reached from inside a build
   — see path 2; standalone, ordering is irrelevant.)
2. **From inside a build — no graph existed yet:** `build-pipeline.md`'s "Optional exports"
   step reads this file after Step 6 (HTML/Obsidian). The file-producing exports run there
   before Step 9 cleanup; `--mcp` starts its blocking server only after Step 9 (it never
   returns).

Run only the export(s) whose flag was given; skip the rest.

### Step 6b - Wiki (only if --wiki flag)

**Only run this step if `--wiki` was explicitly given in the original command.**

Needs `.graphify_labels.json` (written at Step 5). That file — like `graph.json` — is NOT
removed by Step 9 cleanup, so this export works whether run standalone on an existing graph
or from inside a build.

```bash
graphify export wiki
```

### Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag)

**If `--neo4j`** - generate a Cypher file for manual import:

```bash
graphify export neo4j
```

**If `--neo4j-push <uri>`** - push directly to a running Neo4j instance. Ask the user for credentials if not provided:

```bash
graphify export neo4j --push bolt://localhost:7687 --user neo4j --password PASSWORD
```

Default URI is `bolt://localhost:7687`, default user is `neo4j`. Uses MERGE - safe to re-run without creating duplicates.

### Step 7b - SVG export (only if --svg flag)

```bash
graphify export svg
```

### Step 7c - GraphML export (only if --graphml flag)

```bash
graphify export graphml
```

### Step 7d - MCP server (only if --mcp flag)

Serves the existing `graphify-out/graph.json`. This is a **blocking, long-running foreground
server that never returns** — so it must be the LAST action: run it directly on the fast path,
or, when reached from inside a build, only AFTER Step 9 cleanup/report have finished (never
before, or Steps 8/9 will never run).

```bash
python3 -m graphify.serve graphify-out/graph.json
```

This starts a stdio MCP server that exposes tools: `query_graph`, `get_node`, `get_neighbors`, `get_community`, `god_nodes`, `graph_stats`, `shortest_path`. Add to Claude Desktop or any MCP-compatible agent orchestrator so other agents can query the graph live.

To configure in Claude Desktop, add to `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "graphify": {
      "command": "python3",
      "args": ["-m", "graphify.serve", "/absolute/path/to/graphify-out/graph.json"]
    }
  }
}
```
