(function () {
    'use strict';

    var marks = [];
    var currentIndex = -1;
    var lastQuery = '';

    var SKIP_SELECTOR = '.mermaid, svg, script, style, mark.ml-find';

    function escapeRegex(s) {
        return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    }

    function clear() {
        for (var i = 0; i < marks.length; i++) {
            var m = marks[i];
            var parent = m.parentNode;
            if (!parent) continue;
            while (m.firstChild) parent.insertBefore(m.firstChild, m);
            parent.removeChild(m);
            parent.normalize();
        }
        marks = [];
        currentIndex = -1;
        lastQuery = '';
    }

    function shouldSkip(node) {
        var el = node.parentElement;
        while (el) {
            if (el.matches && el.matches(SKIP_SELECTOR)) return true;
            el = el.parentElement;
        }
        return false;
    }

    function collectTextNodes(root, regex) {
        var hits = [];
        var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: function (node) {
                if (!node.nodeValue || !node.nodeValue.length) return NodeFilter.FILTER_REJECT;
                if (shouldSkip(node)) return NodeFilter.FILTER_REJECT;
                regex.lastIndex = 0;
                return regex.test(node.nodeValue) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            }
        });
        var node;
        while ((node = walker.nextNode())) hits.push(node);
        return hits;
    }

    function wrapMatches(textNode, regex) {
        var text = textNode.nodeValue;
        var parent = textNode.parentNode;
        if (!parent) return;
        var lastIdx = 0;
        var match;
        regex.lastIndex = 0;
        var frag = document.createDocumentFragment();
        while ((match = regex.exec(text)) !== null) {
            if (match.index > lastIdx) {
                frag.appendChild(document.createTextNode(text.slice(lastIdx, match.index)));
            }
            var mark = document.createElement('mark');
            mark.className = 'ml-find';
            mark.textContent = match[0];
            frag.appendChild(mark);
            marks.push(mark);
            lastIdx = match.index + match[0].length;
            if (match[0].length === 0) regex.lastIndex++;
        }
        if (lastIdx < text.length) {
            frag.appendChild(document.createTextNode(text.slice(lastIdx)));
        }
        parent.replaceChild(frag, textNode);
    }

    function selectMatch(i) {
        if (currentIndex >= 0 && currentIndex < marks.length) {
            marks[currentIndex].classList.remove('ml-find-current');
        }
        currentIndex = i;
        if (i >= 0 && i < marks.length) {
            marks[i].classList.add('ml-find-current');
            marks[i].scrollIntoView({ block: 'center', behavior: 'auto' });
        }
    }

    function setQuery(q) {
        q = q == null ? '' : String(q);
        if (q === lastQuery) return [marks.length, currentIndex];
        clear();
        if (q.length === 0) return [0, -1];
        var article = document.querySelector('article#content');
        if (!article) return [0, -1];
        var regex = new RegExp(escapeRegex(q), 'gi');
        var nodes = collectTextNodes(article, regex);
        for (var i = 0; i < nodes.length; i++) {
            wrapMatches(nodes[i], regex);
        }
        lastQuery = q;
        if (marks.length > 0) selectMatch(0);
        return [marks.length, currentIndex];
    }

    function next() {
        if (marks.length === 0) return -1;
        selectMatch((currentIndex + 1) % marks.length);
        return currentIndex;
    }

    function previous() {
        if (marks.length === 0) return -1;
        selectMatch((currentIndex - 1 + marks.length) % marks.length);
        return currentIndex;
    }

    window.__marklensFind = {
        setQuery: setQuery,
        next: next,
        previous: previous,
        clear: clear
    };
})();
