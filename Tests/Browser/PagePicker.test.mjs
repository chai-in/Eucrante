import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';
const script = readFileSync(new URL('../../Sources/EucranteApp/Resources/PagePicker.js', import.meta.url), 'utf8');
function scan(links = [], media = [], page = 'https://www.youtube.com/watch?v=OAS-STPdWbc&list=RD123') {
  const location = { href: page };
  const document = { title: 'Song <script>alert(1)</script>', querySelectorAll: selector => selector === 'a[href]' ? links.map(href => ({href: new URL(href,page).href, textContent:'Song', getAttribute:()=>null})) : media };
  runInNewContext(script, { location, document, URL, alert:()=>{} });
  return JSON.parse(new URL(location.href).searchParams.get('payload'));
}
test('canonicalizes YouTube identities and ignores accounts, playlists, credentials and blobs', () => {
  const result = scan(['https://youtu.be/OAS-STPdWbc?t=1','/shorts/V_w8fhtkTBY','https://youtube.com/@creator','https://youtube.com/playlist?list=foo','https://user:pass@example.com/file.mp3'], [{tagName:'VIDEO',currentSrc:'blob:https://youtube.com/xxx'}]);
  assert.equal(result.items.length, 2);
  assert.equal(result.items[0].url, 'https://www.youtube.com/watch?v=OAS-STPdWbc');
  assert.equal(result.items[1].url, 'https://www.youtube.com/watch?v=V_w8fhtkTBY');
});
test('includes direct media and caps payload honestly', () => {
  const result = scan(Array.from({length:120}, (_,i)=>`https://example.com/song${i}.mp3`));
  assert.equal(result.items.length, 100);
  assert.equal(result.truncated, true);
});
test('preserves signed direct media query strings and treats title as data', () => {
  const result = scan(['https://example.com/song.mp3?token=a%26b&expires=1']);
  assert.equal(result.items[1].url, 'https://example.com/song.mp3?token=a%26b&expires=1');
  assert.equal(result.title, 'Song <script>alert(1)</script>');
});
