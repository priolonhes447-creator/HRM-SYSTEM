const fs = require('fs');
const vm = require('vm');
const assert = require('assert/strict');
const { webcrypto } = require('crypto');
const html = fs.readFileSync('apply.html', 'utf8');
const script = html.slice(html.indexOf("let applicationReceiptKey = ''"), html.indexOf('</script>', html.indexOf("let applicationReceiptKey = ''")));
function setup(fetch) {
    const fields = new Map();
    const storage = new Map();
    const get = id => { if (!fields.has(id)) fields.set(id, { value: '', style: {}, disabled: false, classList: { add() {} }, reset() {} }); return fields.get(id); };
    class Form { constructor() { this.data = new Map([['first_name', ' Synthetic ']]); } entries() { return this.data.entries(); } set(k,v) { this.data.set(k,v); } }
    const context = { crypto: webcrypto, AbortController, FormData: Form, fetch, document: { getElementById: get }, validateRequiredApplicantFields: () => true, validatePositionAgeRequirement: () => true,
        sessionStorage: { getItem: k => storage.get(k), setItem: (k,v) => storage.set(k,v), removeItem: k => storage.delete(k) }, window: { API_BASE: '/api', getApiUrl: route => '/api'+route, setTimeout, clearTimeout } };
    vm.createContext(context); vm.runInContext(script, context);
    return { context, get, submit: () => context.submitApplication({ preventDefault() {} }) };
}
(async () => {
    const requiredUploads = [...html.matchAll(/<input[^>]*type="file"[^>]*>/g)].filter(match => /\srequired(?:\s|>)/.test(match[0])).map(match => match[0].match(/name="([^"]+)"/)[1]);
    assert.equal(requiredUploads.length, 7);
    const validator = html.slice(html.indexOf('function validateRequiredApplicantFields(form)'), html.indexOf("let applicationReceiptKey = ''"));
    for (const missing of requiredUploads) {
        let requests = 0;
        const incomplete = setup(async () => { requests++; throw new Error('Incomplete form must not send a request'); });
        const fields = requiredUploads.map(name => ({ type: 'file', files: name === missing ? [] : [{}], setCustomValidity() {}, reportValidity() {}, addEventListener() {} }));
        incomplete.get('applicantForm').querySelectorAll = () => fields;
        incomplete.get('applicantForm').reportValidity = () => true;
        vm.runInContext(validator, incomplete.context);
        await incomplete.submit();
        assert.equal(requests, 0, missing);
    }
    console.log('PASS every missing required attachment blocks submission before a network request');
    let postKey;
    const confirmed = setup(async (url, options) => {
        if (url.endsWith('/receipt')) {
            assert.equal(JSON.parse(options.body).submission_key, postKey);
            return { ok: true, json: async () => ({ received: true }) };
        }
        postKey = options.body.data.get('submission_key');
        throw new Error('Lost response after commit');
    });
    await confirmed.submit();
    assert.equal(confirmed.get('successCard').style.display, 'block');
    assert.equal(confirmed.get('submitBtn').disabled, false);
    console.log('PASS lost POST response reconciles saved receipt and shows success');
    const keys = [];
    const uncertain = setup(async (url, options) => {
        if (url.endsWith('/receipt')) return { ok: true, json: async () => ({ received: false }) };
        keys.push(options.body.data.get('submission_key'));
        throw new Error('Unavailable');
    });
    await uncertain.submit(); await uncertain.submit();
    assert.equal(keys[0], keys[1]);
    assert.match(uncertain.get('alertBox').innerText, /could not confirm/);
    assert.equal(uncertain.get('submitBtn').disabled, false);
    uncertain.context.resetForm(); await uncertain.submit();
    assert.notEqual(keys[2], keys[0]);
    console.log('PASS uncertain retry retains key; explicit new application gets new key');
    let calls = 0;
    const invalid = setup(async () => { calls++; return { ok: false, status: 400, text: async () => JSON.stringify({ error: 'Invalid document' }) }; });
    await invalid.submit();
    assert.equal(calls, 1); assert.equal(invalid.get('alertBox').innerText, 'Invalid document');
    console.log('PASS validation error preserved without receipt lookup');
    let uploadLimitCalls = 0;
    const oversized = setup(async () => {
        uploadLimitCalls++;
        return { ok: false, status: 413, text: async () => { throw new Error('Should not wait for HTML error body'); } };
    });
    await oversized.submit();
    assert.equal(uploadLimitCalls, 1);
    assert.match(oversized.get('alertBox').innerText, /request-size limit is too low/);
    assert.equal(oversized.get('submitBtn').disabled, false);
    console.log('PASS nginx HTML 413 shows upload-limit error immediately without receipt lookup');
    const htmlRejected = setup(async () => ({ ok: false, status: 403, text: async () => '<html>Forbidden</html>' }));
    await htmlRejected.submit();
    assert.match(htmlRejected.get('alertBox').innerText, /HTTP 403/);
    console.log('PASS non-JSON hosting rejection keeps the HTTP error');
    const slow = setup(() => new Promise(() => {}));
    slow.submit(); await slow.submit();
    assert.equal(slow.get('submitBtn').disabled, true);
    console.log('PASS double-click guard remains active');
    process.exit(0);
})().catch(error => { console.error(error); process.exit(1); });
