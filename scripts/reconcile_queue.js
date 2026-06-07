const fs = require('fs');

// Load queue
const queue = JSON.parse(fs.readFileSync('swarm-tasks/upgrade-queue.json', 'utf8'));

// Load weekly completed list from weekly_upgrade_swarm.md
const weekly = fs.readFileSync('agents/weekly_upgrade_swarm.md', 'utf8');
const completedIds = new Set();

// Extract IDs from 'Recently Completed' tables
const idRegex = /\|\s*\d+\s*\|\s*`([^`]+)`\s*\|/g;
let m;
while ((m = idRegex.exec(weekly)) !== null) {
  completedIds.add(m[1]);
}

// Also check progress file
try {
  const progress = JSON.parse(fs.readFileSync('swarm-outputs/upgrade-progress.json', 'utf8'));
  if (progress.upgraded_shaders) {
    progress.upgraded_shaders.forEach(s => completedIds.add(s.id));
  }
  if (progress.new_generative_shaders) {
    progress.new_generative_shaders.forEach(s => completedIds.add(s.id));
  }
} catch (e) {
  console.log('No progress file or parse error');
}

// Also scan WGSL files for 'upgraded-rgba' or batch markers
const shadersDir = 'public/shaders';
const files = fs.readdirSync(shadersDir).filter(f => f.endsWith('.wgsl'));
files.forEach(f => {
  const content = fs.readFileSync(`${shadersDir}/${f}`, 'utf8');
  if (content.includes('upgraded-rgba') || content.includes('batch-4') || content.includes('batch-3') || content.includes('batch-2')) {
    completedIds.add(f.replace('.wgsl', ''));
  }
});

console.log('Found', completedIds.size, 'completed shader IDs');

// Mark them in queue
let updated = 0;
queue.items.forEach(item => {
  if (completedIds.has(item.id) && item.status !== 'completed') {
    item.status = 'completed';
    updated++;
  }
});

fs.writeFileSync('swarm-tasks/upgrade-queue.json', JSON.stringify(queue, null, 2));
console.log('Updated', updated, 'items to completed');
console.log('Pending now:', queue.items.filter(i => i.status === 'pending').length);
console.log('Completed now:', queue.items.filter(i => i.status === 'completed').length);
