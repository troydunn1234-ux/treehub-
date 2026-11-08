import Foundation

extension Bridge {
    /// Runs before the page's own scripts. Gives the page the same `window.claude.use(...)`
    /// services it had on claude.ai, backed by the phone instead:
    ///   db        → documents saved in the app (Documents/store.json)
    ///   assets    → photos saved in the app, served at /_blob/<id>
    ///   downloads → the iOS share sheet
    /// Anything else (AI, connectors) answers null, and the pages already handle that.
    static func bootScript(initialStore: String) -> String {
        """
        (function(){
          if (window.claude && window.claude.use) return;
          var store = \(initialStore);
          if (!store || typeof store !== 'object') store = {};
          var listeners = [];
          var saveTimer = null;
          function post(msg){ return window.webkit.messageHandlers.native.postMessage(msg); }
          function persist(){
            clearTimeout(saveTimer);
            saveTimer = setTimeout(function(){ post({op:'store', json: JSON.stringify(store)}); }, 120);
          }
          document.addEventListener('visibilitychange', function(){
            if (document.visibilityState === 'hidden') { clearTimeout(saveTimer); post({op:'store', json: JSON.stringify(store)}); }
          });
          function clone(v){ return v === undefined ? undefined : JSON.parse(JSON.stringify(v)); }
          function leaf(p){ var a = p.split('/'); return a[a.length-1]; }
          function newId(){ return Date.now().toString(36) + Math.random().toString(36).slice(2,10); }
          function docSnap(path){
            var d = store[path];
            return { id: leaf(path), exists: d !== undefined, data: function(){ return clone(d); },
                     metadata: { fromCache: false, hasPendingWrites: false }, ref: docRef(path) };
          }
          function colSnap(col){
            var pre = col + '/';
            var docs = Object.keys(store).filter(function(k){ return k.indexOf(pre) === 0 && k.slice(pre.length).indexOf('/') < 0; })
                                         .sort().map(docSnap);
            return { docs: docs, size: docs.length, empty: !docs.length, metadata: { fromCache: false },
                     forEach: function(f){ docs.forEach(f); } };
          }
          function notify(){
            listeners.slice().forEach(function(l){
              try { l.cb(l.kind === 'doc' ? docSnap(l.path) : colSnap(l.path)); } catch(e) { console.error(e); }
            });
          }
          function changed(){ persist(); setTimeout(notify, 0); }
          function listen(kind, path, cb){
            var l = { kind: kind, path: path, cb: cb };
            listeners.push(l);
            setTimeout(function(){ if (listeners.indexOf(l) >= 0) cb(kind === 'doc' ? docSnap(path) : colSnap(path)); }, 0);
            return function(){ var i = listeners.indexOf(l); if (i >= 0) listeners.splice(i, 1); };
          }
          function docRef(path){
            return {
              id: leaf(path), path: path,
              get: function(){ return Promise.resolve(docSnap(path)); },
              set: function(data, opts){
                store[path] = (opts && opts.merge && store[path]) ? Object.assign({}, store[path], clone(data)) : clone(data);
                changed(); return Promise.resolve();
              },
              update: function(data){
                if (store[path] === undefined) { var e = new Error('Document not found'); e.code = 'not_found'; return Promise.reject(e); }
                store[path] = Object.assign({}, store[path], clone(data)); changed(); return Promise.resolve();
              },
              delete: function(){ delete store[path]; changed(); return Promise.resolve(); },
              onSnapshot: function(cb){ return listen('doc', path, cb); }
            };
          }
          function colRef(col){
            return {
              id: leaf(col), path: col,
              doc: function(id){ return docRef(col + '/' + (id || newId())); },
              add: function(data){ var r = docRef(col + '/' + newId()); return r.set(data).then(function(){ return r; }); },
              get: function(){ return Promise.resolve(colSnap(col)); },
              onSnapshot: function(cb){ return listen('col', col, cb); }
            };
          }
          var db = { doc: docRef, collection: colRef };

          function toBase64(data){
            if (typeof data === 'string') {
              return Promise.resolve(btoa(unescape(encodeURIComponent(data))));
            }
            return new Promise(function(res, rej){
              var r = new FileReader();
              r.onload = function(){ var s = String(r.result); res(s.slice(s.indexOf(',') + 1)); };
              r.onerror = function(){ rej(r.error); };
              r.readAsDataURL(data instanceof Blob ? data : new Blob([data]));
            });
          }
          var assets = {
            upload: function(blob){
              return toBase64(blob).then(function(b64){ return post({op:'blob', data: b64}); })
                                   .then(function(id){ return { id: id, url: '/_blob/' + id }; });
            }
          };
          var downloads = {
            save: function(o){
              return toBase64(o.data).then(function(b64){ return post({op:'share', filename: o.filename || 'file', data: b64}); })
                .then(function(){ return true; }, function(){ var e = new Error('declined'); e.code = 'declined'; throw e; });
            }
          };
          var services = { db: db, assets: assets, downloads: downloads };
          window.claude = { use: function(name){ return Promise.resolve(services[name] || null); } };
        })();
        """
    }

    /// Runs after the page loads: springy presses, haptics, tap sparkles, shake-for-confetti.
    static func funScript(accent: String) -> String {
        """
        (function(){
          var ACCENT = '\(accent)';
          var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
          var fx = function(k){ try { window.webkit.messageHandlers.fx.postMessage(k); } catch(e){} };

          var css = document.createElement('style');
          css.textContent =
            'html{-webkit-tap-highlight-color:transparent;-webkit-touch-callout:none}' +
            'button,[role=button],a,label,summary,.btn,.chip,.tab{touch-action:manipulation}' +
            'button:not(:disabled),[role=button]{transition:transform .18s cubic-bezier(.3,1.6,.5,1),filter .18s}' +
            'button:not(:disabled):active,[role=button]:active{transform:scale(.94);filter:brightness(1.15)}' +
            '::selection{background:' + ACCENT + '55}' +
            '.__spark{position:fixed;left:0;top:0;width:7px;height:7px;border-radius:50%;pointer-events:none;z-index:2147483647;' +
              'background:' + ACCENT + ';box-shadow:0 0 10px ' + ACCENT + '}' +
            '.__ring{position:fixed;left:0;top:0;width:12px;height:12px;border-radius:50%;pointer-events:none;z-index:2147483647;' +
              'border:2px solid ' + ACCENT + '}' +
            '.__conf{position:fixed;top:-20px;width:9px;height:14px;pointer-events:none;z-index:2147483647;border-radius:2px}';
          document.head.appendChild(css);

          var INTERACTIVE = 'button,[role=button],a[href],label,summary,select,input[type=checkbox],input[type=radio],.btn,.chip,.tab';
          function sparkle(x, y){
            if (reduce) return;
            var ring = document.createElement('div'); ring.className = '__ring';
            document.body.appendChild(ring);
            ring.animate([{transform:'translate('+(x-6)+'px,'+(y-6)+'px) scale(.4)',opacity:.9},
                          {transform:'translate('+(x-6)+'px,'+(y-6)+'px) scale(3.2)',opacity:0}],
                         {duration:420,easing:'cubic-bezier(.2,.8,.2,1)'}).onfinish = function(){ ring.remove(); };
            for (var i = 0; i < 7; i++) {
              var s = document.createElement('div'); s.className = '__spark';
              var a = (Math.PI * 2 * i / 7) + Math.random() * .5, d = 26 + Math.random() * 22;
              var size = .5 + Math.random() * .7;
              document.body.appendChild(s);
              (function(s){
                s.animate([{transform:'translate('+(x-3)+'px,'+(y-3)+'px) scale('+size+')',opacity:1},
                           {transform:'translate('+(x-3+Math.cos(a)*d)+'px,'+(y-3+Math.sin(a)*d)+'px) scale(0)',opacity:0}],
                          {duration:520+Math.random()*200,easing:'cubic-bezier(.15,.8,.3,1)'}).onfinish = function(){ s.remove(); };
              })(s);
            }
          }
          document.addEventListener('pointerdown', function(e){
            var t = e.target && e.target.closest && e.target.closest(INTERACTIVE);
            if (!t || t.disabled) return;
            fx('tap');
            sparkle(e.clientX, e.clientY);
          }, {passive:true, capture:true});
          document.addEventListener('change', function(e){
            var t = e.target;
            if (t && (t.type === 'checkbox' || t.type === 'radio' || t.tagName === 'SELECT' || t.type === 'range')) fx('select');
          }, true);

          window.__shellConfetti = function(){
            if (reduce) return;
            var colors = [ACCENT, '#ffffff', '#ffd166', '#ff6b9a', '#7cf5ff', '#a78bfa'];
            var W = window.innerWidth, H = window.innerHeight;
            for (var i = 0; i < 90; i++) {
              var c = document.createElement('div'); c.className = '__conf';
              c.style.left = (Math.random() * W) + 'px';
              c.style.background = colors[i % colors.length];
              document.body.appendChild(c);
              var drift = (Math.random() - .5) * 160, spin = (Math.random() - .5) * 1440;
              (function(c){
                c.animate([{transform:'translate(0,0) rotate(0deg)',opacity:1},
                           {transform:'translate('+drift+'px,'+(H+60)+'px) rotate('+spin+'deg)',opacity:.85}],
                          {duration:1600+Math.random()*1400,delay:Math.random()*300,easing:'cubic-bezier(.25,.6,.4,1)'})
                 .onfinish = function(){ c.remove(); };
              })(c);
            }
          };
        })();
        """
    }
}
