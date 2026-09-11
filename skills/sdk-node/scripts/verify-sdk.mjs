// Drives one cloud machine through the Node SDK and asserts values.
// Creates a billable machine and deletes it in a finally block, including on an
// assertion failure, because a leaked cloud machine bills until someone notices.
import { Machine, ExecutionError } from 'smolmachines';

const fails = [];
const check = (name, expected, actual) => {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) console.log(`${name}=ok (${a})`);
  else { console.log(`${name}=FAIL expected=${e} actual=${a}`); fails.push(name); }
};

const conn = { target: 'cloud', apiKey: process.env.SMOL_CLOUD_TOKEN };
let machine = null;
try {
  machine = await Machine.create({
    name: 'smolskill-node1',
    image: 'library/alpine:3.20',
    command: ['sh', '-c', 'while true; do sleep 3600; done'],
    resources: { cpus: 1, memoryMb: 256, network: true },
  }, conn);
  console.log(`machine_id=${machine.id}`);

  const r = await machine.exec(['sh', '-c', 'echo SDK_OK']);
  r.assertSuccess();
  check('exec_stdout', 'SDK_OK\n', r.stdout);

  // exec RESOLVES for a failed command. A try/catch around it catches transport
  // errors only, so the exit code has to be read from the result.
  const bad = await machine.exec(['sh', '-c', 'echo boom >&2; exit 42']);
  check('failed_exec_resolves', false, bad.success);
  check('failed_exec_exit_code', 42, bad.exitCode);
  let raised = false;
  try { bad.assertSuccess(); } catch (e) { raised = e instanceof ExecutionError; }
  check('assertSuccess_throws', true, raised);

  await machine.writeFile('/workspace/rt.txt', Buffer.from('ROUNDTRIP'));
  const got = await machine.readFile('/workspace/rt.txt');
  check('readFile_returns_buffer', true, Buffer.isBuffer(got));
  check('file_roundtrip', 'ROUNDTRIP', got.toString());

  // The headline Node-only trap: the key is a plain enumerable property, so
  // console.log and JSON.stringify both expose it. Asserted, never printed.
  const serialised = JSON.stringify(machine);
  check('stringify_leaks_the_key', true, serialised.includes('smk_'));
  const inspected = (await import('node:util')).inspect(machine, { depth: 6 });
  check('inspect_leaks_the_key', true, inspected.includes('smk_'));
} finally {
  if (machine) { await machine.delete(); console.log('deleted=yes'); }
}
console.log('result=' + (fails.length ? 'sdk_failed' : 'sdk_ok'));
process.exit(fails.length ? 1 : 0);
