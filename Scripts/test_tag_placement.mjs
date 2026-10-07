// Exercise the website's actual placement function against the native parity vectors.
// Run from any directory with: node Scripts/test_tag_placement.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const html = fs.readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8');
const source = html.slice(html.indexOf('const TAG_ANCHORS ='), html.indexOf('function positionTag('));
const context = vm.createContext({});
vm.runInContext(source + '\nglobalThis.anchors = TAG_ANCHORS;', context);
const vectors = JSON.parse(fs.readFileSync(new URL('../Tests/Fixtures/tag-placement.json', import.meta.url), 'utf8'));
for (const v of vectors) {
  const [xAnchor, yAnchor] = context.anchors[v.position];
  assert.equal(context.tagAxisOrigin(xAnchor, v.width, v.tagWidth, v.inset, v.horizontalOffset), v.x, v.name + ': x');
  assert.equal(context.tagAxisOrigin(yAnchor, v.height, v.tagHeight, v.inset, v.verticalOffset), v.y, v.name + ': y');
}
assert.equal(context.tagAxisOrigin('center', 700, 30, 20, Infinity), 335);
assert.equal(context.tagAxisOrigin('end', 1000, 100, 20, NaN), 880);
console.log(`Website placement: ${vectors.length} shared vectors and non-finite offsets passed.`);
