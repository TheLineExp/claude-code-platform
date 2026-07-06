# graphify — optional exports (wiki / neo4j / svg / graphml / mcp)

Loaded on demand from `build-pipeline.md` when the matching flag was passed. Run these
AFTER Step 6 (HTML/Obsidian) and BEFORE Step 8/9 cleanup — `--wiki` needs `.graphify_labels.json`,
which Step 9 deletes. Run only the export(s) whose flag was given; skip the rest.

### Step 6b - Wiki (only if --wiki flag)

**Only run this step if `--wiki` was explicitly given in the original command.**

Run this before Step 9 (cleanup) so `.graphify_labels.json` is still available.

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
