(function () {
    'use strict';

    // WebKit refuses to navigate a loadHTMLString page to a file:// URL outside
    // its own base directory, and does it without consulting the navigation
    // delegate — so a link to a sibling document would just do nothing. Catch
    // the click here and hand the href to the app instead.
    //
    // In-page anchors (#section) are left alone: WebKit scrolls to those itself,
    // and the delegate does get asked about them.

    function anchorFor(node) {
        while (node && node !== document) {
            if (node.tagName && node.tagName.toLowerCase() === 'a' && node.hasAttribute('href')) {
                return node;
            }
            node = node.parentNode;
        }
        return null;
    }

    document.addEventListener('click', function (event) {
        if (event.defaultPrevented || event.button !== 0) return;

        var anchor = anchorFor(event.target);
        if (!anchor) return;

        var href = anchor.getAttribute('href');
        if (!href || href.charAt(0) === '#') return;

        var handler = window.webkit
            && window.webkit.messageHandlers
            && window.webkit.messageHandlers.marklensLink;
        if (!handler) return;  // No bridge — let the delegate try its luck.

        event.preventDefault();
        handler.postMessage(href);
    }, true);
})();
