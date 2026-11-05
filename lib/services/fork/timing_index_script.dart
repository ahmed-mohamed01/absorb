// Fork-owned: the page side of read along from a BookOrbit timing index.
// Upstream's narration script (services/narration_script.dart, installed as
// `window.__absorbMO`) lights the sentence being read by its element id. A
// timing index book reads a plain EPUB, with no sentence elements, so this
// goes in after that script and takes over its lookups once `MO.setTable`
// has said where each sentence's text sits in its chapter: the sentence is
// found there and painted with the browser's own highlight, which leaves the
// page's markup alone, so a selection or a saved place made meanwhile still
// names the page as the EPUB has it. A browser without that (iOS before
// 17.2) gets the sentence wrapped while it is lit instead. Without a table
// every call goes to upstream's function unchanged. See timing_index.dart
// and FORK_NOTES.md.

import 'dart:convert';

/// [bootstrap] (upstream's script, which this one rides in) followed by the
/// sentence positions of a timing index book, marked [key] so a page that
/// already holds them isn't sent them again. One evaluation: no call can
/// land on a page that has the script and not yet the positions.
String narrationPositionsSource(String bootstrap, String key, String positions) =>
    '$bootstrap; window.__absorbMO.setTable(${jsonEncode(key)}, $positions);';

/// 'y' when the page script holds the sentence positions marked [key].
String narrationHasPositionsSource(String key) =>
    "window.__absorbMO && __absorbMO.tblKey === ${jsonEncode(key)} ? 'y' : 'n'";

/// Appended to upstream's script body, inside its function.
const String forkNarrationPositionsScript = r'''
  var base = {
    clear: MO.clear, show: MO.show, where: MO.where, reveal: MO.reveal,
    go: MO.go, idsAt: MO.idsAt, onPage: MO.onPage, css: MO.css
  };

  // The same look for a sentence painted as a highlight.
  MO.css = function() {
    return base.css() + (MO.eink
      ? ' ::highlight(absorb-mo) { text-decoration: underline; }'
      : ' ::highlight(absorb-mo) { color: ' + MO.color + '; }');
  };

  // tbl is {chapter path: {n, h, i, s, e}}: the ids of its sentences in
  // reading order, with where each starts and ends counted in characters
  // that aren't whitespace, out of n in the chapter, which hash to h.
  MO.tbl = MO.tbl || null;
  MO.tblKey = MO.tblKey || '';

  // Counts the moves asked for, so one that waits on a chapter loading can
  // tell it was overtaken: read along stopped, or the narration moved on.
  MO.goSeq = MO.goSeq || 0;

  MO.setTable = function(key, t) {
    MO.clear();
    MO.tbl = t;
    MO.tblKey = key;
    MO.secOf = {};
    return true;
  };

  // cur, for a sentence lit from the table: key (chapter#id), el (what to
  // judge its place by), node (one of its text nodes), and either win (the
  // window its highlight is painted in) or spans (its wrappers).
  MO.unlight = function() {
    var c = MO.cur;
    if (c && c.key) {
      try {
        if (c.win) c.win.CSS.highlights.delete('absorb-mo');
        else MO.unwrap(c.spans);
      } catch (e) {}
      MO.cur = null;
      return;
    }
    base.clear();
  };

  // What the reader calls when read along stops.
  MO.clear = function() {
    MO.goSeq++;
    MO.unlight();
  };

  MO.sec = function(href) {
    if (!MO.tbl || !href) return null;
    MO.secOf = MO.secOf || {};
    if (!(href in MO.secOf)) {
      var hit = null;
      for (var k in MO.tbl) {
        if (MO.same(k, href)) { hit = MO.tbl[k]; break; }
      }
      if (hit && !hit.at) {
        // at: where each id is. live: the sentences that have any text.
        hit.at = {};
        hit.live = [];
        for (var j = 0; j < hit.i.length; j++) {
          hit.at[hit.i[j]] = j;
          if (hit.e[j] > hit.s[j]) hit.live.push(j);
        }
      }
      MO.secOf[href] = hit;
    }
    return MO.secOf[href];
  };

  // The last index of sorted [arr] whose value is at most [x], or -1.
  MO.lastAtMost = function(arr, x) {
    var lo = 0, hi = arr.length - 1, at = -1;
    while (lo <= hi) {
      var mid = (lo + hi) >> 1;
      if (arr[mid] <= x) { at = mid; lo = mid + 1; } else { hi = mid - 1; }
    }
    return at;
  };

  // Every text node of the chapter with how many counted characters come
  // before it, and the hash of them all. Built fresh each time: lighting a
  // sentence splits text nodes, and unlighting it joins them again.
  MO.textMap = function(doc) {
    var tw = doc.createTreeWalker(doc.body || doc.documentElement, 12, null, false);
    var nodes = [], cum = [], n = 0, h = 0, node;
    while ((node = tw.nextNode())) {
      var pe = node.parentNode;
      var tag = pe && pe.nodeName ? pe.nodeName.toLowerCase() : '';
      if (tag === 'script' || tag === 'style') continue;
      var t = node.nodeValue.replace(/\s+/g, '');
      nodes.push(node);
      cum.push(n);
      n += t.length;
      for (var c = 0; c < t.length; c++) h = (Math.imul(h, 31) + t.charCodeAt(c)) | 0;
    }
    return { nodes: nodes, cum: cum, n: n, h: h };
  };

  // The text node holding counted character [off], and the offset in it just
  // before that character ([after]: just past it).
  MO.point = function(map, off, after) {
    var at = MO.lastAtMost(map.cum, off);
    if (at < 0) return null;
    var text = map.nodes[at].nodeValue, left = off - map.cum[at];
    for (var c = 0; c < text.length; c++) {
      if (/\s/.test(text.charAt(c))) continue;
      if (left === 0) return { i: at, o: after ? c + 1 : c };
      left--;
    }
    return null;
  };

  // Sentence [k] of [sec] in a loaded chapter: its first and last text nodes
  // and the offsets in them.
  MO.span = function(map, sec, k) {
    if (sec.e[k] <= sec.s[k]) return null;
    var a = MO.point(map, sec.s[k], false), b = MO.point(map, sec.e[k] - 1, true);
    return a && b ? { a: a, b: b } : null;
  };

  // Something MO.visible can judge, for a sentence that isn't wrapped.
  MO.box = function(doc, map, sp) {
    var r = doc.createRange();
    r.setStart(map.nodes[sp.a.i], sp.a.o);
    r.setEnd(map.nodes[sp.b.i], sp.b.o);
    return {
      range: r,
      ownerDocument: doc,
      getClientRects: function() { return r.getClientRects(); },
      getBoundingClientRect: function() { return r.getBoundingClientRect(); }
    };
  };

  // The loaded chapter [href] of [sec] with its text map. No view when it
  // isn't loaded; bad when its text isn't the text the positions were
  // counted in.
  MO.chapter = function(href, sec) {
    var vs = MO.views();
    for (var i = 0; i < vs.length; i++) {
      var v = vs[i];
      if (!v.section || !MO.same(v.section.href, href)) continue;
      var doc = v.contents && v.contents.document;
      if (!doc) continue;
      var map = MO.textMap(doc);
      return { view: v, doc: doc, map: map, bad: map.n !== sec.n || map.h !== sec.h };
    }
    return { view: null };
  };

  MO.wrap = function(doc, map, sp) {
    var made = [];
    for (var i = sp.b.i; i >= sp.a.i; i--) {
      var node = map.nodes[i];
      if (!node.parentNode) continue;
      var from = i === sp.a.i ? sp.a.o : 0;
      var to = i === sp.b.i ? sp.b.o : node.nodeValue.length;
      if (to <= from || !/\S/.test(node.nodeValue.substring(from, to))) continue;
      var target = node;
      if (from > 0) target = target.splitText(from);
      if (to - from < target.nodeValue.length) target.splitText(to - from);
      var span = doc.createElement('span');
      span.className = 'absorb-mo-on absorb-mo-w';
      target.parentNode.insertBefore(span, target);
      span.appendChild(target);
      made.push(span);
    }
    return made.reverse();
  };

  MO.unwrap = function(spans) {
    var parents = [];
    for (var i = 0; i < spans.length; i++) {
      var el = spans[i], p = el.parentNode;
      if (!p) continue;
      while (el.firstChild) p.insertBefore(el.firstChild, el);
      p.removeChild(el);
      if (parents.indexOf(p) === -1) parents.push(p);
    }
    for (var k = 0; k < parents.length; k++) {
      try { parents[k].normalize(); } catch (e) {}
    }
  };

  // The lit sentence when it is [href]#[id] and still in the page: a
  // relayout throws the chapter's document away, lit sentence and all.
  MO.lit = function(href, id) {
    var c = MO.cur;
    if (!c || c.key !== href + '#' + id) return null;
    var n = c.node;
    return n.isConnected && n.ownerDocument && n.ownerDocument.defaultView ? c.el : null;
  };

  // The element (or box) to judge sentence [id] by, lighting it when [light].
  // Null when the book has no table: upstream's lookup by id then runs. A
  // string when there is nothing to judge: 'missing' (its chapter isn't
  // loaded), 'mismatch' (the chapter's text isn't the index's), or 'skip'
  // (the index places no such sentence).
  MO.target = function(href, id, light) {
    if (!MO.tbl) return null;
    var sec = MO.sec(href);
    if (!sec) { if (light) MO.unlight(); return 'skip'; }
    var el = MO.lit(href, id);
    if (el) return el;
    // Before the chapter is mapped: unlighting joins text nodes back up.
    if (light) MO.unlight();
    var ch = MO.chapter(href, sec);
    if (!ch.view) return 'missing';
    if (ch.bad) return 'mismatch';
    var k = sec.at[id];
    var sp = k === undefined ? null : MO.span(ch.map, sec, k);
    if (!sp) return 'skip';
    if (!light) return MO.box(ch.doc, ch.map, sp);
    MO.style(ch.doc);
    var key = href + '#' + id, win = ch.doc.defaultView;
    if (win && win.Highlight && win.CSS && win.CSS.highlights) {
      var box = MO.box(ch.doc, ch.map, sp);
      win.CSS.highlights.set('absorb-mo', new win.Highlight(box.range));
      MO.cur = { key: key, el: box, node: ch.map.nodes[sp.a.i], win: win };
      return box;
    }
    var spans = MO.wrap(ch.doc, ch.map, sp);
    if (!spans.length) return 'skip';
    MO.cur = { key: key, el: spans[0], node: spans[0], spans: spans };
    return spans[0];
  };

  MO.show = function(href, id) {
    var el = MO.target(href, id, true);
    if (el === null) return base.show(href, id);
    if (typeof el === 'string') return el;
    var vis = MO.visible(el);
    if (vis.low) return 'low';
    if (vis.far) return vis.dir < 0 ? 'far-before' : 'far-after';
    return vis.v ? 'on' : (vis.dir < 0 ? 'before' : 'after');
  };

  MO.where = function(href, id) {
    var el = MO.target(href, id, false);
    if (el === null) return base.where(href, id);
    if (typeof el === 'string') return el;
    var vis = MO.visible(el);
    return vis.v ? 'on' : (vis.dir < 0 ? 'before' : 'after');
  };

  MO.reveal = function(href, id) {
    var el = MO.target(href, id, false);
    if (el === null) return base.reveal(href, id);
    var c = null;
    try { c = rendition.manager && rendition.manager.container; } catch (e0) {}
    if (typeof el === 'string' || !c) return false;
    try {
      var fe = el.ownerDocument.defaultView.frameElement;
      var fr = fe ? fe.getBoundingClientRect() : { top: 0 };
      var y = fr.top + el.getBoundingClientRect().top;
      c.scrollTo({ top: c.scrollTop + y - window.innerHeight * 0.25, behavior: 'smooth' });
      return true;
    } catch (e) {
      return false;
    }
  };

  // Straight to the sentence when its chapter is loaded; otherwise to the
  // chapter, then on to the sentence once it is. Nowhere when the chapter's
  // text isn't the index's.
  MO.go = function(href, id) {
    if (!MO.tbl || !id) return base.go(href, id);
    var sec = MO.sec(href);
    if (!sec) return false;
    var item = null, items = [];
    try { items = book.spine.spineItems || []; } catch (e) {}
    for (var i = 0; i < items.length && !item; i++) {
      if (MO.same(items[i].href, href)) item = items[i];
    }
    if (!item) return false;
    var seq = ++MO.goSeq;
    if (MO.chapter(href, sec).view) return MO.goTo(href, sec, id);
    // Where the page is, to come back to if the chapter turns out not to be
    // the index's text.
    var back = null;
    try { back = rendition.currentLocation().start.cfi; } catch (e0) {}
    try {
      rendition.display(item.href).then(function() {
        if (MO.goSeq !== seq || MO.goTo(href, sec, id)) return;
        var ch = MO.chapter(href, sec);
        if (back && ch.view && ch.bad) rendition.display(back);
      });
    } catch (e) {
      return false;
    }
    return true;
  };

  MO.goTo = function(href, sec, id) {
    try {
      // Unlit first, so the place is named in the page's own markup.
      MO.unlight();
      var ch = MO.chapter(href, sec), k = sec.at[id];
      var sp = !ch.view || ch.bad || k === undefined ? null : MO.span(ch.map, sec, k);
      if (!sp) return false;
      var r = ch.doc.createRange();
      r.setStart(ch.map.nodes[sp.a.i], sp.a.o);
      r.collapse(true);
      rendition.display(ch.view.contents.cfiFromRange(r));
      return true;
    } catch (e) {
      return false;
    }
  };

  // How many counted characters of the chapter come before a point in it.
  MO.offsetOf = function(doc, map, container, offset) {
    var r = doc.createRange();
    r.setStart(container, offset);
    r.collapse(true);
    for (var k = 0; k < map.nodes.length; k++) {
      var node = map.nodes[k];
      if (node === container) return map.cum[k] + node.nodeValue.substring(0, offset).replace(/\s+/g, '').length;
      if (r.comparePoint(node, 0) > 0) return map.cum[k];
    }
    return map.n;
  };

  // The sentences of [sec] from the one holding counted character [off], or
  // the next one when [off] is in text no sentence covers.
  MO.idsFrom = function(sec, off, max) {
    var at = Math.max(0, MO.lastAtMost(sec.s, off));
    if (off >= sec.e[at] && at + 1 < sec.i.length) at++;
    return sec.i.slice(at, at + max);
  };

  // No section named when the selection's chapter has no usable positions:
  // nothing is played from, rather than the chapter's first sentence. bad
  // when that chapter's text isn't the index's.
  MO.idsAt = function(cfi) {
    if (!MO.tbl) return base.idsAt(cfi);
    var out = { href: '', ids: [] };
    // The chapter the selection names: with two loaded, its path can fit both.
    var spine = -1;
    try { spine = new ePub.CFI(cfi).spinePos; } catch (e0) {}
    var vs = MO.views();
    for (var i = 0; i < vs.length; i++) {
      var v = vs[i];
      if (!v.section || (spine >= 0 && v.section.index !== spine)) continue;
      var r = null;
      try { r = v.contents.range(cfi); } catch (e) {}
      if (!r) continue;
      var sec = MO.sec(v.section.href);
      if (!sec) break;
      var doc = v.contents.document, m = MO.textMap(doc);
      if (m.n !== sec.n || m.h !== sec.h) { out.bad = true; break; }
      out.href = v.section.href;
      out.ids = MO.idsFrom(sec, MO.offsetOf(doc, m, r.startContainer, r.startOffset), 60);
      break;
    }
    return JSON.stringify(out);
  };

  MO.onPage = function() {
    if (!MO.tbl) return base.onPage();
    var out = { href: '', ids: [] };
    var vs = MO.views();
    for (var i = 0; i < vs.length && !out.href; i++) {
      var v = vs[i];
      var doc = v.contents && v.contents.document;
      var sec = doc && v.section ? MO.sec(v.section.href) : null;
      if (!sec) continue;
      var m = MO.textMap(doc);
      if (m.n !== sec.n || m.h !== sec.h) { out.bad = true; continue; }
      // Sentences run in reading order: the first one not behind the page.
      var lo = 0, hi = sec.live.length - 1, first = -1;
      while (lo <= hi) {
        var mid = (lo + hi) >> 1;
        var sp = MO.span(m, sec, sec.live[mid]);
        if (sp && MO.visible(MO.box(doc, m, sp)).dir < 0) { lo = mid + 1; } else { first = mid; hi = mid - 1; }
      }
      var fsp = first < 0 ? null : MO.span(m, sec, sec.live[first]);
      if (fsp && MO.visible(MO.box(doc, m, fsp)).v) {
        out.href = v.section.href;
        out.ids = sec.i.slice(sec.live[first], sec.live[first] + 40);
        out.bad = false;
      }
    }
    return JSON.stringify(out);
  };
''';
