import assert from 'node:assert/strict';
import {audit} from './audit-staging-evidence.mjs';
const bad={production:{},staging:{},validation:{},extra:true};
assert.ok(audit(bad).errors.includes('INVALID_EVIDENCE_SHAPE'));
assert.ok(audit({production:[],staging:{},validation:{}}).errors.includes('INVALID_EVIDENCE_SHAPE'));
assert.ok(audit({production:{},staging:[],validation:{}}).errors.includes('INVALID_EVIDENCE_SHAPE'));
console.log('Gate152: unknown keys and invalid nested object shapes rejected');
