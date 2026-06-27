const fs = require('fs');

const QUEUE_FILE = 'shader_plans/queue.json';

function loadQueue() {
  try {
    const data = fs.readFileSync(QUEUE_FILE, 'utf8');
    return JSON.parse(data);
  } catch (e) {
    return { queue: [], completed: [], pending: [], rejected: [], on_hold: [], metadata: {} };
  }
}

function saveQueue(queue) {
  fs.writeFileSync(QUEUE_FILE, JSON.stringify(queue, null, 2));
}

function complete(filename) {
  const queue = loadQueue();
  let found = false;
  const now = new Date().toISOString();

  // Search in queue array
  for (const item of queue.queue || []) {
    if (item.file === filename || item.filename === filename) {
      item.status = 'completed';
      item.completed_at = now;
      found = true;
      console.log(`✅ Completed (queue): ${item.title || filename}`);
    }
  }

  // Search in pending array
  const pending = queue.pending || [];
  for (let i = pending.length - 1; i >= 0; i--) {
    if (pending[i].filename === filename) {
      const item = pending[i];
      item.status = 'completed';
      item.completed_at = now;
      queue.completed = queue.completed || [];
      queue.completed.push(item);
      pending.splice(i, 1);
      found = true;
      console.log(`✅ Completed (pending): ${item.title || filename}`);
    }
  }

  if (!found) {
    console.log(`⚠️ Not found in queue/pending, adding to completed: ${filename}`);
    queue.completed = queue.completed || [];
    queue.completed.push({
      filename: filename,
      status: 'completed',
      completed_at: now
    });
  }

  saveQueue(queue);
}

function main() {
  const args = process.argv.slice(2);
  if (args.length < 2) {
    console.log('Usage: node scripts/update_queue.js complete <plan-file> [plan-file...]');
    process.exit(1);
  }

  const cmd = args[0];
  if (cmd !== 'complete') {
    console.log(`Unknown command: ${cmd}`);
    console.log('Usage: node scripts/update_queue.js complete <plan-file> [plan-file...]');
    process.exit(1);
  }

  for (let i = 1; i < args.length; i++) {
    complete(args[i]);
  }
  console.log('\n📋 Queue updated successfully.');
}

main();
