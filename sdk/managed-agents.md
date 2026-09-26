---
title: Managed Agent Sessions
---

# Managed Agent Sessions

Use a managed session when your application needs an agent to work in the same isolated machine across multiple turns. Smol cloud installs the selected harness, runs turns after your request disconnects, records events for replay, and can checkpoint, rewind, or fork the agent's machine. The Node, Python, and Rust SDKs expose the same cloud session lifecycle.

Set `SMOL_CLOUD_TOKEN` to an account API key, and [store a model-provider credential](/docs/introduction/concepts/isolation-networking-credentials) named `anthropic` for the `claude-code` harness. The SDK calls below create the agent's machine, but they do not clone your repository into `/workspace`; stage your project through the machine API before asking the agent to edit it.

::: code-group

```ts [TypeScript]
import { AgentSession } from "smolmachines";

const agent = await AgentSession.create(
  { name: "fixer", harness: "claude-code", credential: "anthropic" },
  { target: "cloud" },
);
while ((await agent.info()).status === "starting") {
  await new Promise((resolve) => setTimeout(resolve, 2000));
}
if ((await agent.info()).status !== "ready") throw new Error("agent setup failed");
await (await agent.machine()).writeFile("/workspace/task.txt", Buffer.from("Fix the tests"));

const turn = await agent.send("Fix the failing tests", {
  idempotencyKey: "task-123",
});
for await (const event of agent.events(turn)) {
  if (event.type === "event") console.log(event.id, event.data);
  else console.log("finished:", event.turn.status);
}
```

```python [Python]
import time
from smol import AgentSession, ConnectOptions

agent = AgentSession.create(
    "fixer", harness="claude-code", credential="anthropic",
    conn=ConnectOptions(target="cloud"),
)
while agent.info()["status"] == "starting":
    time.sleep(2)
if agent.info()["status"] != "ready":
    raise RuntimeError("agent setup failed")
agent.machine().write_file("/workspace/task.txt", "Fix the tests")

turn = agent.send("Fix the failing tests", idempotency_key="task-123")
for event in agent.events(turn):
    if event["type"] == "event":
        print(event["id"], event["data"])
    else:
        print("finished:", event["turn"]["status"])
```

```rust [Rust]
use smolmachines::{cloud_agent::CloudAgentSession, smol_cloud::types::{CreateAgent, SendAgentTurn}, ConnectOptions};

let agent = CloudAgentSession::create(&CreateAgent {
    name: "fixer".into(),
    harness: Some("claude-code".into()),
    credential: Some("anthropic".into()),
    ..Default::default()
}, &ConnectOptions::cloud())?;
while agent.info()?.status == "starting" {
    std::thread::sleep(std::time::Duration::from_secs(2));
}
assert_eq!(agent.info()?.status, "ready", "agent setup failed");
agent.machine()?.write_file("/workspace/task.txt", b"Fix the tests".to_vec())?;
let turn = agent.send(&SendAgentTurn {
    prompt: "Fix the failing tests".into(),
    env: Default::default(),
    timeout_seconds: None,
}, Some("task-123"))?;
for event in agent.events(turn, None)? {
    println!("{:?}", event?);
}
```

:::

`create` returns while setup runs. Check that the session reaches `ready` before sending its first turn; handle `failed` as an error. `machine()` gives you the current machine handle so you can stage repository files in `/workspace` with the usual file API. Attach again after a rewind because the machine ID changes. Each turn returns an index immediately. Its event stream ends with a `done` summary; if the connection breaks, reconnect with the last event ID as `after`. Reusing an idempotency key with the same turn input returns the original index.

After a turn is checkpointed, use `rewind(turn)` to restore that state or `fork(turn, newName)` to try another approach in an independent machine. `cancel(turn)` stops a running turn; `pause()`, `resume()`, and `delete()` manage the session's machine. Fetch `info()` for turn history and use `AgentSession.list()` (or `CloudAgentSession::list()`) to page through an account's sessions.

Managed sessions are a cloud feature. Local agent sessions are available through `smol agent` and the Rust `smolmachines::agent::Session` API; the Node and Python managed-session clients do not silently run a local machine.
